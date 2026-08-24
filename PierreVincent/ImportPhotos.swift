#if os(macOS)
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Importe des œuvres directement depuis des fichiers image.
///
/// Chaque photo devient une entrée : la photo est réduite et compressée sous
/// 450 Ko (voir `PhotoStore.importerImageCompressee`), et ses **mots-clés
/// IPTC** — ceux saisis dans Photos — alimentent les champs de l'œuvre.
///
/// Volontairement séparé de `Import`, qui est un moteur CSV : l'entrée, la
/// source des données et le traitement diffèrent en tout, et les deux n'ont
/// aucune étape en commun.
enum ImportPhotos {

    struct Resultat {
        let importees: Int
        let ignorees: Int
        let erreur: String?
    }

    /// Images à importer pour un élément choisi dans le panneau.
    ///
    /// Un fichier se renvoie lui-même ; un **dossier** est parcouru en
    /// profondeur et rend toutes les images qu'il contient, sous-dossiers
    /// compris. Les fichiers cachés sont ignorés.
    private static func imagesContenues(dans url: URL) -> [URL] {
        let gestionnaire = FileManager.default
        var estDossier: ObjCBool = false
        guard gestionnaire.fileExists(atPath: url.path, isDirectory: &estDossier) else { return [] }

        guard estDossier.boolValue else {
            return estUneImage(url) ? [url] : []
        }

        guard let parcours = gestionnaire.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }

        var trouvees: [URL] = []
        for cas in parcours {
            guard let fichier = cas as? URL, estUneImage(fichier) else { continue }
            trouvees.append(fichier)
        }
        // Ordre stable : le parcours du système ne garantit rien.
        return trouvees.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Vrai si le fichier relève d'un des types acceptés (JPEG, PNG, HEIC).
    private static func estUneImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return PhotoStore.typesAcceptes.contains { type.conforms(to: $0) }
    }

    /// Crée une œuvre par fichier image fourni.
    ///
    /// **`async`** : l'import rend la main entre deux fichiers
    /// (`await Task.yield()`), sans quoi la boucle monopolise le fil principal
    /// et l'interface ne se redessine qu'à la fin — aucun compteur ne pourrait
    /// bouger.
    /// - Parameters:
    ///   - fichiers: les images choisies dans le sélecteur.
    ///   - feuilleCible: la feuille de destination (rubrique affichée).
    @MainActor
    static func importer(fichiers: [URL],
                         feuilleCible: Feuille,
                         context: ModelContext) async -> Resultat {
        guard !fichiers.isEmpty else {
            return Resultat(importees: 0, ignorees: 0, erreur: "Aucun fichier choisi.")
        }

        var importees = 0
        var ignorees = 0
        // Identifiants des œuvres créées, pour permettre « Annuler
        // l'importation » (voir `DernierImport`).
        var creees: [UUID] = []

        // Accès sécurisé : les éléments choisis viennent de l'extérieur du bac
        // à sable. Les autorisations sont ouvertes ICI et tenues ouvertes
        // pendant TOUT l'import — un fichier trouvé dans un dossier n'a pas
        // d'autorisation propre, il dépend de celle du dossier qui le contient.
        var autorises: [URL] = []
        defer { autorises.forEach { $0.stopAccessingSecurityScopedResource() } }

        var aTraiter: [URL] = []
        for choix in fichiers {
            if choix.startAccessingSecurityScopedResource() { autorises.append(choix) }
            aTraiter += imagesContenues(dans: choix)
        }

        guard !aTraiter.isEmpty else {
            return Resultat(importees: 0, ignorees: 0,
                            erreur: "Aucune image trouvée dans la sélection.")
        }

        let suivi = ProgressionImport.partagee
        suivi.demarrer(total: aTraiter.count)
        defer { suivi.terminer() }

        for fichier in aTraiter {

            // Métadonnées LUES AVANT la compression : la version stockée est
            // ré-encodée et ne conserve pas l'IPTC d'origine.
            let motsCles = PhotoStore.motsCles(de: fichier)
            let legende = PhotoStore.legende(de: fichier)
            let nomFichier = fichier.deletingPathExtension().lastPathComponent

            guard let nomStocke = PhotoStore.importerImageCompressee(depuis: fichier) else {
                ignorees += 1
                continue
            }

            let oeuvre = Oeuvre(feuille: feuilleCible)
            oeuvre.photoNom = nomStocke
            CorrespondanceMotsCles.appliquer(motsCles: motsCles,
                                             legende: legende,
                                             nomFichier: nomFichier,
                                             sur: oeuvre)

            // Filet : sans mot-clé de statut, l'œuvre resterait avec un statut
            // vide et n'apparaîtrait dans aucune rubrique (voir
            // `statutParDefautImport`). Les photos prises à l'atelier ne
            // portent pas toujours d'IPTC.
            if oeuvre.statut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                oeuvre.statut = statutParDefautImport
            }
            // La feuille suit le statut, comme à l'import .pvbase : la rubrique
            // d'où part l'import ne dit rien du sort de l'œuvre.
            if estEnReserve(oeuvre) { oeuvre.feuille = .reserve }

            context.insert(oeuvre)
            creees.append(oeuvre.id)
            importees += 1

            // Rend la main : c'est ce qui permet à la sidebar d'afficher la
            // progression au fur et à mesure, et non d'un seul coup à la fin.
            suivi.avancer()
            await Task.yield()
        }

        if importees > 0 { try? context.save() }
        // Remplace la mémoire du dernier import, même si rien n'a été créé :
        // sans cela, « Annuler l'importation » viserait encore le lot d'avant.
        DernierImport.enregistrer(creees)

        if importees == 0 {
            return Resultat(importees: 0, ignorees: ignorees,
                            erreur: "Aucune image n'a pu être lue.")
        }
        return Resultat(importees: importees, ignorees: ignorees, erreur: nil)
    }
}

