import Foundation

/// Sens du tri d'une colonne.
enum SensTri {
    case ascendant
    case descendant
}

/// Applique un tri sur une liste d'œuvres selon une colonne et un sens.
func trier(_ oeuvres: [Oeuvre], par cle: CleColonne, sens: SensTri) -> [Oeuvre] {
    let triees = oeuvres.sorted { a, b in
        let (na, sa) = cle.cleTri(pour: a)
        let (nb, sb) = cle.cleTri(pour: b)
        if let na = na, let nb = nb {
            return na < nb
        }
        return sa < sb
    }
    return sens == .ascendant ? triees : triees.reversed()
}

/// Formate une somme en euros selon la locale française.
func formaterEuros(_ montant: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "EUR"
    f.locale = Locale(identifier: "fr_FR")
    // Pas de centimes : on affiche des montants ronds (40 € et non 40,00 €).
    f.minimumFractionDigits = 0
    f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: montant)) ?? "\(Int(montant)) €"
}

/// Calcule la somme totale de la colonne Prix pour une liste d'œuvres.
func totalPrix(_ oeuvres: [Oeuvre]) -> Double {
    oeuvres.reduce(0) { $0 + $1.prix }
}
