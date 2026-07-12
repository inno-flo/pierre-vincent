import SwiftUI
import SwiftData
import AppKit

/// Vue « galerie » (par icône) : chaque entrée est une vignette de l'image
/// (200×200 max), avec en dessous le prix et les dimensions.
struct VueGalerie: View {
    let oeuvres: [Oeuvre]
    let estFeuilleDon: Bool
    @Binding var selection: Set<UUID>
    /// Double-clic sur une carte : ouvre la fiche d'édition.
    var onOuvrir: (Oeuvre) -> Void

    // Ancre pour la sélection par plage (Maj + clic).
    @State private var derniere: UUID?

    // Grille adaptative : autant de colonnes que la largeur le permet.
    private let colonnes = [GridItem(.adaptive(minimum: 200, maximum: 220), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: colonnes, spacing: 16) {
                ForEach(oeuvres) { o in
                    carte(o)
                }
            }
            .padding(16)
        }
    }

    private func carte(_ o: Oeuvre) -> some View {
        VStack(spacing: 6) {
            // Image 200×200 max.
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                if let img = PhotoStore.chargerImage(nom: o.photoNom) {
                    Image(nsImage: img).resizable().scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .cornerRadius(8)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 40)).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 200, height: 200)

            // Prix (sauf feuille « données ») et dimensions.
            VStack(spacing: 2) {
                if !estFeuilleDon {
                    Text(formaterEuros(o.prix))
                        .font(.callout.weight(.semibold))
                }
                Text(o.dimensions.isEmpty ? " " : o.dimensions)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selection.contains(o.id)
                      ? Color.accentColor.opacity(0.18)
                      : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selection.contains(o.id) ? Color.accentColor : Color.clear,
                              lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture { cliquer(o) }
        .onTapGesture(count: 2) { onOuvrir(o) }
    }

    /// Gère le clic selon les touches enfoncées, comme dans la vue liste :
    /// - Cmd : ajoute/retire l'entrée de la sélection.
    /// - Maj : sélectionne toute la plage depuis la dernière entrée cliquée.
    /// - sans touche : sélectionne uniquement cette entrée.
    private func cliquer(_ o: Oeuvre) {
        let mod = NSEvent.modifierFlags
        if mod.contains(.command) {
            if selection.contains(o.id) { selection.remove(o.id) } else { selection.insert(o.id) }
            derniere = o.id
        } else if mod.contains(.shift), let ancre = derniere,
                  let iA = oeuvres.firstIndex(where: { $0.id == ancre }),
                  let iC = oeuvres.firstIndex(where: { $0.id == o.id }) {
            for idx in min(iA, iC)...max(iA, iC) { selection.insert(oeuvres[idx].id) }
        } else {
            selection = [o.id]
            derniere = o.id
        }
    }
}
