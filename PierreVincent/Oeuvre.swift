import Foundation
import SwiftData

/// Les cinq feuilles possibles de l'application.
/// Chaque entrée appartient à une feuille (sauf « Œuvres » qui est une vue compilée).
enum Feuille: String, Codable, CaseIterable {
    case tableauxVendus = "Tableaux vendus"
    case dessinsVendus  = "Dessins vendus"
    case tapisVendus    = "Tapis vendus"
    case oeuvresDonnees = "Œuvres données"
    /// Œuvres encore détenues. Les quatre feuilles ci-dessus viennent des
    /// onglets du tableur d'origine et disent DEUX choses à la fois : le genre
    /// d'objet et son sort (« Tableaux vendus »). Aucune ne convient donc à une
    /// œuvre qui n'a jamais quitté l'atelier — d'où cette cinquième, qui ne
    /// dit que le sort. Le genre, lui, se lit sur le champ `type`.
    case reserve = "Réserve"
}

/// Une œuvre = une ligne dans une feuille.
/// On stocke TOUS les champs possibles ici. Les feuilles « vendues »
/// utilisent le prix + vendeur + acheteur + date ; la feuille « données »
/// utilise le destinataire à la place. Les champs inutilisés restent vides.
@Model
final class Oeuvre {
    // Identifiant unique (utile pour nommer les fichiers photo à l'export)
    var id: UUID = UUID()

    // À quelle feuille appartient cette entrée
    var feuilleBrute: String = Feuille.tableauxVendus.rawValue

    // Le nom de fichier de la photo (stockée à part dans le dossier de l'app).
    // Vide si aucune photo.
    var photoNom: String = ""

    // Champs communs
    var type: String = ""
    var dimensions: String = ""
    var format: String = ""
    var remarques: String = ""

    // Champs des feuilles « vendues »
    var prix: Double = 0
    var vendeur: String = ""
    var modeVente: String = ""
    var acheteur: String = ""
    var date: String = ""

    // Champ de la feuille « données »
    var destinataire: String = ""

    // Champs communs ajoutés pour le suivi des œuvres.
    // Valeur par défaut vide : SwiftData migre la base existante tout seul
    // (migration légère), sans perte de données.
    var statut: String = ""
    var theme: String = ""
    /// « Oui » si l'œuvre relève de la collection personnelle, vide sinon.
    /// Renseigné à l'import par les mots-clés « à garder ». Texte et non
    /// booléen, pour rester homogène avec les autres champs et voyager tel
    /// quel dans les exports.
    var collectionPersonnelle: String = ""
    /// Où l'œuvre est entreposée — « Bourg-de-Péage », « Domicile ».
    /// Renseigné à l'import par les mots-clés « Stockage … ».
    /// Distinct d'`emplacement`, qui nomme le carton à l'intérieur du lieu.
    var lieuStockage: String = ""
    var emplacement: String = ""

    // Date technique de création de l'entrée (pour l'ordre par défaut)
    var creeLe: Date = Date()

    init(feuille: Feuille) {
        self.feuilleBrute = feuille.rawValue
    }

    /// Accès pratique à la feuille sous forme d'enum.
    var feuille: Feuille {
        get { Feuille(rawValue: feuilleBrute) ?? .tableauxVendus }
        set { feuilleBrute = newValue.rawValue }
    }
}

// MARK: Reprise de données

/// Opérations ponctuelles sur la base existante, exécutées une seule fois.
enum RepriseDonnees {

    /// Renseigne le Statut par défaut des œuvres dont il est encore vide :
    /// « Donné » pour les dons, « Vendu » pour toutes les autres.
    ///
    /// Ne touche jamais un statut déjà renseigné : l'opération est donc sans
    /// risque si elle venait à être relancée, et elle n'écrase pas une saisie
    /// manuelle. Renvoie le nombre d'œuvres modifiées.
    @discardableResult
    @MainActor
    static func remplirStatutParDefaut(context: ModelContext) -> Int {
        guard let toutes = try? context.fetch(FetchDescriptor<Oeuvre>()) else { return 0 }
        var compte = 0
        for o in toutes where o.statut.isEmpty {
            o.statut = (o.feuille == .oeuvresDonnees) ? "Donné" : "Vendu"
            compte += 1
        }
        if compte > 0 { try? context.save() }
        return compte
    }

