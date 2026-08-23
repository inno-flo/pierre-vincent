import Foundation
import SwiftData

/// Mémoire du **dernier import**, pour pouvoir l'annuler d'un coup.
///
/// Retient les identifiants des œuvres créées par le dernier import — photos
/// ou dossier CSV — et rien d'autre : l'annulation ne touche jamais une œuvre
/// saisie à la main, ni celles d'un import antérieur.
///
/// **Un seul import est mémorisé à la fois.** Un nouvel import remplace le
/// précédent : au-delà, il faudrait un historique, et l'annulation cesserait
/// d'être l'opération simple qu'elle doit rester.
///
/// La liste survit au redémarrage (elle est dans les réglages), mais elle est
/// vidée dès l'annulation faite — c'est ce qui grise la commande de menu.
@MainActor
enum DernierImport {
    private static let cleIdentifiants = "dernierImportIdentifiants"
    /// Drapeau lu par le menu « Fichier » pour activer ou griser la commande.
    /// Distinct de la liste : le menu vit dans `PierreVincentApp`, qui n'a pas
    /// à décoder les identifiants pour savoir s'il y a quelque chose à annuler.
    static let cleAnnulable = "importAnnulable"

    /// Enregistre les œuvres créées par un import, en remplaçant la mémoire
    /// précédente. Une liste vide efface la mémoire — rien à annuler.
    static func enregistrer(_ identifiants: [UUID]) {
        let reglages = UserDefaults.standard
        let textes = identifiants.map(\.uuidString)
        reglages.set(textes, forKey: cleIdentifiants)
        reglages.set(!textes.isEmpty, forKey: cleAnnulable)
    }

    /// Nombre d'œuvres annulables, pour l'annoncer dans la confirmation.
    static var nombre: Int {
        (UserDefaults.standard.stringArray(forKey: cleIdentifiants) ?? []).count
    }

    static var estAnnulable: Bool { nombre > 0 }

    /// Supprime les œuvres du dernier import, leurs photos comprises, puis
    /// oublie la liste. Renvoie le nombre réellement supprimé.
    ///
    /// Le nombre peut être inférieur à `nombre` : une œuvre du lot a pu être
    /// effacée à la main entre-temps. Ce n'est pas une anomalie.
    @discardableResult
    static func annuler(context: ModelContext) -> Int {
        let textes = UserDefaults.standard.stringArray(forKey: cleIdentifiants) ?? []
        let cibles = Set(textes.compactMap(UUID.init(uuidString:)))
        defer { enregistrer([]) }
        guard !cibles.isEmpty,
              let toutes = try? context.fetch(FetchDescriptor<Oeuvre>()) else { return 0 }

        var compte = 0
        for o in toutes where cibles.contains(o.id) {
            // La photo est stockée hors base : sans cette ligne, elle
            // resterait sur disque sans plus rien pour la référencer.
            if !o.photoNom.isEmpty { PhotoStore.supprimerPhoto(nom: o.photoNom) }
            context.delete(o)
            compte += 1
        }
        if compte > 0 { try? context.save() }
        return compte
    }
}
