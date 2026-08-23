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
func correspond(_ o: Oeuvre, statuts: [String], types: [String],
                themes: [String] = [], emplacements: [String] = []) -> Bool {
    func egal(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(b.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
    guard statuts.contains(where: { egal(o.statut, $0) }) else { return false }
    guard types.isEmpty || types.contains(where: { egal(o.type, $0) }) else { return false }
    guard themes.isEmpty || themes.contains(where: { egal(o.theme, $0) }) else { return false }
    // Emplacement : test par INCLUSION et non par égalité. La valeur stockée
    // nomme le carton (« Collection personnelle carton 3 ») ; la rubrique, elle,
    // désigne la collection entière.
    guard emplacements.isEmpty || emplacements.contains(where: {
        o.emplacement.localizedCaseInsensitiveContains($0)
    }) else { return false }
    return true
}

/// Les seuls types d'œuvre possibles, dans l'ordre du menu de l'éditeur.
///
/// Liste **fermée** : le champ `type` était en saisie libre et portait parfois
/// une technique (« Huile sur toile », « Aquarelle »), ce qui rendait muets
/// les filtres par type — une œuvre ainsi renseignée n'apparaissait dans
/// aucune rubrique de catégorie.
let typesOeuvre: [String] = ["Dessin", "Tableau", "Tapis"]

/// Statuts recensés par la section « Réserve » : les œuvres encore détenues.
/// Défini ici, et non dans `Categorie`, pour que les rubriques de la sidebar
/// et la reprise de données `remplirFeuilleReserve` s'accordent toujours.
let statutsReserve: [String] = ["Disponible", "À garder"]

/// Statut donné à une œuvre importée par photo dont aucun mot-clé ne dit le
/// sort. Une œuvre photographiée à l'atelier n'a été ni vendue ni donnée.
///
/// **Ce repli est indispensable** : un statut VIDE ne satisfait ni
/// `estVenduOuDonne` ni `estEnReserve`, et l'œuvre n'apparaît alors dans
/// AUCUNE rubrique — tout en étant bien en base, donc comptée à l'export.
let statutParDefautImport = "Disponible"

/// Vrai si l'œuvre est encore détenue, d'après son seul statut.
func estEnReserve(_ o: Oeuvre) -> Bool {
    statutsReserve.contains { $0.caseInsensitiveCompare(o.statut) == .orderedSame }
}

/// Feuilles dont les œuvres n'ont pas de prix à montrer : les dons, par
/// principe, et la Réserve, dont les œuvres n'ont pas encore été vendues.
let feuillesSansPrix: Set<Feuille> = [.oeuvresDonnees, .reserve]

/// Vrai si l'œuvre a un prix à afficher.
///
/// **Se lit sur l'ŒUVRE, jamais sur la rubrique affichée** : dans les vues
/// agrégées (Catalogue, Ventes) la feuille de la rubrique vaut `nil`. Sans ce
/// test, une œuvre sans prix affiche « 0 € » sous sa vignette — le bug déjà
/// rencontré sur les dons, que la Réserve rejouerait à l'identique.
func aUnPrix(_ o: Oeuvre) -> Bool {
    !feuillesSansPrix.contains(o.feuille)
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
