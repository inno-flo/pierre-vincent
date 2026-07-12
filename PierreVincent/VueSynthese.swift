import SwiftUI
import SwiftData

/// Tableau de bord « Synthèse » : agrège les données des autres catégories.
/// Deux blocs : Ventes (tableaux, dessins, tapis) et Dons (tableaux, dessins).
struct VueSynthese: View {
    // Toutes les entrées ; on filtre par feuille dans les calculs.
    let toutes: [Oeuvre]

    // MARK: Sous-ensembles par feuille

    private var tableauxVendus: [Oeuvre] { toutes.filter { $0.feuille == .tableauxVendus } }
    private var dessinsVendus:  [Oeuvre] { toutes.filter { $0.feuille == .dessinsVendus } }
    private var tapisVendus:    [Oeuvre] { toutes.filter { $0.feuille == .tapisVendus } }
    private var oeuvresDonnees: [Oeuvre] { toutes.filter { $0.feuille == .oeuvresDonnees } }

    // Dons séparés par type (le type est saisi dans le champ « Type »).
    // On considère comme « tableau » ou « dessin » selon le texte du type.
    private var tableauxDonnes: [Oeuvre] {
        oeuvresDonnees.filter { $0.type.localizedCaseInsensitiveContains("tableau") }
    }
    private var dessinsDonnes: [Oeuvre] {
        oeuvresDonnees.filter { $0.type.localizedCaseInsensitiveContains("dessin") }
    }

    // MARK: Statistiques de prix

    /// Prix min, max et moyen d'une liste (en ignorant les prix nuls/0).
    private func stats(_ liste: [Oeuvre]) -> (min: Double, max: Double, moyenne: Double) {
        let prix = liste.map { $0.prix }.filter { $0 > 0 }
        guard !prix.isEmpty else { return (0, 0, 0) }
        let somme = prix.reduce(0, +)
        return (prix.min() ?? 0, prix.max() ?? 0, somme / Double(prix.count))
    }

    private func somme(_ liste: [Oeuvre]) -> Double {
        liste.reduce(0) { $0 + $1.prix }
    }

    // Somme des ventes par maison d'enchères (champ Vendeur).
    private func sommeVendeur(_ nom: String) -> Double {
        let cible = nom.trimmingCharacters(in: .whitespaces).lowercased()
        let ventes = tableauxVendus + dessinsVendus + tapisVendus
        return ventes
            .filter { $0.vendeur.trimmingCharacters(in: .whitespaces).lowercased() == cible }
            .reduce(0) { $0 + $1.prix }
    }

    // MARK: Corps

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                blocVentes
                blocDons
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .navigationTitle("Synthèse")
    }

    // MARK: Bloc Ventes

    private var blocVentes: some View {
        let statT = stats(tableauxVendus)
        let statD = stats(dessinsVendus)
        let sommeTableaux = somme(tableauxVendus)
        let sommeDessins  = somme(dessinsVendus)
        let sommeTapis    = somme(tapisVendus)
        let sommeTotale   = sommeTableaux + sommeDessins + sommeTapis

        return carte(titre: "Ventes", systemImage: "eurosign.circle") {
            groupe("Œuvres") {
                ligne("Tableaux vendus", "\(tableauxVendus.count)")
                ligne("Dessins vendus", "\(dessinsVendus.count)")
                ligne("Tapis vendus", "\(tapisVendus.count)")
            }

            groupe("Prix des tableaux") {
                ligne("Le plus bas", formaterEuros(statT.min))
                ligne("Le plus haut", formaterEuros(statT.max))
                ligne("Prix moyen", formaterEuros(statT.moyenne))
            }

            groupe("Prix des dessins") {
                ligne("Le plus bas", formaterEuros(statD.min))
                ligne("Le plus haut", formaterEuros(statD.max))
                ligne("Prix moyen", formaterEuros(statD.moyenne))
            }

            groupe("Sommes des ventes") {
                ligne("Tableaux", formaterEuros(sommeTableaux))
                ligne("Dessins", formaterEuros(sommeDessins))
                ligne("Tapis", formaterEuros(sommeTapis))
                ligne("Total (tableaux + dessins + tapis)", formaterEuros(sommeTotale),
                      gras: true)
            }

            groupe("Ventes par maison d'enchères") {
                ligne("Artenchères", formaterEuros(sommeVendeur("Artenchères")))
                ligne("Drôme Enchères", formaterEuros(sommeVendeur("Drôme Enchères")))
            }
        }
    }

    // MARK: Bloc Dons

    private var blocDons: some View {
        carte(titre: "Dons", systemImage: "gift") {
            groupe("Œuvres") {
                ligne("Tableaux donnés", "\(tableauxDonnes.count)")
                ligne("Dessins donnés", "\(dessinsDonnes.count)")
            }
        }
    }

    // MARK: Briques d'affichage réutilisables

    /// Une carte titrée (bloc principal).
    /// Le titre est aligné à gauche (comme la sidebar) et souligné d'un filet
    /// qui court jusqu'au bord droit de la colonne des chiffres.
    private func carte<Contenu: View>(titre: String, systemImage: String,
                                      @ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label(titre, systemImage: systemImage)
                    .font(.title2.weight(.semibold))
                // Filet sous le titre, sur toute la largeur du contenu.
                Divider()
            }
            contenu()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Un sous-groupe titré à l'intérieur d'une carte.
    private func groupe<Contenu: View>(_ titre: String,
                                       @ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titre)
                .font(.headline)
                .foregroundStyle(.primary)
            contenu()
        }
    }

    /// Une ligne « libellé …… valeur ».
    private func ligne(_ libelle: String, _ valeur: String, gras: Bool = false) -> some View {
        HStack {
            Text(libelle)
            Spacer()
            Text(valeur)
                .font(gras ? .body.weight(.semibold) : .body)
                .monospacedDigit()
        }
    }
}
