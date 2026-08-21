#if os(macOS)
import Foundation
import SwiftData

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

    /// Crée une œuvre par fichier image fourni.
    /// - Parameters:
    ///   - fichiers: les images choisies dans le sélecteur.
    ///   - feuilleCible: la feuille de destination (rubrique affichée).
    @MainActor
    static func importer(fichiers: [URL],
                         feuilleCible: Feuille,
                         context: ModelContext) -> Resultat {
        guard !fichiers.isEmpty else {
            return Resultat(importees: 0, ignorees: 0, erreur: "Aucun fichier choisi.")
        }

        var importees = 0
        var ignorees = 0

        for fichier in fichiers {
            // Accès sécurisé : les fichiers viennent de l'extérieur du bac à sable.
            let acces = fichier.startAccessingSecurityScopedResource()
            defer { if acces { fichier.stopAccessingSecurityScopedResource() } }

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
            context.insert(oeuvre)
            importees += 1
        }

        if importees > 0 { try? context.save() }

        if importees == 0 {
            return Resultat(importees: 0, ignorees: ignorees,
                            erreur: "Aucune image n'a pu être lue.")
        }
        return Resultat(importees: importees, ignorees: ignorees, erreur: nil)
    }
}

/// Traduit les métadonnées d'une photo en champs d'une œuvre.
///
/// **C'est ici, et nulle part ailleurs, que se règle la correspondance.**
/// Tant que la table définitive n'est pas arrêtée, rien n'est perdu : les
/// mots-clés, la légende et le nom du fichier sont recopiés tels quels dans
/// les Remarques, prêts à être répartis dans les bons champs.
///
/// Exemple de mots-clés relevés sur les photos de test :
///   « Dessin disponible »      → Statut
///   « Dessin nature morte »    → Thème
///   « Natures mortes carton 2 »→ Emplacement
///   « Dessin Pierre Innocente »→ Type
enum CorrespondanceMotsCles {

    @MainActor
    static func appliquer(motsCles: [String],
                          legende: String,
                          nomFichier: String,
                          sur o: Oeuvre) {
        // --- Table de correspondance : À COMPLÉTER ---
        // Pour chaque mot-clé, décider du champ de destination puis écrire
        // par exemple `o.statut = mot`. Voir les préfixes ci-dessus.

        // En attendant, on conserve TOUT dans les Remarques : aucun import ne
        // perd d'information, et la répartition pourra se faire ensuite.
        var lignes: [String] = ["Fichier : \(nomFichier)"]
        if !legende.isEmpty { lignes.append("Légende : \(legende)") }
        if !motsCles.isEmpty {
            lignes.append("Mots-clés : " + motsCles.joined(separator: " · "))
        }
        o.remarques = lignes.joined(separator: "\n")
    }
}

#endif
