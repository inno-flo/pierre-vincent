import Foundation
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Échange de la base entre Mac et iPhone via un fichier unique.
///
/// Principe : le Mac exporte toutes les œuvres et leurs images dans UN SEUL
/// fichier JSON (les images sont encodées en base64 à l'intérieur). Ce fichier
/// est transféré sur l'iPhone (par iCloud Drive / Fichiers), où l'app le lit et
/// RECONSTRUIT la base — en remplaçant les données existantes.
///
/// Le fichier porte l'extension « .pvbase » (pour « Pierre-Vincent base »).
enum EchangeBase {

    static let extensionFichier = "pvbase"
    static let nomFichierDefaut = "PierreVincent.pvbase"

    // MARK: Modèle de transport (une œuvre sérialisable en JSON)

    /// Copie « plate » d'une œuvre, avec son image encodée en base64.
    struct OeuvreExport: Codable, Sendable {
        var feuille: String
        var type: String
        var dimensions: String
        var format: String
        var remarques: String
        var prix: Double
        var vendeur: String
        var modeVente: String
        var acheteur: String
        var date: String
        var destinataire: String
        // Champs ajoutés après la version 1 du format. Optionnels : un Codable
        // synthétisé n'applique PAS les valeurs par défaut aux clés absentes,
        // donc un .pvbase exporté avant leur ajout deviendrait illisible s'ils
        // étaient obligatoires.
        var statut: String?
        var theme: String?
        /// OPTIONNEL comme tout champ ajouté après coup : un `Codable`
        /// synthétisé n'applique pas les valeurs par défaut aux clés absentes,
        /// et un fichier exporté avant l'ajout deviendrait illisible.
        var collectionPersonnelle: String?
        var lieuStockage: String?
        var emplacement: String?
        /// OPTIONNEL, même raison que les champs ci-dessus.
        var favori: Bool?
        // Image encodée en base64 (vide si aucune photo).
        var imageBase64: String
        var imageExtension: String   // "png", "jpeg"… (pour ré-enregistrer)
    }

    /// Enveloppe du fichier : version + liste des œuvres.
    struct Fichier: Codable, Sendable {
        var version: Int
        var oeuvres: [OeuvreExport]
    }

    // MARK: Export (Mac)

    /// Construit le fichier d'échange à partir de toutes les œuvres.
    /// Les images sont lues sur le disque et encodées dans le JSON.
    ///
    /// **`async`, en DEUX temps.** Les propriétés d'une `Oeuvre` (modèle
    /// SwiftData) ne se lisent que sur `MainActor` : on en prend donc d'abord
    /// un instantané `Sendable`, images exclues. La partie lourde — lecture des
    /// fichiers, encodage base64, encodage JSON — part ensuite dans une tâche
    /// détachée. Tout faire sur le fil principal y gelait l'interface le temps
    /// d'encoder TOUTES les photos de la base.
    @MainActor
    static func exporter(oeuvres: [Oeuvre]) async throws -> Data {
        // 1. Instantané sur MainActor : le champ image reste vide à ce stade,
        //    seul le nom de fichier est retenu pour la seconde étape.
        var liste: [OeuvreExport] = []
        var photos: [String] = []
        for o in oeuvres {
            photos.append(o.photoNom)
            liste.append(OeuvreExport(
                feuille: o.feuilleBrute,
                type: o.type,
                dimensions: o.dimensions,
                format: o.format,
                remarques: o.remarques,
                prix: o.prix,
                vendeur: o.vendeur,
                modeVente: o.modeVente,
                acheteur: o.acheteur,
                date: o.date,
                destinataire: o.destinataire,
                statut: o.statut,
                theme: o.theme,
                collectionPersonnelle: o.collectionPersonnelle,
                lieuStockage: o.lieuStockage,
                emplacement: o.emplacement,
                favori: o.favori,
                imageBase64: "",
                imageExtension: ""))
        }

        // 2. Hors MainActor : lecture disque, base64 et encodage JSON.
        let instantane = liste
        let noms = photos
        return try await Task.detached(priority: .userInitiated) {
            var finale = instantane
            for i in finale.indices where !noms[i].isEmpty {
                guard let url = PhotoStore.urlPhoto(nom: noms[i]),
                      let data = try? Data(contentsOf: url) else { continue }
                finale[i].imageBase64 = data.base64EncodedString()
                finale[i].imageExtension = url.pathExtension.isEmpty
                    ? "png" : url.pathExtension
            }
            return try JSONEncoder().encode(Fichier(version: 1, oeuvres: finale))
        }.value
    }

