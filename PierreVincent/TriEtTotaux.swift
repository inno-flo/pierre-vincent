import Foundation

/// Valeur affichable d'un champ de suivi (statut, thème, emplacement).
/// Ces trois champs s'affichent TOUJOURS, même vides : le bloc doit rester
/// complet et lisible, avec « Inconnu » à la place d'une ligne manquante.
let valeurInconnue = "Inconnu"

func afficher(_ valeur: String) -> String {
    valeur.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? valeurInconnue : valeur
}

/// Statuts recensés par la section « Ventes et dons ».
///
/// TOUTES les rubriques de cette section — Inventaire, Tableaux, Dessins,
/// Tapis, Dons, Ventes — ne montrent que les œuvres SORTIES du fonds :
/// vendues ou données. Les œuvres encore disponibles, notamment celles
/// importées depuis des photos, relèvent de la section « Réserve ».
let statutsVentesEtDons: Set<String> = ["Vendu", "Donné"]

/// Vrai si l'œuvre satisfait les filtres de statut et de type d'une rubrique.
/// `types` vide = aucun filtre de type. Comparaisons insensibles à la casse et
/// aux espaces de bord, les valeurs étant saisies à la main.
func correspond(_ o: Oeuvre, statuts: [String], types: [String]) -> Bool {
    func egal(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(b.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
    guard statuts.contains(where: { egal(o.statut, $0) }) else { return false }
    guard types.isEmpty || types.contains(where: { egal(o.type, $0) }) else { return false }
    return true
}

/// Vrai si l'œuvre relève du canal choisi dans le filtre rapide de la vue
/// « Ventes ».
///
/// Le menu mélange deux natures de critère : trois **vendeurs** (Artenchères,
/// Drôme Enchères, RempART) et un **mode de vente** (Vente privée). On teste
/// donc les deux champs — un seul suffit à retenir l'œuvre.
func correspondAuCanal(_ o: Oeuvre, canal: String) -> Bool {
    func egal(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(b.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
    return egal(o.vendeur, canal) || egal(o.modeVente, canal)
}

/// Vrai si l'œuvre relève de la section « Ventes et dons ».
func estVenduOuDonne(_ o: Oeuvre) -> Bool {
    statutsVentesEtDons.contains(o.statut)
}

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

/// Formatter partagé pour l'affichage des euros. Construit une seule fois
/// (un NumberFormatter est coûteux à instancier) et réutilisé à chaque appel
/// de `formaterEuros` : cette fonction est appelée très souvent (chaque ligne
/// de tableau, chaque tuile de la Synthèse, chaque vignette de galerie), donc
/// en recréer un à chaque fois ralentissait inutilement l'affichage.
private let formatteurEuros: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "EUR"
    f.locale = Locale(identifier: "fr_FR")
    // Pas de centimes : on affiche des montants ronds (40 € et non 40,00 €).
    f.minimumFractionDigits = 0
    f.maximumFractionDigits = 0
    return f
}()

/// Formate une somme en euros selon la locale française.
func formaterEuros(_ montant: Double) -> String {
    formatteurEuros.string(from: NSNumber(value: montant)) ?? "\(Int(montant)) €"
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
