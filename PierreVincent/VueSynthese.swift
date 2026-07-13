import SwiftUI
import SwiftData

/// Tableau de bord « Synthèse » : blocs de statistiques inspirés du prototype.
/// Chaque bloc a un petit titre en haut, un grand chiffre, et une info secondaire.
struct VueSynthese: View {
    let toutes: [Oeuvre]

    // MARK: Sous-ensembles par feuille

    private var tableauxVendus: [Oeuvre] { toutes.filter { $0.feuille == .tableauxVendus } }
    private var dessinsVendus:  [Oeuvre] { toutes.filter { $0.feuille == .dessinsVendus } }
    private var tapisVendus:    [Oeuvre] { toutes.filter { $0.feuille == .tapisVendus } }
    private var oeuvresDonnees: [Oeuvre] { toutes.filter { $0.feuille == .oeuvresDonnees } }

    private var tableauxDonnes: [Oeuvre] {
        oeuvresDonnees.filter { $0.type.localizedCaseInsensitiveContains("tableau") }
    }
    private var dessinsDonnes: [Oeuvre] {
        oeuvresDonnees.filter { $0.type.localizedCaseInsensitiveContains("dessin") }
    }

    // MARK: Statistiques

    private func stats(_ liste: [Oeuvre]) -> (min: Double, max: Double, moyenne: Double) {
        let prix = liste.map { $0.prix }.filter { $0 > 0 }
        guard !prix.isEmpty else { return (0, 0, 0) }
        let somme = prix.reduce(0, +)
        return (prix.min() ?? 0, prix.max() ?? 0, somme / Double(prix.count))
    }

    private func somme(_ liste: [Oeuvre]) -> Double {
        liste.reduce(0) { $0 + $1.prix }
    }

    private func sommeVendeur(_ nom: String) -> Double {
        let cible = nom.trimmingCharacters(in: .whitespaces).lowercased()
        let ventes = tableauxVendus + dessinsVendus + tapisVendus
        return ventes
            .filter { $0.vendeur.trimmingCharacters(in: .whitespaces).lowercased() == cible }
            .reduce(0) { $0 + $1.prix }
    }

    // Grille adaptative de blocs.
    private let colonnes = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                // --- Rangée 1 : nombres d'œuvres ---
                section("Œuvres") {
                    bloc(titre: "Tableaux vendus",
                         valeur: "\(tableauxVendus.count)",
                         detail: formaterEuros(somme(tableauxVendus)),
                         icone: "paintpalette")
                    bloc(titre: "Dessins vendus",
                         valeur: "\(dessinsVendus.count)",
                         detail: formaterEuros(somme(dessinsVendus)),
                         icone: "pencil.and.outline")
                    bloc(titre: "Tapis vendus",
                         valeur: "\(tapisVendus.count)",
                         detail: formaterEuros(somme(tapisVendus)),
                         icone: "square.grid.3x3.square")
                    bloc(titre: "Tableaux donnés",
                         valeur: "\(tableauxDonnes.count)",
                         detail: "—",
                         icone: "gift")
                    bloc(titre: "Dessins donnés",
                         valeur: "\(dessinsDonnes.count)",
                         detail: "—",
                         icone: "gift")
                }

                // --- Rangée 2 : prix et sommes ---
                section("Montants") {
                    let sT = stats(tableauxVendus)
                    let sD = stats(dessinsVendus)
                    blocMulti(titre: "Prix des tableaux", lignes: [
                        ("Le plus bas", formaterEuros(sT.min)),
                        ("Le plus haut", formaterEuros(sT.max)),
                        ("Prix moyen", formaterEuros(sT.moyenne))
                    ])
                    blocMulti(titre: "Prix des dessins", lignes: [
                        ("Le plus bas", formaterEuros(sD.min)),
                        ("Le plus haut", formaterEuros(sD.max)),
                        ("Prix moyen", formaterEuros(sD.moyenne))
                    ])
                    blocMulti(titre: "Somme des ventes", lignes: [
                        ("Tableaux", formaterEuros(somme(tableauxVendus))),
                        ("Dessins", formaterEuros(somme(dessinsVendus))),
                        ("Tapis", formaterEuros(somme(tapisVendus))),
                        ("Total", formaterEuros(somme(tableauxVendus) + somme(dessinsVendus) + somme(tapisVendus)))
                    ])
                }

                // --- Rangée 3 : enchères et expositions ---
                section("Enchères et expositions") {
                    bloc(titre: "Artenchères",
                         valeur: formaterEuros(sommeVendeur("Artenchères")),
                         detail: "")
                    bloc(titre: "Drôme Enchères",
                         valeur: formaterEuros(sommeVendeur("Drôme Enchères")),
                         detail: "")
                    bloc(titre: "RempART",
                         valeur: formaterEuros(sommeVendeur("RempART")),
                         detail: "")
                }
            }
            .padding(20)
        }
        .navigationTitle("Synthèse")
    }

    // MARK: Composants

    /// Une section titrée contenant une grille de blocs.
    @ViewBuilder
    private func section<Contenu: View>(_ titre: String,
                                        @ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titre)
                .font(.title3.weight(.semibold))
            LazyVGrid(columns: colonnes, alignment: .leading, spacing: 16) {
                contenu()
            }
        }
    }

    /// Bloc simple : petit titre (avec icône), grand chiffre, détail secondaire.
    private func bloc(titre: String, valeur: String, detail: String,
                      icone: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icone {
                    Image(systemName: icone)
                        .foregroundStyle(.black)
                }
                Text(titre)
                    .font(.subheadline)
                    .foregroundStyle(.black)
            }
            Text(valeur)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
            if !detail.isEmpty {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .padding(16)
        .background(fondBloc)
    }

    /// Bloc multi-lignes : un titre et plusieurs paires libellé/valeur.
    private func blocMulti(titre: String, lignes: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titre)
                .font(.subheadline)
                .foregroundStyle(.black)
            ForEach(lignes, id: \.0) { libelle, valeur in
                HStack {
                    Text(libelle).foregroundStyle(.black)
                    Spacer()
                    Text(valeur).font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .font(.callout)
            }
            Spacer(minLength: 0)   // pousse le contenu vers le haut
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .padding(16)
        .background(fondBloc)
    }

    /// Fond arrondi commun aux blocs : orange international.
    private var fondBloc: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(red: 1.0, green: 0.31, blue: 0.0))
    }
}
