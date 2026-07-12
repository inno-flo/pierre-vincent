import Foundation
import SwiftData

/// Point d'accès partagé au gestionnaire d'annulation de la base SwiftData.
/// On le crée une seule fois et on l'attache au contexte principal, puis on le
/// réutilise pour les commandes Annuler/Rétablir du menu (Cmd Z / Cmd Maj Z).
///
/// Pourquoi ce détour : sur macOS, le menu Édition standard vise le gestionnaire
/// d'annulation de la fenêtre, pas celui de SwiftData. En gardant une référence
/// directe ici, on câble Cmd Z sur le BON gestionnaire.
@MainActor
final class GestionAnnulation {
    static let shared = GestionAnnulation()
    let undoManager = UndoManager()

    private init() {}
}
