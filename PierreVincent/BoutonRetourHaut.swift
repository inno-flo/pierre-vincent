#if os(iOS)
import SwiftUI

/// Bouton flottant « Retour en haut », pour les vues Galerie/Liste iOS.
///
/// **Écrit une seule fois** : `VueGalerie` (Galerie, partagée avec macOS —
/// gardée `#if os(iOS)` à l'appel), `VueOeuvresStructuree` (Catalogue,
/// Ventes, modes de vente), `VueDonsStructuree` (Dons) et `VueiOS` (mode
/// Liste des rubriques de Réserve et Favoris) le posent chacune sur leur
/// propre `ScrollView` — même patron que `BandeauTypes`, pour éviter quatre
/// copies vouées à diverger.
///
/// Pastille ronde : cercle sombre (`black.opacity(0.275)`) cerclé de
/// l'ACCENT DE LA RUBRIQUE (orange dans « Ventes et dons », bleu ardoise
/// dans la Réserve, taupe pour Favoris), flèche blanche — même rendu que
/// les boutons de retour en arrière déjà dans l'app
/// (`VisionneuseOeuvres.boutonFermer`, `VisionneuseImagePleinEcran`).
///
/// **PAS un `Button`** : posé sur un `ScrollView` encore en train de
/// défiler, un `Button` n'y réagissait qu'à un second tap — UIKit laissait
/// le premier au geste de défilement (arrêt de l'inertie) et ne le
/// transmettait qu'ensuite. `.highPriorityGesture` donne à ce tap la
/// priorité sur les reconnaisseurs de gestes du `ScrollView` ancêtre : le
/// bouton réagit dès le premier appui, défilement en cours ou non.
struct BoutonRetourHaut: View {
    /// Accent de la rubrique — posé une fois sur la colonne de contenu par
    /// `ContentView`, descend jusqu'ici quelle que soit la vue appelante.
    @Environment(\.accentRubrique) private var accent
    let action: () -> Void

    var body: some View {
        Image(systemName: "arrow.up")
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background {
                Circle()
                    .fill(.black.opacity(0.275))
                    .overlay(Circle().strokeBorder(accent, lineWidth: 1))
            }
            .shadow(radius: 3)
            .contentShape(Circle())
            .highPriorityGesture(
                TapGesture().onEnded { action() }
            )
            // Effet d'apparition fluide : léger zoom depuis le centre,
            // combiné au fondu, plutôt qu'un simple fondu sec.
            .transition(.scale(scale: 0.7).combined(with: .opacity))
    }
}

/// Ajoute à un `ScrollView` le suivi de défilement et le bouton flottant
/// « Retour en haut » : apparaît après un défilement de deux fois la
/// hauteur visible, positionné à la limite haute du TIERS BAS de l'écran,
/// côté droit — calculé via un `GeometryReader`, pas un simple padding
/// depuis le coin.
private struct RetourEnHautModifier: ViewModifier {
    @Binding var visible: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometrie in
                geometrie.contentOffset.y > geometrie.containerSize.height * 2
            } action: { _, doitAfficher in
                withAnimation(.easeOut(duration: 0.25)) {
                    visible = doitAfficher
                }
            }
            .overlay {
                if visible {
                    // Centré horizontalement — accessible de la même façon
                    // pour droitiers et gauchers, plutôt que collé à un
                    // bord. Seule la position X change ; la hauteur
                    // (limite haute du tiers bas) reste identique.
                    GeometryReader { geo in
                        BoutonRetourHaut(action: action)
                            .position(x: geo.size.width / 2,
                                      y: geo.size.height * 2 / 3)
                    }
                }
            }
    }
}

extension View {
    /// Voir `RetourEnHautModifier`. `visible` doit être un `@State` propre à
    /// la vue appelante (un par `ScrollView`, pas partagé entre Galerie et
    /// Liste quand elles ont chacune le leur). `action` fait typiquement
    /// `proxy.scrollTo(ancre, anchor: .top)`.
    func retourEnHaut(visible: Binding<Bool>, action: @escaping () -> Void) -> some View {
        modifier(RetourEnHautModifier(visible: visible, action: action))
    }
}
#endif
