import SwiftUI

/// Une cellule de texte éditable directement.
/// Au clic, elle passe en mode saisie. La validation (Entrée ou perte de focus)
/// enregistre la nouvelle valeur via `onValider`.
struct CelluleEditable: View {
    /// Texte initial affiché.
    let texte: String
    /// Alignement horizontal du texte (à gauche ou centré selon la colonne).
    var alignement: TextAlignment = .leading
    /// Appelé avec la nouvelle valeur quand l'utilisateur valide.
    let onValider: (String) -> Void

    @State private var saisie: String = ""
    @State private var enEdition = false
    @FocusState private var focus: Bool

    /// Convertit l'alignement du texte en alignement de cadre SwiftUI.
    private var alignementCadre: Alignment {
        switch alignement {
        case .center:   return .center
        case .trailing: return .trailing
        default:        return .leading
        }
    }

    var body: some View {
        Group {
            if enEdition {
                TextField("", text: $saisie)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .multilineTextAlignment(alignement)
                    .focused($focus)
                    .onSubmit { valider() }
                    .onChange(of: focus) { _, actif in
                        if !actif { valider() }
                    }
            } else {
                Text(texte.isEmpty ? " " : texte)
                    .font(.callout)
                    .multilineTextAlignment(alignement)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: alignementCadre)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        saisie = texte
                        enEdition = true
                        focus = true
                    }
            }
        }
    }

    private func valider() {
        enEdition = false
        if saisie != texte { onValider(saisie) }
    }
}
