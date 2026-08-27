#if os(macOS)
import Foundation
import SwiftData

/// Recompression des photos déjà en base, pour rattraper celles entrées avant
/// que toutes les voies d'import passent par `importerImageCompressee`.
///
/// **Pourquoi cet outil existe.** L'import CSV appelait `enregistrer(image:)`,
/// qui ré-encode en PNG : une photo légère y devenait plusieurs mégaoctets. Le
/// défaut est corrigé pour les imports à venir, mais les fichiers déjà écrits
/// restent lourds sur le disque — et alourdissent le cache de vignettes, les
/// exports et surtout le fichier d'échange `.pvbase`, construit entièrement en
/// mémoire.
///
/// **Ce n'est PAS une passe de `RepriseDonnees`.** Les reprises tournent au
/// lancement, sur le fil principal : recompresser des centaines d'images à ce
/// moment-là gèlerait l'app à chaque démarrage, exactement le défaut qu'on
/// cherche à supprimer. C'est donc une commande explicite du menu Fichier, que
/// l'utilisateur déclenche quand il le décide.
///
/// **L'opération n'est pas annulable** : elle réécrit des fichiers sur le
/// disque. L'appelant DOIT demander confirmation, et `analyser` est là pour que
/// cette confirmation annonce des chiffres réels plutôt qu'une promesse vague.
enum RecompressionPhotos {

    /// État des lieux, sans rien modifier.
    struct Bilan {
        /// Photos dépassant le seuil, donc concernées.
        let concernees: Int
        /// Poids cumulé de ces photos, en octets.
        let poidsActuel: Int64
        /// Poids total de toutes les photos référencées.
        let poidsTotal: Int64

        var rienAFaire: Bool { concernees == 0 }
    }

    /// Résultat d'une exécution.
    struct Resultat {
        let recompressees: Int
        let echecs: Int
        let octetsAvant: Int64
        let octetsApres: Int64

        var octetsGagnes: Int64 { max(0, octetsAvant - octetsApres) }
    }

    /// Poids d'un fichier photo, ou 0 s'il est illisible.
    nonisolated private static func poids(_ nom: String) -> Int64 {
        guard !nom.isEmpty,
              let url = PhotoStore.urlPhoto(nom: nom),
              let attributs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let octets = attributs[.size] as? Int64 else { return 0 }
        return octets
    }

    /// Compte les photos à recompresser et pèse le dossier.
    ///
    /// Passe par les ŒUVRES et non par le contenu du dossier : une photo
    /// orpheline n'a pas à être recompressée, elle a vocation à disparaître au
    /// prochain nettoyage.
    @MainActor
    static func analyser(oeuvres: [Oeuvre]) async -> Bilan {
        let noms = oeuvres.map(\.photoNom).filter { !$0.isEmpty }
        return await Task.detached(priority: .userInitiated) {
            var concernees = 0
            var poidsActuel: Int64 = 0
            var poidsTotal: Int64 = 0
            for nom in noms {
                let p = poids(nom)
                poidsTotal += p
                if p > Int64(PhotoStore.poidsMaxImport) {
                    concernees += 1
                    poidsActuel += p
                }
            }
            return Bilan(concernees: concernees,
                         poidsActuel: poidsActuel,
                         poidsTotal: poidsTotal)
        }.value
    }

    /// Recompresse toutes les photos dépassant le seuil.
    ///
    /// Déroulé, par œuvre :
    /// 1. peser le fichier ; sous le seuil, on ne touche à rien ;
    /// 2. fabriquer un NOUVEAU fichier compressé (nom UUID distinct) ;
    /// 3. n'écrire `photoNom` **qu'une fois le nouveau fichier en place** ;
    /// 4. supprimer l'ancien seulement après.
    ///
    /// Cet ordre est ce qui rend l'opération sûre : une panne à n'importe quel
    /// moment laisse l'œuvre pointant sur un fichier valide — l'ancien si on
    /// n'a pas fini, le nouveau sinon. Le pire résidu possible est un fichier
    /// orphelin, que le nettoyage au lancement effacera.
    ///
    /// La compression se fait hors du fil principal ; seule l'écriture du champ
    /// `photoNom` (donc SwiftData) revient sur `MainActor`.
    @MainActor
    static func executer(oeuvres: [Oeuvre], context: ModelContext) async -> Resultat {
        // Seules les œuvres réellement concernées, pesées une fois pour toutes.
        let candidates: [(oeuvre: Oeuvre, poids: Int64)] = await {
            let noms = oeuvres.map(\.photoNom)
            let poidsParIndex = await Task.detached(priority: .userInitiated) {
                noms.map { $0.isEmpty ? Int64(0) : poids($0) }
            }.value
            return oeuvres.enumerated().compactMap { index, o in
                let p = poidsParIndex[index]
                guard p > Int64(PhotoStore.poidsMaxImport) else { return nil }
                return (o, p)
            }
        }()

        guard !candidates.isEmpty else {
            return Resultat(recompressees: 0, echecs: 0, octetsAvant: 0, octetsApres: 0)
        }

        // Progression en pied de sidebar, comme l'import de photos.
        let suivi = ProgressionImport.partagee
        suivi.demarrer(total: candidates.count)
        defer { suivi.terminer() }

        var recompressees = 0
        var echecs = 0
        var octetsAvant: Int64 = 0
        var octetsApres: Int64 = 0

        for (oeuvre, poidsAvant) in candidates {
            let ancienNom = oeuvre.photoNom
            guard let url = PhotoStore.urlPhoto(nom: ancienNom) else {
                echecs += 1
                suivi.avancer()
                continue
            }

            // Compression hors MainActor : c'est tout le travail lourd.
            let nouveauNom = await Task.detached(priority: .userInitiated) {
                PhotoStore.importerImageCompressee(depuis: url)
            }.value

            guard let nouveauNom else {
                // Photo illisible ou encodage impossible : on la LAISSE telle
                // quelle. Mieux vaut un fichier lourd qu'une photo perdue.
                echecs += 1
                suivi.avancer()
                continue
            }

            let poidsApres = poids(nouveauNom)
            // Garde-fou : si la « recompression » n'a rien gagné, on garde
            // l'original et on jette le nouveau fichier. Cas possible sur une
            // image déjà optimisée dont le ré-encodage HEIC serait plus lourd.
            guard poidsApres > 0, poidsApres < poidsAvant else {
                PhotoStore.supprimerPhoto(nom: nouveauNom)
                suivi.avancer()
                continue
            }

            oeuvre.photoNom = nouveauNom          // 3. la base pointe sur le neuf
            PhotoStore.supprimerPhoto(nom: ancienNom)   // 4. l'ancien peut partir

            recompressees += 1
            octetsAvant += poidsAvant
            octetsApres += poidsApres
            suivi.avancer()
        }

        try? context.save()
        return Resultat(recompressees: recompressees, echecs: echecs,
                        octetsAvant: octetsAvant, octetsApres: octetsApres)
    }

    /// Formate un nombre d'octets pour l'affichage (« 1,2 Go »).
    static func formater(_ octets: Int64) -> String {
        let formateur = ByteCountFormatter()
        formateur.countStyle = .file
        return formateur.string(fromByteCount: octets)
    }
}
#endif
