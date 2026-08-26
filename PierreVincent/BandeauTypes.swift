#if os(iOS)
import SwiftUI

/// Bandeau de pastilles filtrant par TYPE d'œuvre — Tableaux, Dessins, Tapis —
/// avec le compteur des œuvres affichées à droite.
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

    /// Pastilles à proposer, décidées par la rubrique (`Categorie.typesFiltre`)
    /// et non par cette vue : la Réserve n'en veut que deux, « Ventes et
    /// dons » les trois.
    let mots: [String]
    /// Mot cherché dans le champ `type`, ou nil si aucun filtre.
    @Binding var typeRetenu: String?
    /// Nombre d'œuvres réellement affichées, filtre appliqué.
    let nombreAffiche: Int

    var body: some View {
        // Alignement explicite : même pattern que `bandeauFiltres` sur Mac,
        // pour que pastilles (des `Button`) et compteur (un `Text` nu)
        // partagent la même ligne de base, quelle que soit la vue qui les
        // compose.
        HStack(alignment: .center, spacing: 8) {
            ForEach(mots, id: \.self) { mot in
                pastille(libelle: libelleTypeFiltrable(mot), mot: mot)
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
                // `.body` : même corps que les libellés de rubrique de la
                // sidebar. Style SÉMANTIQUE et non une taille en points :
                // figer une taille casserait le Dynamic Type.
                .font(.body)
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
            // Même corps que les pastilles, donc que les libellés de sidebar.
            .font(.body)
            // Toujours rempli de l'accent de la section, texte blanc — comme
            // sur macOS, contrairement aux pastilles de filtre qui ne se
            // remplissent qu'une fois retenues.
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background { Capsule().fill(accent) }
    }
}

// Les pastilles elles-mêmes — libellés, symboles et fonction de filtrage —
// vivent dans `TriEtTotaux.swift` (`motsTypesFiltrables`,
// `libelleTypeFiltrable`, `symboleTypeFiltrable`, `filtrerParType`), avec le
// reste des prédicats partagés : le bandeau macOS de `VueFeuille` s'en sert
// aussi, et ce fichier est réservé à iOS.

/// Menu de filtre par type, pour la barre d'outils — **alternative** aux
/// pastilles du bandeau.
///
/// Les deux pilotent le MÊME état : changer l'un met l'autre à jour, il n'y a
/// pas deux filtres à tenir d'accord.
struct MenuFiltreTypes: View {
    /// Accent de la rubrique — orange dans « Ventes et dons », bleu ardoise
    /// dans la Réserve. Posé sur la colonne de contenu, il descend jusqu'ici.
    @Environment(\.accentRubrique) private var accent

    /// Mêmes pastilles que le bandeau : les deux commandes proposent
    /// exactement les mêmes entrées.
    let mots: [String]
    /// Symbole de l'entrée « Tous » — l'icône de la rubrique dans les deux
    /// Catalogue, la grille générique ailleurs.
    var symboleTous: String = "square.grid.2x2"
    @Binding var typeRetenu: String?

    var body: some View {
        Menu {
            Button {
                typeRetenu = nil
            } label: {
                Label(typeRetenu == nil ? "✓ Tout" : "Tout",
                      systemImage: symboleTous)
            }
            ForEach(mots, id: \.self) { mot in
                let libelle = libelleTypeFiltrable(mot)
                Button {
                    typeRetenu = mot
                } label: {
                    Label(typeRetenu == mot ? "✓ \(libelle)" : libelle,
                          systemImage: symboleTypeFiltrable(mot))
                }
            }
        } label: {
            // L'icône dit le CRITÈRE ACTIF, exactement comme celle du menu
            // de tri : le type retenu quand il y en a un, et sinon l'icône de
            // l'entrée « Tous » — donc celle de la rubrique dans les deux
            // Catalogue.
            Image(systemName: typeRetenu.map(symboleTypeFiltrable)
                              ?? symboleTous)
        }
    }
}
#endif
