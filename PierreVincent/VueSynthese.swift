import SwiftUI
import SwiftData

/// Tableau de bord « Synthèse », thème « Graphite » (sombre fixe).
///
/// Structure à deux niveaux (d'après la maquette Claude Design) :
///  - de grandes CARTES par section (Ventes, Prix de vente, Dons, Enchères) ;
///  - à l'intérieur, des TUILES (un ton plus clair) pour chaque élément.
/// L'orange de marque n'est utilisé que sur les valeurs chiffrées.
struct VueSynthese: View {
    let toutes: [Oeuvre]

    // MARK: Polices

    // Cette vue est PARTAGÉE entre iOS et macOS, et les styles sémantiques n'y
    // valent pas la même chose. Chaque plateforme prend donc SON barème :
    //
    //   rôle              iOS              macOS
    //   libellé de tuile  .callout  16 pt  .body    13 pt
    //   valeur chiffrée   .body     17 pt  .title3  15 pt
    //   titre de carte    .title3   20 pt  .title2  17 pt
    //
    // La vue utilisait auparavant 16/18/20 pt sur les DEUX plateformes : des
    // valeurs pensées pour iPhone, hors du barème macOS (10, 11, 12, 13, 15,
    // 17, 22, 26), qui faisaient un corps de texte 40 % plus gros que partout
    // ailleurs dans l'app Mac. La Synthèse macOS est donc plus compacte
    // qu'avant : c'est voulu.

    /// Libellé d'une tuile.
    private var policeLibelle: Font {
        #if os(macOS)
        .body             // 13 pt
        #else
        .callout          // 16 pt
        #endif
    }

    /// Compteur d'œuvres d'une tuile (« Vendues 336 »).
    private var policeValeur: Font {
        #if os(macOS)
        .body             // 13 pt, comme les prix et le reste de l'app Mac
        #else
        .body             // 17 pt
        #endif
    }

    /// Montants en euros. Sur macOS ils sont à 13 pt PARTOUT ailleurs dans
    /// l'app (cellule Prix du tableau, inspecteur, légende de galerie) : la
    /// Synthèse s'aligne dessus, au lieu des 15 pt de `policeValeur`, qui reste
    /// réservée aux compteurs d'œuvres. Sur iOS, valeur identique à
    /// `policeValeur` : rien n'y change.
    private var policePrix: Font {
        #if os(macOS)
        .body             // 13 pt
        #else
        .body             // 17 pt
        #endif
    }

    /// Titre d'une carte.
    private var policeTitre: Font {
        #if os(macOS)
        .title2           // 17 pt
        #else
        .title3           // 20 pt
        #endif
    }

    // MARK: Sous-ensembles par feuille

    /// Œuvres recensées par la Synthèse : mêmes règles que la section
    /// « Ventes et dons » — uniquement celles sorties du fonds. Les œuvres
    /// encore disponibles (section « Réserve ») ne doivent pas peser dans les
    /// totaux, sans quoi la Synthèse compterait des ventes qui n'ont pas eu lieu.
    /// Tous les sous-ensembles ci-dessous en dérivent.
    private var recensees: [Oeuvre] { toutes.filter(estVenduOuDonne) }

    private var tableauxVendus: [Oeuvre] { recensees.filter { $0.feuille == .tableauxVendus } }
    private var dessinsVendus:  [Oeuvre] { recensees.filter { $0.feuille == .dessinsVendus } }
    private var tapisVendus:    [Oeuvre] { recensees.filter { $0.feuille == .tapisVendus } }
    private var oeuvresDonnees: [Oeuvre] { recensees.filter { $0.feuille == .oeuvresDonnees } }

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

                // --- Carte VENTES ---
                // Contenu IDENTIQUE sur les deux plateformes : le récapitulatif
                // « Vendues / Données » qui n'existait que sur iOS a été retiré,
                // devenu redondant avec la carte « Dons » qui détaille par type.
                carte(titre: "Ventes") {
                    LazyVGrid(columns: colonnesTuiles, spacing: 10) {
                        tuileNombre(icone: "paintpalette", label: "Tableaux",
                                    valeur: "\(tableauxVendus.count)",
                                    detail: formaterEuros(somme(tableauxVendus)))
                        tuileNombre(icone: "pencil.and.outline", label: "Dessins",
                                    valeur: "\(dessinsVendus.count)",
                                    detail: formaterEuros(somme(dessinsVendus)))
                        tuileNombre(icone: "square.grid.3x3.square", label: "Tapis",
                                    valeur: "\(tapisVendus.count)",
                                    detail: formaterEuros(somme(tapisVendus)))
                        // Total = tableaux + dessins + tapis (en euros).
                        // Placé à droite de « Tapis » dans la grille 2 colonnes.
                        tuileTotalVentes()
                    }
                }

                // --- Carte PRIX DE VENTE ---
                carte(titre: "Prix de vente") {
                    let sT = stats(tableauxVendus)
                    let sD = stats(dessinsVendus)
                    VStack(spacing: 10) {
                        // La carte le dit désormais : plus besoin de répéter
                        // « Prix des » dans chaque intitulé de tuile.
                        tuileLignes(titre: "Tableaux", lignes: [
                            ("Le plus bas", formaterEuros(sT.min)),
                            ("Le plus haut", formaterEuros(sT.max)),
                            ("Prix moyen", formaterEuros(sT.moyenne))
                        ])
                        tuileLignes(titre: "Dessins", lignes: [
                            ("Le plus bas", formaterEuros(sD.min)),
                            ("Le plus haut", formaterEuros(sD.max)),
                            ("Prix moyen", formaterEuros(sD.moyenne))
                        ])
                        // La tuile « Catégories » (total par type) a été
                        // retirée : ce total figure déjà en détail sous
                        // chaque tuile de la carte « Ventes ».
                    }
                }

