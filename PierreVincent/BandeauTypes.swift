#if os(iOS)
import SwiftUI

/// Bandeau de pastilles filtrant par TYPE d'œuvre — Tableaux, Dessins — avec
/// le compteur des œuvres affichées à droite.
///
/// Pendant iPhone du `bandeauFiltres` de `VueFeuille` (macOS), même apparence :
/// contour orange au repos, fond orange plein et texte blanc une fois retenu.
/// Un second appui sur la pastille retenue lève le filtre.
///
/// **Écrit une seule fois** : les deux vues qui en ont besoin — `VueiOS` pour
/// la Réserve, `VueDonsStructuree` pour les Dons — ont chacune leur propre
/// rendu de vignettes, et se seraient retrouvées avec deux copies vouées à
/// diverger, comme cela s'est déjà produit sur le filet de sélection.
struct BandeauTypes: View {
    /// Accent de la rubrique — orange dans « Ventes et dons », bleu ardoise
    /// dans la Réserve. Posé sur la colonne de contenu, il descend jusqu'ici.
    @Environment(\.accentRubrique) private var accent

    /// Mot cherché dans le champ `type`, ou nil si aucun filtre.
    @Binding var typeRetenu: String?
    /// Nombre d'œuvres réellement affichées, filtre appliqué.
    let nombreAffiche: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TypesFiltrables.tous, id: \.mot) { t in
                pastille(libelle: t.libelle, mot: t.mot)
            }
            Spacer()
            compteur
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func pastille(libelle: String, mot: String) -> some View {
        let retenu = typeRetenu?.caseInsensitiveCompare(mot) == .orderedSame
        return Button {
            // Un second appui sur la pastille retenue lève le filtre.
            typeRetenu = retenu ? nil : mot
        } label: {
            Text(libelle)
                // Corps SÉMANTIQUE et non une taille en points : figer une
                // taille casserait le Dynamic Type.
                .font(.subheadline)
                .fontWeight(retenu ? .bold : .regular)
                .foregroundStyle(retenu ? Color.white : Color.textePrincipal)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    if retenu {
                        Capsule().fill(accent)
                    } else {
                        Capsule().strokeBorder(accent, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    /// Compteur, non interactif : une indication, pas un bouton.
    private var compteur: some View {
        Text("\(nombreAffiche)")
            .font(.subheadline)
            .foregroundStyle(Color.textePrincipal)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background { Capsule().strokeBorder(accent, lineWidth: 1) }
    }
}

/// Les deux pastilles proposées, et le mot cherché dans le champ `type`.
///
/// **Fixes, et non déduites des données** — contrairement aux pastilles de
/// vendeur. Le champ `type` porte encore, sur les données anciennes, des
/// libellés composés (« Tableau — huile sur toile ») : collecter les valeurs
/// distinctes donnerait des dizaines de pastilles, pas deux.
enum TypesFiltrables {
    static let tous: [(libelle: String, mot: String)] = [
        ("Tableaux", "tableau"),
        ("Dessins", "dessin"),
    ]

    /// Symbole d'un type, repris de ceux de la barre latérale.
    static func symbole(_ mot: String) -> String {
        mot == "tableau" ? "paintpalette" : "pencil.and.outline"
    }

    /// Applique le filtre. Test par **inclusion** : le type peut être composé.
    ///
    /// Corollaire à garder en tête : une œuvre dont le type ne nomme ni l'un ni
    /// l'autre n'est retenue par AUCUNE pastille, et les deux comptes ne
    /// totalisent alors pas la rubrique.
    static func filtrer(_ liste: [Oeuvre], mot: String?) -> [Oeuvre] {
        guard let mot else { return liste }
        return liste.filter { $0.type.localizedCaseInsensitiveContains(mot) }
    }
}

/// Menu de filtre par type, pour la barre d'outils — **alternative** aux
/// pastilles du bandeau.
///
/// Les deux pilotent le MÊME état : changer l'un met l'autre à jour, il n'y a
/// pas deux filtres à tenir d'accord.
struct MenuFiltreTypes: View {
    /// Accent de la rubrique — orange dans « Ventes et dons », bleu ardoise
    /// dans la Réserve. Posé sur la colonne de contenu, il descend jusqu'ici.
    @Environment(\.accentRubrique) private var accent

    @Binding var typeRetenu: String?

    var body: some View {
        Menu {
            Button {
                typeRetenu = nil
            } label: {
                Label(typeRetenu == nil ? "✓ Tous" : "Tous",
                      systemImage: "square.grid.2x2")
            }
            ForEach(TypesFiltrables.tous, id: \.mot) { t in
                Button {
                    typeRetenu = t.mot
                } label: {
                    Label(typeRetenu == t.mot ? "✓ \(t.libelle)" : t.libelle,
                          systemImage: TypesFiltrables.symbole(t.mot))
                }
            }
        } label: {
            // L'icône dit le filtre actif, comme celle du menu de tri.
            Image(systemName: typeRetenu.map(TypesFiltrables.symbole)
                              ?? "line.3.horizontal.decrease")
        }
    }
}
#endif
