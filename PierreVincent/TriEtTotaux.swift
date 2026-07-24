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

/// Calcule la SURFACE d'une œuvre à partir de son champ « Dimensions ».
///
/// Le champ est du texte libre, écrit de façons variées : « 73 × 92 cm »,
/// « 73x92 », « 73 x 92 cm », « 50 X 61 »… On extrait donc tous les nombres
/// présents et on multiplie les deux premiers.
///
/// Renvoie 0 si aucune dimension exploitable n'est trouvée (les entrées sans
/// dimensions se retrouvent ainsi regroupées en début de tri).
func surfaceDimensions(_ texte: String) -> Double {
    var nombres: [Double] = []
    var courant = ""

    // On parcourt le texte et on isole les suites de chiffres
    // (en acceptant la virgule ou le point comme séparateur décimal).
    for c in texte {
        if c.isNumber {
            courant.append(c)
        } else if c == "," || c == "." {
            // Séparateur décimal : on le normalise en point.
            courant.append(".")
        } else {
            if !courant.isEmpty {
                if let v = Double(courant) { nombres.append(v) }
                courant = ""
            }
        }
    }
    if !courant.isEmpty, let v = Double(courant) { nombres.append(v) }

    // Deux nombres ou plus : largeur × hauteur.
    if nombres.count >= 2 { return nombres[0] * nombres[1] }
    // Un seul nombre : on le prend tel quel (mieux que rien pour ordonner).
    if nombres.count == 1 { return nombres[0] }
    return 0
}