    // MARK: Import (iPhone surtout, mais fonctionne aussi sur Mac)

    /// Résultat de l'import.
    struct Resultat { let importees: Int; let erreur: String? }

    /// Lit un fichier d'échange et REMPLACE la base : supprime toutes les
    /// œuvres existantes (et leurs photos), puis recrée tout depuis le fichier.
    ///
    /// **`async`, en TROIS temps** : le décodage JSON puis l'écriture des
    /// images (décodage base64 + écriture disque) se font hors de `MainActor`,
    /// qui ne garde que les mutations SwiftData. Tout enchaîner sur le fil
    /// principal y gelait l'interface pendant tout l'import d'une grosse base —
    /// c'est ce que la pastille « Import en cours » ne faisait que signaler.
    @MainActor
    static func importerEnRemplacant(donnees: Data, context: ModelContext) async -> Resultat {
        // 1. Décodage du fichier, hors MainActor.
        let fichier: Fichier
        do {
            fichier = try await Task.detached(priority: .userInitiated) {
                try JSONDecoder().decode(Fichier.self, from: donnees)
            }.value
        } catch {
            return Resultat(importees: 0, erreur: "Fichier illisible ou format inattendu.")
        }

        // 2. Effacer l'existant (œuvres + photos sur disque).
        do {
            let toutes = try context.fetch(FetchDescriptor<Oeuvre>())
            for o in toutes {
                if !o.photoNom.isEmpty { PhotoStore.supprimerPhoto(nom: o.photoNom) }
                context.delete(o)
            }
        } catch {
            return Resultat(importees: 0, erreur: "Impossible de vider la base existante.")
        }

        // 3. Écrire TOUTES les images hors MainActor, en une passe : décodage
        //    base64 et écriture disque sont le gros du travail d'un import.
        //    On n'en rapporte que les noms de fichiers créés, indexés comme
        //    `fichier.oeuvres` — des `String?`, donc Sendable.
        let entrees = fichier.oeuvres
        let nomsPhotos: [String?] = await Task.detached(priority: .userInitiated) {
            entrees.map { e in
                guard !e.imageBase64.isEmpty,
                      let data = Data(base64Encoded: e.imageBase64) else { return nil }
                return PhotoStore.enregistrerDonnees(data, extension: e.imageExtension)
            }
        }.value

        // 4. Recréer chaque œuvre sur MainActor — mutations SwiftData seules.
        var compte = 0
        for (index, e) in fichier.oeuvres.enumerated() {
            let feuille = Feuille(rawValue: e.feuille) ?? .tableauxVendus
            let o = Oeuvre(feuille: feuille)
            o.type         = e.type
            o.dimensions   = e.dimensions
            o.format       = e.format
            o.remarques    = e.remarques
            o.prix         = e.prix
            o.vendeur      = e.vendeur
            o.modeVente    = e.modeVente
            o.acheteur     = e.acheteur
            o.date         = e.date
            o.destinataire = e.destinataire
            o.statut       = e.statut ?? ""
            o.theme        = e.theme ?? ""
            o.collectionPersonnelle = e.collectionPersonnelle ?? ""
            o.lieuStockage = e.lieuStockage ?? ""
            o.emplacement  = e.emplacement ?? ""
            o.favori       = e.favori ?? false

            // Filet : le statut fait foi sur l'appartenance à la Réserve.
            // La feuille voyage en TEXTE et se relit avec un repli sur
            // « Tableaux vendus » (voir plus haut) : un fichier écrit avant
            // l'existence de la feuille « Réserve », ou lu par une version qui
            // ne la connaît pas encore, ferait atterrir les œuvres détenues
            // parmi les tableaux vendus — silencieusement. Le rattrapage ne
            // peut pas venir de `RepriseDonnees` : ses passes tournent au
            // lancement, donc AVANT l'import, et leur drapeau est déjà consommé.
            if estEnReserve(o) { o.feuille = .reserve }

            // Image : déjà écrite sur disque à l'étape 2b, il ne reste qu'à
            // reprendre son nom. Les octets du base64 sont écrits DIRECTEMENT,
            // sans passer par une image en mémoire (bien plus léger et rapide).
            if let nom = nomsPhotos[index] {
                o.photoNom = nom
            }

            context.insert(o)
            compte += 1

            // Sauvegarde intermédiaire tous les 25 éléments : libère la mémoire
            // et évite d'accumuler tout le travail jusqu'à la fin.
            if compte % 25 == 0 {
                try? context.save()
            }
        }

        try? context.save()
        return Resultat(importees: compte, erreur: nil)
    }
}
