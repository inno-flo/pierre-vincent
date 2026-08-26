#if os(iOS)
import SwiftUI

/// Visionneuse plein écran d'une photo d'œuvre (pinch-to-zoom + glissement
/// pour se déplacer dans l'image agrandie). Ouverte depuis la fiche de
/// détail (DetailiOS) par un appui prolongé sur la photo — un « Long Press
/// Gesture » dans la terminologie Apple, « pression prolongée » en français.
///
/// **Croix et fermeture par glissement calqués sur `VisionneuseOeuvres`** :
/// même pastille (cercle sombre cerclé de l'accent), même position (coin
/// supérieur droit, 20 pt), même geste de fermeture. Les deux visionneuses
/// doivent se manipuler et se refermer de façon identique.
struct VisionneuseImagePleinEcran: View {
    /// Accent de la rubrique — orange dans « Ventes et dons », bleu ardoise
    /// dans la Réserve. Hérité de la fiche de détail qui ouvre cette vue.
    @Environment(\.accentRubrique) private var accent
    let image: ImagePlateforme
    @Environment(\.dismiss) private var dismiss

    // Échelle et décalage courants (pinch + glissement), et leurs valeurs
    // de référence au début de chaque geste pour cumuler d'un geste à l'autre.
    @State private var echelle: CGFloat = 1
    @State private var echelleReference: CGFloat = 1
    @State private var decalage: CGSize = .zero
    @State private var decalageReference: CGSize = .zero

    private let echelleMin: CGFloat = 1
    private let echelleMax: CGFloat = 5
    /// Distance verticale au-delà de laquelle le glissement ferme la vue —
    /// même seuil que `VisionneuseOeuvres`.
    private let seuilFermeture: CGFloat = 120

    /// Glissement vertical en cours vers la fermeture. Le contenu suit le
    /// doigt : sans ce retour, on ne saurait pas que le geste est engagé.
    @State private var glissementFermeture: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
                // Le fond s'estompe à mesure qu'on tire vers le bas, ce qui
                // annonce la fermeture avant qu'elle ne soit acquise — même
                // traitement que `VisionneuseOeuvres`.
                .opacity(max(0.35, 1 - abs(glissementFermeture) / 400))

            Image(imagePlateforme: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(echelle)
                .offset(decalage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Double-tap pour réinitialiser rapidement le zoom.
                .onTapGesture(count: 2) { reinitialiserZoom() }

            boutonFermer
        }
        // Le contenu suit le doigt pendant le glissement de fermeture.
        .offset(y: glissementFermeture)
        // Geste posé sur TOUT l'écran, et non sur la seule image : la
        // fermeture par glissement doit marcher partout, y compris dans les
        // marges noires d'une image qui ne remplit pas l'écran.
        .contentShape(Rectangle())
        .gesture(gesteCombine)
        .statusBarHidden()
    }

    /// Bouton de fermeture — même pastille, même position que
    /// `VisionneuseOeuvres.boutonFermer` : cercle sombre cerclé de l'accent,
    /// 34×34, à 20 pt du coin supérieur droit.
    private var boutonFermer: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background {
                    Circle()
                        .fill(.black.opacity(0.55))
                        .overlay(Circle().strokeBorder(accent, lineWidth: 1))
                }
        }
        .padding(20)
        .accessibilityLabel("Fermer")
    }

    /// Pinch (zoom), glissement (déplacement une fois zoomé) et glissement
    /// vertical de fermeture (à l'échelle 1), combinés simultanément — même
    /// répartition que `VisionneuseOeuvres.gesteCombine`.
    private var gesteCombine: some Gesture {
        let pinch = MagnificationGesture()
            .onChanged { valeur in
                echelle = min(max(echelleReference * valeur, echelleMin), echelleMax)
            }
            .onEnded { _ in
                echelleReference = echelle
                // Revenu à l'échelle mini : on recentre l'image.
                if echelle <= echelleMin {
                    reinitialiserZoom()
                }
            }

        let glissement = DragGesture()
            .onChanged { valeur in
                // ZOOMÉ : le glissement déplace l'image, et RIEN d'autre —
                // pas de fermeture accidentelle en consultant un détail agrandi.
                guard echelle <= echelleMin else {
                    decalage = CGSize(
                        width: decalageReference.width + valeur.translation.width,
                        height: decalageReference.height + valeur.translation.height)
                    return
                }
                // À l'échelle 1, un glissement vertical amorce la fermeture,
                // le contenu suivant le doigt.
                glissementFermeture = valeur.translation.height
            }
            .onEnded { valeur in
                guard echelle <= echelleMin else {
                    decalageReference = decalage
                    return
                }
                // Vers le BAS et assez loin : on ferme. Sinon, le contenu
                // revient en place.
                if valeur.translation.height > seuilFermeture {
                    dismiss()
                    return
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    glissementFermeture = 0
                }
            }

        return pinch.simultaneously(with: glissement)
    }

    /// Remet l'image à sa taille et sa position d'origine.
    private func reinitialiserZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            echelle = 1
            echelleReference = 1
            decalage = .zero
            decalageReference = .zero
        }
    }
}
#endif
