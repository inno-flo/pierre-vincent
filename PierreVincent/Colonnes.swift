import Foundation

/// Décrit une colonne d'une feuille : son titre affiché et comment lire/écrire
/// sa valeur dans une Oeuvre. Cela permet de générer les tableaux, le tri,
/// les exports CSV/Excel et le PDF sans dupliquer le code.
struct Colonne: Identifiable {
    let id = UUID()
    let titre: String
    let cle: CleColonne
}

/// Les clés possibles d'une colonne (correspond aux champs de Oeuvre).
enum CleColonne {
    case photo
    case prix
    case type
    case dimensions
    case format
    case vendeur
    case acheteur
    case date
    case destinataire
    case remarques

    /// Le texte affiché pour cette colonne d'une entrée donnée
    /// (sert au tri, au CSV et au PDF ; la photo renvoie son nom de fichier).
    func texte(pour o: Oeuvre) -> String {
        switch self {
        case .photo:        return o.photoNom
        case .prix:         return String(format: "%.2f", o.prix)
        case .type:         return o.type
        case .dimensions:   return o.dimensions
        case .format:       return o.format
        case .vendeur:      return o.vendeur
        case .acheteur:     return o.acheteur
        case .date:         return o.date
        case .destinataire: return o.destinataire
        case .remarques:    return o.remarques
        }
    }

    /// Écrit une valeur texte dans le bon champ de l'entrée (édition directe).
    /// Le prix est converti depuis le texte saisi.
    func definir(_ valeur: String, sur o: Oeuvre) {
        switch self {
        case .photo:        o.photoNom = valeur   // rarement utilisé directement
        case .prix:
            let net = valeur
                .replacingOccurrences(of: "€", with: "")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ",", with: ".")
            o.prix = Double(net) ?? o.prix
        case .type:         o.type = valeur
        case .dimensions:   o.dimensions = valeur
        case .format:       o.format = valeur
        case .vendeur:      o.vendeur = valeur
        case .acheteur:     o.acheteur = valeur
        case .date:         o.date = valeur
        case .destinataire: o.destinataire = valeur
        case .remarques:    o.remarques = valeur
        }
    }

    /// Vrai si cette colonne est éditable directement au clavier (pas la photo).
    var editable: Bool {
        if case .photo = self { return false }
        return true
    }

    /// Valeur de comparaison pour le tri (le prix se trie numériquement).
    func cleTri(pour o: Oeuvre) -> (Double?, String) {
        switch self {
        case .prix: return (o.prix, "")
        default:    return (nil, texte(pour: o).lowercased())
        }
    }

    /// Largeur par défaut de la colonne (avant tout redimensionnement).
    var largeurDefaut: CGFloat {
        switch self {
        case .photo: return 60
        case .prix: return 100
        case .remarques: return 240
        case .type, .format: return 100
        default: return 140
        }
    }
}

/// Fournit la liste ordonnée des colonnes selon la feuille.
enum SchemaFeuille {

    static let colonnesVente: [Colonne] = [
        Colonne(titre: "Photo",      cle: .photo),
        Colonne(titre: "Prix",       cle: .prix),
        Colonne(titre: "Type",       cle: .type),
        Colonne(titre: "Dimensions", cle: .dimensions),
        Colonne(titre: "Format",     cle: .format),
        Colonne(titre: "Vendeur",    cle: .vendeur),
        Colonne(titre: "Acheteur",   cle: .acheteur),
        Colonne(titre: "Date",       cle: .date),
        Colonne(titre: "Remarques",  cle: .remarques),
    ]

    static let colonnesDon: [Colonne] = [
        Colonne(titre: "Photo",        cle: .photo),
        Colonne(titre: "Destinataire", cle: .destinataire),
        Colonne(titre: "Type",         cle: .type),
        Colonne(titre: "Dimensions",   cle: .dimensions),
        Colonne(titre: "Format",       cle: .format),
        Colonne(titre: "Remarques",    cle: .remarques),
    ]

    static func colonnes(pour feuille: Feuille) -> [Colonne] {
        switch feuille {
        case .oeuvresDonnees: return colonnesDon
        default:              return colonnesVente
        }
    }

    static let colonnesOeuvres: [Colonne] = colonnesVente
}
