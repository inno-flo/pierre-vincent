import SwiftUI
import SwiftData

/// Tableau de bord « Synthèse », thème « Graphite » (sombre fixe).
///
/// Structure à deux niveaux (d'après la maquette Claude Design) :
///  - de grandes CARTES par section (Œuvres, Montants, Enchères) ;
///  - à l'intérieur, des TUILES (un ton plus clair) pour chaque élément.
/// L'orange de marque n'est utilisé que sur les valeurs chiffrées.
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

    // Grille des tuiles « Œuvres » : 2 colonnes façon maquette iPhone,
    // adaptative pour rester correcte sur les fenêtres larges du Mac.
    private let colonnesTuiles = [GridItem(.adaptive(minimum: 150, maximum: 320), spacing: 10)]

    // MARK: Corps

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // --- Carte ŒUVRES ---
                carte(titre: "Œuvres") {
                    #if os(iOS)
                    // Récapitulatif Vendues / Données, sous le titre Œuvres.
                    // Même grille que les tuiles en dessous, pour que « Vendues »
                    // tombe sous « Tableaux vendus » et « Données » sous
                    // « Dessins vendus ».
                    LazyVGrid(columns: colonnesTuiles, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Vendues")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(Color.primary)
                            Text("\(tableauxVendus.count + dessinsVendus.count + tapisVendus.count)")
                                .font(.system(size: 22, weight: .regular))
                                .foregroundStyle(Color.orangeInternational)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Données")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(Color.primary)
                            Text("\(oeuvresDonnees.count)")
                                .font(.system(size: 22, weight: .regular))
                                .foregroundStyle(Color.orangeInternational)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, 12)
                    #endif

                    LazyVGrid(columns: colonnesTuiles, spacing: 10) {
                        tuileNombre(icone: "paintpalette", label: "Tableaux vendus",
                                    valeur: "\(tableauxVendus.count)",
                                    detail: formaterEuros(somme(tableauxVendus)))
                        tuileNombre(icone: "pencil.and.outline", label: "Dessins vendus",
                                    valeur: "\(dessinsVendus.count)",
                                    detail: formaterEuros(somme(dessinsVendus)))
                        tuileNombre(icone: "square.grid.3x3.square", label: "Tapis vendus",
                                    valeur: "\(tapisVendus.count)",
                                    detail: formaterEuros(somme(tapisVendus)))
                        tuileNombre(icone: "gift", label: "Tableaux donnés",
                                    valeur: "\(tableauxDonnes.count)", detail: nil,
                                    reserverEspace: true)
                        tuileNombre(icone: "gift", label: "Dessins donnés",
                                    valeur: "\(dessinsDonnes.count)", detail: nil,
                                    reserverEspace: true)
                    }
                }

                // --- Carte MONTANTS ---
                carte(titre: "Montants") {
                    let sT = stats(tableauxVendus)
                    let sD = stats(dessinsVendus)
                    VStack(spacing: 10) {
                        tuileLignes(titre: "Prix des tableaux", lignes: [
                            ("Le plus bas", formaterEuros(sT.min)),
                            ("Le plus haut", formaterEuros(sT.max)),
                            ("Prix moyen", formaterEuros(sT.moyenne))
                        ])
                        tuileLignes(titre: "Prix des dessins", lignes: [
                            ("Le plus bas", formaterEuros(sD.min)),
                            ("Le plus haut", formaterEuros(sD.max)),
                            ("Prix moyen", formaterEuros(sD.moyenne))
                        ])
                        tuileLignes(titre: "Catégories", lignes: [
                            ("Tableaux", formaterEuros(somme(tableauxVendus))),
                            ("Dessins", formaterEuros(somme(dessinsVendus))),
                            ("Tapis", formaterEuros(somme(tapisVendus)))
                        ])
                    }
                }

                // --- Carte ENCHÈRES ET EXPOSITIONS ---
                carte(titre: "Enchères et expositions") {
                    VStack(spacing: 10) {
                        tuileVendeur("Artenchères", sommeVendeur("Artenchères"))
                        tuileVendeur("Drôme Enchères", sommeVendeur("Drôme Enchères"))
                        tuileVendeur("RempART", sommeVendeur("RempART"))
                    }
                }
            }
            .padding(16)
        }
        .background(Color.cremeFond)
        #if os(iOS)
        .navigationTitle("Synthèse")
        #else
        .navigationTitle("")
        #endif
    }

    // MARK: Récapitulatif mobile

    // MARK: Composants du thème

    /// Grande carte de section : titre + contenu, fond sombre à fine bordure.
    @ViewBuilder
    private func carte<Contenu: View>(titre: String,
                                      @ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titre)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.primary)
                // Décalage pour aligner le titre du bloc avec le texte des
                // tuiles en dessous (qui ont un padding interne de 12).
                .padding(.leading, 12)
            contenu()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.fondLegende)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.orangeInternational.opacity(0.5), lineWidth: 1)
                )
        )
    }

    /// Tuile « nombre » : icône + label, grand chiffre orange, détail orange.
    private func tuileNombre(icone: String, label: String,
                             valeur: String, detail: String?,
                             reserverEspace: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Titre du sous-bloc, seul.
            Text(label)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            // Nombre d'œuvres, précédé de l'icône du type.
            HStack(spacing: 5) {
                Image(systemName: icone)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.orangeInternational)
                Text(valeur)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.orangeInternational)
            }
            // Prix, précédé d'une icône euro (seulement s'il y a un prix).
            if let detail {
                HStack(spacing: 5) {
                    Image(systemName: "eurosign.circle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color.orangeInternational)
                    Text(detail)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Color.orangeInternational)
                        .flouteSiPrixMasques()
                }
            } else if reserverEspace {
                // Pas de prix mais on réserve la hauteur d'une ligne « euro +
                // prix », uniquement quand la tuile partage une rangée avec une
                // tuile qui a un prix (pour aligner les titres).
                HStack(spacing: 5) {
                    Image(systemName: "eurosign.circle")
                        .font(.system(size: 18, weight: .regular))
                    Text(" ")
                        .font(.system(size: 22, weight: .regular))
                }
                .hidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.cremeFond))
    }

    /// Tuile « lignes » : un titre et des paires libellé / valeur.
    private func tuileLignes(titre: String, lignes: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titre)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.primary)
            VStack(spacing: 5) {
                ForEach(lignes, id: \.0) { lib, val in
                    HStack {
                        Text(lib)
                            .font(.system(size: 18))
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Text(val)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(Color.orangeInternational)
                            .monospacedDigit()
                            .flouteSiPrixMasques()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.cremeFond))
    }

    /// Tuile « vendeur » : libellé à gauche, montant orange à droite.
    private func tuileVendeur(_ nom: String, _ montant: Double) -> some View {
        HStack {
            Text(nom)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.primary)
            Spacer()
            PrixText(montant)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.orangeInternational)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.cremeFond))
    }
}