                // --- Carte DONS ---
                // Les deux tuiles vivaient dans la carte « Ventes » ; en sortir
                // leur redonne un intitulé simple (« Tableaux », « Dessins »),
                // qui n'a plus à se distinguer de leurs pendants vendus.
                carte(titre: "Dons") {
                    LazyVGrid(columns: colonnesTuiles, spacing: 10) {
                        tuileNombre(icone: "gift", label: "Tableaux",
                                    valeur: "\(tableauxDonnes.count)", detail: nil)
                        tuileNombre(icone: "gift", label: "Dessins",
                                    valeur: "\(dessinsDonnes.count)", detail: nil)
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

    // MARK: Composants du thème

    /// Grande carte de section : titre + contenu, fond sombre à fine bordure.
    @ViewBuilder
    private func carte<Contenu: View>(titre: String,
                                      @ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titre)
                .font(policeTitre).fontWeight(.bold)
                .foregroundStyle(Color.textePrincipal)
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

    /// Tuile « Total des ventes » : montant total encaissé sur les trois
    /// feuilles de vente (tableaux + dessins + tapis), en euros. Même style
    /// visuel que `tuileNombre`, mais sans compteur d'œuvres — juste le montant.
    private func tuileTotalVentes() -> some View {
        let total = somme(tableauxVendus) + somme(dessinsVendus) + somme(tapisVendus)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Total")
                .font(policeLibelle)
                .foregroundStyle(Color.textePrincipal)
                .lineLimit(1)
            HStack(spacing: 5) {
                Image(systemName: "eurosign.circle")
                    .font(policeLibelle)
                    .foregroundStyle(Color.orangeInternational)
                Text(formaterEuros(total))
                    .font(policePrix)
                    .foregroundStyle(Color.orangeInternational)
                    .flouteSiPrixMasques()
            }
            // Deuxième ligne réservée (invisible) pour garder la même hauteur
            // que la tuile « Tableaux vendus » qui l'accompagne sur la rangée.
            HStack(spacing: 5) {
                Image(systemName: "eurosign.circle")
                    .font(policeLibelle)
                Text(" ")
                    .font(policePrix)
            }
            .hidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.fondTuile))
    }

    /// Tuile « nombre » : icône + label, grand chiffre orange, détail orange.
    private func tuileNombre(icone: String, label: String,
                             valeur: String, detail: String?,
                             reserverEspace: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Titre du sous-bloc, seul.
            Text(label)
                .font(policeLibelle)
                .foregroundStyle(Color.textePrincipal)
                .lineLimit(1)
            // Nombre d'œuvres, précédé de l'icône du type.
            HStack(spacing: 5) {
                Image(systemName: icone)
                    .font(policeLibelle)
                    .foregroundStyle(Color.orangeInternational)
                Text(valeur)
                    .font(policeValeur)
                    .foregroundStyle(Color.orangeInternational)
            }
            // Prix, précédé d'une icône euro (seulement s'il y a un prix).
            if let detail {
                HStack(spacing: 5) {
                    Image(systemName: "eurosign.circle")
                        .font(policeLibelle)
                        .foregroundStyle(Color.orangeInternational)
                    Text(detail)
                        .font(policePrix)
                        .foregroundStyle(Color.orangeInternational)
                        .flouteSiPrixMasques()
                }
            } else if reserverEspace {
                // Pas de prix mais on réserve la hauteur d'une ligne « euro +
                // prix », uniquement quand la tuile partage une rangée avec une
                // tuile qui a un prix (pour aligner les titres).
                HStack(spacing: 5) {
                    Image(systemName: "eurosign.circle")
                        .font(policeLibelle)
                    Text(" ")
                        .font(policePrix)
                }
                .hidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.fondTuile))
    }

    /// Tuile « lignes » : un titre et des paires libellé / valeur.
    private func tuileLignes(titre: String, lignes: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titre)
                .font(policeValeur).fontWeight(.bold)
                .foregroundStyle(Color.textePrincipal)
            VStack(spacing: 5) {
                ForEach(lignes, id: \.0) { lib, val in
                    HStack {
                        Text(lib)
                            .font(policeLibelle)
                            .foregroundStyle(Color.textePrincipal)
                        Spacer()
                        Text(val)
                            .font(policePrix)
                            .foregroundStyle(Color.orangeInternational)
                            .monospacedDigit()
                            .flouteSiPrixMasques()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.fondTuile))
    }

    /// Tuile « vendeur » : libellé à gauche, montant orange à droite.
    private func tuileVendeur(_ nom: String, _ montant: Double) -> some View {
        HStack {
            // Même corps que les libellés des tuiles « lignes » (« Le plus
            // bas », « Prix moyen »…) : c'est le même rôle, un intitulé en
            // regard d'un montant.
            Text(nom)
                .font(policeLibelle)
                .foregroundStyle(Color.textePrincipal)
            Spacer()
            PrixText(montant)
                .font(policePrix)
                .foregroundStyle(Color.orangeInternational)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.fondTuile))
    }
}
