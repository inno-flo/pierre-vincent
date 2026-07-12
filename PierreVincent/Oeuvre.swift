import Foundation
import SwiftData

/// Les cinq feuilles possibles de l'application.
/// Chaque entrée appartient à une feuille (sauf « Œuvres » qui est une vue compilée).
enum Feuille: String, Codable, CaseIterable {
    case tableauxVendus = "Tableaux vendus"
    case dessinsVendus  = "Dessins vendus"
    case tapisVendus    = "Tapis vendus"
    case oeuvresDonnees = "Œuvres données"
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
    var acheteur: String = ""
    var date: String = ""

    // Champ de la feuille « données »
    var destinataire: String = ""

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
