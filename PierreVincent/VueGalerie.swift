import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

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

    #if os(macOS)
    // Largeur mesurée de la grille, pour déduire le nombre de colonnes.
    @State private var largeurGrille: CGFloat = 600
    @FocusState private var focusGalerie: Bool
    #endif

    // Colonnes de la grille :
    // - iPhone : 2 colonnes fixes (les images se réduisent pour tenir à 2 par rangée).
    // - Mac : grille adaptative selon la largeur disponible.
    private var colonnes: [GridItem] {
        #if os(iOS)
        return [GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)]
        #else
        return [GridItem(.adaptive(minimum: 200, maximum: 220), spacing: 16)]
        #endif
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: colonnes, spacing: 16) {
                    ForEach(oeuvres) { o in
                        carte(o)
                            .id(o.id)
                    }
                }
                .padding(16)
            }
            .background(Color.cremeFond)
            // Fait défiler vers l'œuvre sélectionnée quand la sélection change
            // (utile lors de la navigation Précédent / Suivant de l'éditeur).
            .onChange(of: selection) { _, nouvelle in
                guard nouvelle.count == 1, let id = nouvelle.first else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func carte(_ o: Oeuvre) -> some View {
        VStack(spacing: 0) {
            // Image en haut : cadre en PORTRAIT (proche du ratio réel des
            // photos de tableaux), pour ne rogner que très peu tout en
            // remplissant la carte. Essai de nouvelle présentation.
            ZStack {
                Color.gray.opacity(0.12)
                VignetteCacheeFlexible(nom: o.photoNom, coteSource: 320,
                                       preserverRatio: true)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3.0/4.0, contentMode: .fit)   // portrait 3:4
            .clipped()

            // Bande blanche en légende, sous l'image.
            // Textes forcés en sombre car le fond reste blanc dans les deux modes.
            VStack(alignment: .leading, spacing: 5) {
                // En gras : le nom de l'acheteur (pour la feuille « données »,
                // le destinataire, qui joue le même rôle).
                Text(ligneGras(o).isEmpty ? " " : ligneGras(o))
                    .font(.headline)
                    .foregroundStyle(Color.texteLegende)
                    .lineLimit(1)

                // En dessous : prix à gauche, dimensions à droite.
                HStack {
                    if !estFeuilleDon {
                        PrixText(o.prix)
                            .foregroundStyle(Color.orangeInternational)
                    }
                    Spacer()
                    Text(o.dimensions)
                        .foregroundStyle(Color.texteLegende.opacity(0.6))
                }
                .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.fondLegende)
        }
        // Carte « photo posée » : fond blanc, coins arrondis, ombre douce.
        .background(Color.fondLegende)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selection.contains(o.id) ? Color.orangeInternational : Color.filetVignette,
                              lineWidth: selection.contains(o.id) ? 3 : 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 5, x: 0, y: 2)
        .contentShape(Rectangle())
        #if os(macOS)
        // Sur Mac : un clic sélectionne, un double-clic ouvre la fiche.
        .onTapGesture { cliquer(o) }
        .onTapGesture(count: 2) { onOuvrir(o) }
        #else
        // Sur iPhone : un simple tap ouvre directement la fiche de détail.
        .onTapGesture { onOuvrir(o) }
        #endif
    }

    /// Texte de la ligne en gras : le nom de l'acheteur pour les ventes,
    /// le destinataire pour les dons.
    /// Texte de la ligne en gras : le nom de l'acheteur s'il existe, sinon le
    /// destinataire (utile dans la vue « Œuvres » qui compile ventes ET dons).
    private func ligneGras(_ o: Oeuvre) -> String {
        if !o.acheteur.isEmpty { return o.acheteur }
        if !o.destinataire.isEmpty { return o.destinataire }
        return ""
    }

    /// Gère le clic selon les touches enfoncées, comme dans la vue liste :
    /// - Cmd : ajoute/retire l'entrée de la sélection.
    /// - Maj : sélectionne toute la plage depuis la dernière entrée cliquée.
    /// - sans touche : sélectionne uniquement cette entrée.
    private func cliquer(_ o: Oeuvre) {
        #if os(macOS)
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
        #else
        // iPhone (consultation) : un simple tap sélectionne l'entrée.
        selection = [o.id]
        derniere = o.id
        #endif
    }
}