/// Progression de l'import en cours, affichée en pied de sidebar (macOS).
///
/// `@Observable` et non `ObservableObject` : ce dernier réclame
/// `import Combine` depuis Swift 6.
@MainActor
@Observable
final class ProgressionImport {
    static let partagee = ProgressionImport()
    private init() {}

    private(set) var enCours = false
    private(set) var traites = 0
    private(set) var total = 0

    func demarrer(total: Int) {
        self.total = total
        traites = 0
        enCours = true
    }

    func avancer() { traites += 1 }

    func terminer() {
        enCours = false
        traites = 0
        total = 0
    }
}

/// Traduit les métadonnées d'une photo en champs d'une œuvre.
///
/// **C'est ici, et nulle part ailleurs, que se règle la correspondance.**
/// Ajouter un mot-clé revient à ajouter une entrée dans l'une des tables
/// ci-dessous ; rien d'autre n'est à toucher.
///
/// Les clés sont écrites en minuscules sans accent : la comparaison passe par
/// `normaliser`, si bien que « Dessin à garder » est reconnu même saisi
/// « dessin a garder » ou avec des espaces en trop.
enum CorrespondanceMotsCles {

    // MARK: Tables

    /// Mots-clés qui rangent l'œuvre dans la **collection personnelle**.
    ///
    /// Ils fixent AUSSI le statut « Disponible » via la table ci-dessous : ce
    /// sont deux informations distinctes portées par le même mot-clé, d'où un
    /// test à part et non une branche du `else if`.
    private static let collectionPersonnelle: Set<String> = [
        "tableau a garder",
        "tableau a garder absolument",
        "dessin a garder",
        "dessin a garder absolument",
    ]

    /// Mot-clé → valeur du champ **Statut**.
    ///
    /// Les six mots-clés donnent tous « Disponible » : la nuance « à garder »,
    /// voire « absolument », dit une intention du propriétaire, pas le sort de
    /// l'œuvre — laquelle est dans tous les cas encore détenue. Les clés sont
    /// écrites sans accent, `normaliser` repliant les diacritiques.
    ///
    /// Pas d'entrée pour les tapis : il n'en reste aucun de disponible.
    private static let statuts: [String: String] = [
        "dessin disponible":            "Disponible",
        "dessin a garder":              "Disponible",
        "dessin a garder absolument":   "Disponible",
        "tableau disponible":           "Disponible",
        "tableau a garder":             "Disponible",
        "tableau a garder absolument":  "Disponible",
    ]

