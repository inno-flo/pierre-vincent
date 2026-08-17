#if os(iOS)
import SwiftUI

/// Visionneuse plein écran d'une photo d'œuvre (pinch-to-zoom + glissement
/// pour se déplacer dans l'image agrandie). Ouverte depuis la fiche de
/// détail (DetailiOS) par un tap prolongé sur la photo.
struct VisionneuseImagePleinEcran: View {
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

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Image(imagePlateforme: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(echelle)
                .offset(decalage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(gesteCombine)
                // Double-tap pour réinitialiser rapidement le zoom.
                .onTapGesture(count: 2) { reinitialiserZoom() }

            // Bouton de fermeture, coin supérieur droit.
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .font(.system(size: 30))
            }
            .padding()
        }
        .statusBarHidden()
    }

    /// Pinch (zoom) et glissement (déplacement), combinés simultanément.
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
                guard echelle > echelleMin else { return }
                decalage = CGSize(
                    width: decalageReference.width + valeur.translation.width,
                    height: decalageReference.height + valeur.translation.height)
            }
            .onEnded { _ in
                decalageReference = decalage
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
