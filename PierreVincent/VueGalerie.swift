import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// Vue « galerie » (par icône) : chaque entrée est une vignette de l'image
/// (200×200 max), avec en dessous le prix et les dimensions.
struct VueGalerie: View {
    let oeuvres: [Oeuvre]
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
            #if os(macOS)
            // Focus clavier sur le ScrollView pour recevoir les touches fléchées.
            // focusEffectDisabled() supprime l'anneau bleu de focus.
            // Focalisable UNIQUEMENT s'il y a une vignette sélectionnée : sinon
            // la galerie captait le focus dès l'ouverture d'une rubrique, la
            // sidebar le perdait (sélection qui vire au gris/marron) et ses ↑↓
            // ne répondaient plus. Même correctif que sur le Table du mode liste.
            .focusable(!selection.isEmpty)
            .focused($focusGalerie)
            .focusEffectDisabled()
            .onKeyPress(.leftArrow)  { naviguerClavier(delta: -1) }
            .onKeyPress(.rightArrow) { naviguerClavier(delta: +1) }
            .onKeyPress(.upArrow)    { naviguerClavier(delta: -nbColonnes) }
            .onKeyPress(.downArrow)  { naviguerClavier(delta: +nbColonnes) }
            .onKeyPress(.return) {
                guard selection.count == 1,
                      let id = selection.first,
                      let o = oeuvres.first(where: { $0.id == id }) else { return .ignored }
                onOuvrir(o)
                return .handled
            }
            // Overlay invisible pour mesurer la largeur sans perturber le layout.
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.size.width, initial: true) { _, w in
                            largeurGrille = w
                        }
                }
            }
            #endif
        }
    }

    #if os(macOS)
    // Nombre de colonnes déduit de la largeur mesurée, pour la navigation ↑↓.
    // La grille utilise adaptive(minimum: 200), spacing: 16 ; padding: 16 de chaque côté.
    private var nbColonnes: Int {
        let spacing: CGFloat = 16
        let padding: CGFloat = 32
        let available = max(1, largeurGrille - padding)
        return max(1, Int((available + spacing) / (200 + spacing)))
    }

    // Déplace la sélection de `delta` positions dans la liste ordonnée des œuvres.
    // Retourne .handled pour bloquer la propagation même si le bord est atteint.
    private func naviguerClavier(delta: Int) -> KeyPress.Result {
        guard selection.count == 1,
              let id = selection.first,
              let idx = oeuvres.firstIndex(where: { $0.id == id }) else { return .ignored }
        let nouveauIdx = idx + delta
        guard nouveauIdx >= 0, nouveauIdx < oeuvres.count else { return .handled }
        let nouvelle = oeuvres[nouveauIdx]
        selection = [nouvelle.id]
        derniere = nouvelle.id
        return .handled
    }
    #endif

    /// Police du prix et des dimensions dans la légende d'une vignette.
    /// 13 pt sur macOS : c'est `NSFont.systemFontSize`, la taille standard
    /// d'un libellé (`.subheadline` n'y vaut que 11 pt).
    /// Sur iOS on garde `.subheadline` (15 pt) : le 13 pt macOS n'y est pas
    /// la référence et rapetisserait le texte.
    private var policeLegende: Font {
        #if os(macOS)
        .system(size: 13)
        #else
        .subheadline
        #endif
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
                // Le test porte sur l'ŒUVRE et non sur la rubrique affichée :
                // dans les vues agrégées (Inventaire, Ventes), une œuvre donnée
                // affichait « 0 € » sous sa vignette. Même correctif que dans
                // l'inspecteur. La vue n'a donc plus besoin qu'on lui passe le
                // caractère « don » de la rubrique.
                HStack {
                    if o.feuille != .oeuvresDonnees {
                        PrixText(o.prix)
                            .foregroundStyle(Color.orangeInternational)
                    }
                    Spacer()
                    Text(o.dimensions)
                        .foregroundStyle(Color.texteLegende.opacity(0.6))
                }
                .font(policeLegende)
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
        // Sur Mac : un clic sélectionne, un double-clic sélectionne PUIS ouvre
        // la fiche. Le double-clic n'appelait auparavant que `onOuvrir` : le
        // filet orange restait donc sur la vignette précédemment sélectionnée.
        // Sélection posée directement (et non via `cliquer`, qui tient compte
        // des touches Cmd/Maj) : un double-clic désigne toujours cette seule
        // vignette.
        .onTapGesture { cliquer(o) }
        .onTapGesture(count: 2) {
            selection = [o.id]
            derniere = o.id
            onOuvrir(o)
        }
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
        // Focus demandé APRÈS la mise à jour de la sélection : la galerie
        // n'est focalisable que si la sélection est non vide (voir plus haut),
        // donc une demande faite avant serait purement et simplement ignorée.
        focusGalerie = !selection.isEmpty
        #else
        // iPhone (consultation) : un simple tap sélectionne l'entrée.
        selection = [o.id]
        derniere = o.id
        #endif
    }
}