    /// Mot-clé → valeur du champ **Thème**.
    private static let themes: [String: String] = [
        "dessin bouquet":      "Bouquet",
        "dessin nature morte": "Nature morte",
        "dessin animaux":      "Animaux",
        "dessin paysage":      "Paysage",
        "dessin portrait":     "Portrait",
    ]

    /// Mot-clé → valeur du champ **Type**.
    private static let types: [String: String] = [
        "dessin pierre innocente": "Dessin",
    ]

    /// Mots-clés recopiés **à l'identique** dans le champ **Emplacement**.
    private static let emplacements: Set<String> = [
        "collection personnelle carton 1",
        "collection personnelle carton 2",
        "collection personnelle carton 3",
        "collection personnelle carton 4",
        "natures mortes carton 1",
        "natures mortes carton 2",
        "grands formats carton 1",
        "grands formats carton 2",
        "paysages carton 1",
        "paysages carton 2",
        "paysages carton 3",
        "personnages carton 1",
        "animaux carton 1",
        "bouquets carton 1",
    ]

    // MARK: Application

    @MainActor
    static func appliquer(motsCles: [String],
                          legende: String,
                          nomFichier: String,
                          sur o: Oeuvre) {
        var nonReconnus: [String] = []

        for mot in motsCles {
            let cle = normaliser(mot)
            // Testé AVANT l'aiguillage : un mot-clé « à garder » dit deux
            // choses — le sort de l'œuvre et son rangement — et doit donc
            // alimenter les deux champs.
            if collectionPersonnelle.contains(cle) {
                ecrire(valeurCollectionPersonnelle,
                       dans: \.collectionPersonnelle, sur: o)
            }
            if let v = statuts[cle] {
                ecrire(v, dans: \.statut, sur: o)
            } else if let v = themes[cle] {
                ecrire(v, dans: \.theme, sur: o)
            } else if let v = types[cle] {
                ecrire(v, dans: \.type, sur: o)
            } else if emplacements.contains(cle) {
                // Recopié tel quel, avec sa casse d'origine.
                ecrire(mot.trimmingCharacters(in: .whitespacesAndNewlines),
                       dans: \.emplacement, sur: o)
            } else {
                nonReconnus.append(mot)
            }
        }

        // Remarques : la légende du fichier, puis les mots-clés absents des
        // tables — signalés plutôt que perdus silencieusement — et enfin le
        // nom du fichier d'origine, que rien d'autre ne conserve (la photo est
        // stockée sous un nom généré).
        var lignes: [String] = []
        if !legende.isEmpty { lignes.append(legende) }
        for mot in nonReconnus { lignes.append("Mot clef non reconnu : \(mot)") }
        lignes.append("Fichier : \(nomFichier)")
        ecrire(lignes.joined(separator: "\n"), dans: \.remarques, sur: o)
    }

    // MARK: Outils

    /// N'écrit QUE si le champ est vide ou vaut « Inconnu » : une valeur déjà
    /// saisie n'est jamais écrasée. Couvre les deux conventions possibles —
    /// champ vide en base, ou « Inconnu » réellement stocké.
    @MainActor
    private static func ecrire(_ valeur: String,
                               dans champ: ReferenceWritableKeyPath<Oeuvre, String>,
                               sur o: Oeuvre) {
        let actuel = o[keyPath: champ].trimmingCharacters(in: .whitespacesAndNewlines)
        guard actuel.isEmpty || actuel.caseInsensitiveCompare(valeurInconnue) == .orderedSame
        else { return }
        o[keyPath: champ] = valeur
    }

    /// Minuscules, sans accent, sans espaces de bord : la comparaison tolère
    /// les variantes de saisie.
    private static func normaliser(_ texte: String) -> String {
        texte.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "fr_FR"))
    }
}

#endif
