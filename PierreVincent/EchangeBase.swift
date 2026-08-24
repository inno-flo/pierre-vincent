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
    struct OeuvreExport: Codable {
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
        var emplacement: String?
        // Image encodée en base64 (vide si aucune photo).
        var imageBase64: String
        var imageExtension: String   // "png", "jpeg"… (pour ré-enregistrer)
    }

    /// Enveloppe du fichier : version + liste des œuvres.
    struct Fichier: Codable {
        var version: Int
        var oeuvres: [OeuvreExport]
    }

    // MARK: Export (Mac)

    /// Construit le fichier d'échange à partir de toutes les œuvres.
    /// Les images sont lues sur le disque et encodées dans le JSON.
    @MainActor
    static func exporter(oeuvres: [Oeuvre]) throws -> Data {
        var liste: [OeuvreExport] = []
        for o in oeuvres {
            var b64 = ""
            var ext = ""
            if !o.photoNom.isEmpty,
               let url = PhotoStore.urlPhoto(nom: o.photoNom),
               let data = try? Data(contentsOf: url) {
                b64 = data.base64EncodedString()
                ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
            }
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
                emplacement: o.emplacement,
                imageBase64: b64,
                imageExtension: ext))
        }
        let fichier = Fichier(version: 1, oeuvres: liste)
        let encodeur = JSONEncoder()
        return try encodeur.encode(fichier)
    }

    // MARK: Import (iPhone surtout, mais fonctionne aussi sur Mac)

    /// Résultat de l'import.
    struct Resultat { let importees: Int; let erreur: String? }

    /// Lit un fichier d'échange et REMPLACE la base : supprime toutes les
    /// œuvres existantes (et leurs photos), puis recrée tout depuis le fichier.
    @MainActor
    static func importerEnRemplacant(donnees: Data, context: ModelContext) -> Resultat {
        let fichier: Fichier
        do {
            fichier = try JSONDecoder().decode(Fichier.self, from: donnees)
        } catch {
            return Resultat(importees: 0, erreur: "Fichier illisible ou format inattendu.")
        }

        // 1. Effacer l'existant (œuvres + photos sur disque).
        do {
            let toutes = try context.fetch(FetchDescriptor<Oeuvre>())
            for o in toutes {
                if !o.photoNom.isEmpty { PhotoStore.supprimerPhoto(nom: o.photoNom) }
                context.delete(o)
            }
        } catch {
            return Resultat(importees: 0, erreur: "Impossible de vider la base existante.")
        }

        // 2. Recréer chaque œuvre, en ré-enregistrant son image.
        var compte = 0
        for e in fichier.oeuvres {
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
            o.emplacement  = e.emplacement ?? ""

            // Filet : le statut fait foi sur l'appartenance à la Réserve.
            // La feuille voyage en TEXTE et se relit avec un repli sur
            // « Tableaux vendus » (voir plus haut) : un fichier écrit avant
            // l'existence de la feuille « Réserve », ou lu par une version qui
            // ne la connaît pas encore, ferait atterrir les œuvres détenues
            // parmi les tableaux vendus — silencieusement. Le rattrapage ne
            // peut pas venir de `RepriseDonnees` : ses passes tournent au
            // lancement, donc AVANT l'import, et leur drapeau est déjà consommé.
            if estEnReserve(o) { o.feuille = .reserve }

            // Image : on écrit DIRECTEMENT les octets décodés du base64, sans
            // les transformer en image en mémoire (bien plus léger et rapide).
            if !e.imageBase64.isEmpty,
               let data = Data(base64Encoded: e.imageBase64),
               let nom = PhotoStore.enregistrerDonnees(data, extension: e.imageExtension) {
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
