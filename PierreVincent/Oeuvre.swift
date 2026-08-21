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