    /// Écrit « Inconnu » dans tous les champs texte encore vides.
    ///
    /// Convention de la base : un champ non renseigné contient « Inconnu »,
    /// et non une chaîne vide. L'éditeur fait la conversion inverse à la
    /// lecture, pour que l'utilisateur n'ait pas à effacer ce mot avant de
    /// saisir (voir `EditeurEntree`).
    ///
    /// `photoNom` est exclu : c'est un champ technique, dont le vide signifie
    /// « aucune photo » et non « inconnu ».
    @discardableResult
    @MainActor
    static func remplirChampsVides(context: ModelContext) -> Int {
        guard let toutes = try? context.fetch(FetchDescriptor<Oeuvre>()) else { return 0 }
        let champs: [ReferenceWritableKeyPath<Oeuvre, String>] = [
            \.type, \.dimensions, \.format, \.remarques,
            \.vendeur, \.modeVente, \.acheteur, \.date,
            \.destinataire, \.statut, \.theme, \.emplacement,
            // `collectionPersonnelle` est ABSENT volontairement : son vide
            // signifie « non », pas « on ne sait pas ». Y écrire « Inconnu »
            // rendrait le filtre de la rubrique inopérant.
        ]
        var compte = 0
        for o in toutes {
            var modifiee = false
            for champ in champs
            where o[keyPath: champ].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                o[keyPath: champ] = valeurInconnue
                modifiee = true
            }
            if modifiee { compte += 1 }
        }
        if compte > 0 { try? context.save() }
        return compte
    }

    /// Harmonise le champ Dimensions au modèle « 60x50 » : pas d'espaces
    /// autour du séparateur, pas d'unité.
    ///
    /// **Conservatrice par construction** : `normaliserDimensions` ne renvoie
    /// une valeur que si TOUTES les parties sont des nombres. « Inconnu »,
    /// une note libre (« H 65 x L 50 »), un format inattendu sont laissés
    /// intacts plutôt que mutilés — le champ est en saisie libre, on ne peut
    /// pas présumer de ce qu'il contient.
    @discardableResult
    @MainActor
    static func normaliserDimensions(context: ModelContext) -> Int {
        guard let toutes = try? context.fetch(FetchDescriptor<Oeuvre>()) else { return 0 }
        var compte = 0
        for o in toutes {
            if let normalisee = RepriseDonnees.normaliserDimensions(o.dimensions) {
                o.dimensions = normalisee
                compte += 1
            }
        }
        if compte > 0 { try? context.save() }
        return compte
    }

    /// Forme normalisée d'une valeur de Dimensions, ou `nil` si elle n'est pas
    /// reconnue — ou qu'elle est déjà au bon format, auquel cas il n'y a rien
    /// à écrire.
    ///
    /// Accepte les séparateurs `x`, `X` et `×`, l'unité « cm » finale, les
    /// espaces, et les décimales à la virgule comme au point.
    static func normaliserDimensions(_ brut: String) -> String? {
        var valeur = brut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !valeur.isEmpty else { return nil }

        // Unité finale, collée ou non au dernier nombre.
        if valeur.lowercased().hasSuffix("cm") {
            valeur = String(valeur.dropLast(2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let separateurs: Set<Character> = ["x", "X", "×"]
        let parties = valeur.split(whereSeparator: { separateurs.contains($0) })
        guard parties.count >= 2 else { return nil }

        var nombres: [String] = []
        for partie in parties {
            let n = partie.trimmingCharacters(in: .whitespacesAndNewlines)
            // Tout sauf un nombre fait abandonner : mieux vaut ne rien
            // toucher que de perdre une information qu'on n'a pas su lire.
            guard !n.isEmpty,
                  n.allSatisfy({ $0.isNumber || $0 == "," || $0 == "." })
            else { return nil }
            nombres.append(n)
        }

        let normalisee = nombres.joined(separator: "x")
        return normalisee == brut ? nil : normalisee
    }

    /// **PURGE — supprime les doublons d'un import de photos répété.**
    ///
    /// Critère : feuille « Tableaux vendus » ET statut de réserve. Cette
    /// combinaison est contradictoire — une œuvre disponible n'a pas été
    /// vendue — et n'apparaît donc dans AUCUNE rubrique : ni « Ventes et
    /// dons », qui veut Vendu ou Donné, ni la Réserve, qui veut la feuille
    /// `.reserve`. Aucune œuvre légitime ne peut y correspondre.
    ///
    /// Elle vient d'imports faits avant que `ImportPhotos` n'aligne la feuille
    /// sur le statut : le statut était lu des mots-clés, la feuille restait au
    /// repli `.tableauxVendus`. Vérifié sur l'export : 683 enregistrements de
    /// ce type pour 630 noms de fichier, tous déjà présents dans la Réserve.
    ///
    /// La photo n'est effacée que si **aucune œuvre conservée ne s'en sert** —
    /// sans quoi supprimer un doublon aveuglerait son jumeau.
    @discardableResult
    @MainActor
    static func supprimerDoublonsImport(context: ModelContext) -> Int {
        guard let toutes = try? context.fetch(FetchDescriptor<Oeuvre>()) else { return 0 }
        let cibles = toutes.filter { $0.feuille == .tableauxVendus && estEnReserve($0) }
        guard !cibles.isEmpty else { return 0 }

        let idsCibles = Set(cibles.map(\.id))
        let photosConservees = Set(
            toutes.filter { !idsCibles.contains($0.id) }.map(\.photoNom)
        )

        for o in cibles {
            if !o.photoNom.isEmpty, !photosConservees.contains(o.photoNom) {
                PhotoStore.supprimerPhoto(nom: o.photoNom)
            }
            context.delete(o)
        }
        try? context.save()
        return cibles.count
    }

    /// **PURGE — supprime DÉFINITIVEMENT toutes les œuvres de la Réserve**,
    /// leurs photos comprises.
    ///
    /// Opération ponctuelle demandée pour reprendre à zéro un import de photos
    /// dont les mots-clés n'étaient pas encore reconnus. Ce n'est PAS une
    /// reprise de données : elle détruit, elle ne répare pas.
    ///
    /// Le critère est la seule feuille `.reserve` — le plus simple à vérifier.
    /// Elle emporte donc aussi les premiers dessins d'essai.
    ///
    /// Comme toutes les passes, elle a son drapeau et ne se rejoue pas. **Ne
    /// pas la rebrancher sans nouveau drapeau** : un lancement suffirait à
    /// effacer une Réserve reconstituée entre-temps.
    @discardableResult
    @MainActor
    static func purgerReserve(context: ModelContext) -> Int {
        guard let toutes = try? context.fetch(FetchDescriptor<Oeuvre>()) else { return 0 }
        var compte = 0
        for o in toutes where o.feuille == .reserve {
            // La photo est hors base : la supprimer explicitement, sinon elle
            // resterait sur disque sans plus rien pour la référencer.
            if !o.photoNom.isEmpty { PhotoStore.supprimerPhoto(nom: o.photoNom) }
            context.delete(o)
            compte += 1
        }
        if compte > 0 { try? context.save() }
        return compte
    }

    /// Convertit le statut « À garder » en « Disponible ».
    ///
    /// La table de correspondance de l'import fait désormais converger les six
    /// mots-clés — « disponible », « à garder », « à garder absolument », pour
    /// les tableaux comme pour les dessins — vers « Disponible » : la nuance
    /// dit une intention du propriétaire, pas le sort de l'œuvre. Sans cette
    /// passe, la base porterait deux statuts pour une même réalité, selon la
    /// date d'import.
    ///
    /// Elle ÉCRASE une valeur existante, comme `remplirFeuilleReserve` et
    /// `renommerThemePortrait`, et reste rejouable : plus aucune œuvre ne porte
    /// l'ancienne valeur ensuite.
    @discardableResult
    @MainActor
    static func convertirAGarderEnDisponible(context: ModelContext) -> Int {
        guard let toutes = try? context.fetch(FetchDescriptor<Oeuvre>()) else { return 0 }
        var compte = 0
        for o in toutes
        where o.statut.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("À garder") == .orderedSame {
            o.statut = statutParDefautImport
            compte += 1
        }
        if compte > 0 { try? context.save() }
        return compte
    }

    /// Rattrape les œuvres au statut VIDE, invisibles dans toutes les vues.
    ///
    /// Cas rencontré après un import de photos sans mots-clés IPTC : l'œuvre
    /// entre en base, l'export la compte, mais aucune rubrique ne la montre —
    /// un statut vide ne satisfait ni `estVenduOuDonne` ni `estEnReserve`.
    ///
    /// **Le vide est un marqueur fiable ici** : la passe `remplirChampsVides`
    /// a écrit « Inconnu » dans tous les champs texte vides d'alors. Une œuvre
    /// au statut réellement vide est donc forcément postérieure, donc issue
    /// d'un import de photos.
    @discardableResult
    @MainActor
    static func reparerStatutsVides(context: ModelContext) -> Int {
        guard let toutes = try? context.fetch(FetchDescriptor<Oeuvre>()) else { return 0 }
        var compte = 0
        for o in toutes
        where o.statut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            o.statut = statutParDefautImport
            o.feuille = .reserve
            compte += 1
        }
        if compte > 0 { try? context.save() }
        return compte
    }

    /// Renomme le thème « Personnage » en « Portrait ».
    ///
    /// La table de correspondance de l'import photos écrit désormais
    /// « Portrait » ; sans cette passe, les deux valeurs coexisteraient et la
    /// sidebar afficherait DEUX rubriques « Portraits », une par valeur
    /// stockée, sans que rien ne l'explique à l'écran.
    ///
    /// Comme `remplirFeuilleReserve`, elle écrase une valeur existante — c'est
    /// tout son objet — et reste rejouable sans danger : une fois la bascule
    /// faite, plus aucune œuvre ne porte l'ancienne valeur.
    @discardableResult
    @MainActor
    static func renommerThemePortrait(context: ModelContext) -> Int {
        guard let toutes = try? context.fetch(FetchDescriptor<Oeuvre>()) else { return 0 }
        var compte = 0
        for o in toutes
        where o.theme.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("Personnage") == .orderedSame {
            o.theme = "Portrait"
            compte += 1
        }
        if compte > 0 { try? context.save() }
        return compte
    }

    /// Bascule sur la feuille « Réserve » les œuvres encore détenues.
    ///
    /// À la différence des reprises ci-dessus, celle-ci **écrase** une valeur
    /// existante : `feuille` n'est jamais vide, elle vaut par défaut
    /// « Tableaux vendus ». Elle reste sans danger et rejouable, le statut
    /// suffisant à décider — une œuvre disponible n'a par définition été ni
    /// vendue ni donnée.
    @discardableResult
    @MainActor
    static func remplirFeuilleReserve(context: ModelContext) -> Int {
        guard let toutes = try? context.fetch(FetchDescriptor<Oeuvre>()) else { return 0 }
        var compte = 0
        for o in toutes where estEnReserve(o) && o.feuille != .reserve {
            o.feuille = .reserve
            compte += 1
        }
        if compte > 0 { try? context.save() }
        return compte
    }

    /// Renseigne le Mode de vente « Don » sur les œuvres de la feuille
    /// « Œuvres données » dont ce champ est encore vide.
    ///
    /// Même précaution que ci-dessus : aucune valeur existante n'est écrasée.
    @discardableResult
    @MainActor
    static func remplirModeVenteDon(context: ModelContext) -> Int {
        guard let toutes = try? context.fetch(FetchDescriptor<Oeuvre>()) else { return 0 }
        var compte = 0
        for o in toutes where o.feuille == .oeuvresDonnees && o.modeVente.isEmpty {
            o.modeVente = "Don"
            compte += 1
        }
        if compte > 0 { try? context.save() }
        return compte
    }
}
