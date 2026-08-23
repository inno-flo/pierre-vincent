#if os(iOS)
import SwiftUI
import UIKit

/// Pastille éphémère « Prix masqués » / « Prix affichés », affichée dans une
/// **fenêtre à part**, au-dessus de tout le reste.
///
/// Pourquoi une `UIWindow` et non un simple `overlay` SwiftUI : une `.sheet`
/// se présente au-dessus de toute la hiérarchie de vues qui l'ouvre. Un
/// overlay posé dans cette hiérarchie — même à la racine — reste donc derrière
/// la fiche de détail. Seule une fenêtre d'un niveau supérieur passe devant.
///
/// La fenêtre est créée une fois puis réutilisée, et **ne capte aucun
/// toucher** (voir `FenetreTransparente`) : elle recouvre l'écran en
/// permanence sans jamais gêner l'app.
@MainActor
final class PastillePrix {
    static let shared = PastillePrix()
    private init() {}

    /// Durée d'affichage, identique à celle de la pastille macOS.
    private static let dureeNanosecondes: UInt64 = 840_000_000

    private let modele = ModelePastillePrix()
    private var fenetre: UIWindow?
    private var tacheExtinction: Task<Void, Never>?

    /// Montre la pastille correspondant à l'état demandé, puis l'éteint seule.
    func afficher(masques: Bool) {
        preparerFenetre()
        modele.masques = masques
        modele.message = masques ? "Prix masqués" : "Prix affichés"

        // Réarme le minuteur à chaque bascule : deux appuis rapprochés ne
        // doivent pas faire disparaître la seconde pastille trop tôt.
        tacheExtinction?.cancel()
        tacheExtinction = Task { [modele] in
            try? await Task.sleep(nanoseconds: Self.dureeNanosecondes)
            if !Task.isCancelled { modele.message = nil }
        }
    }

    /// Crée la fenêtre au premier besoin. La scène est cherchée à ce
    /// moment-là, et non au lancement : elle n'existe pas encore à l'`init`.
    private func preparerFenetre() {
        guard fenetre == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
                ?? scenes.first else { return }

        let hote = UIHostingController(rootView: VuePastillePrix(modele: modele))
        hote.view.backgroundColor = .clear

        let f = FenetreTransparente(windowScene: scene)
        f.rootViewController = hote
        f.backgroundColor = .clear
        // Au-dessus des feuilles et des alertes.
        f.windowLevel = .alert + 1
        f.isHidden = false
        fenetre = f
    }
}

/// Fenêtre qui laisse passer TOUS les touchers vers l'app en dessous.
/// Sans ce `hitTest`, elle intercepterait l'écran entier en permanence.
private final class FenetreTransparente: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

/// État observable de la pastille, partagé entre le contrôleur et la vue.
/// `@Observable` plutôt que `ObservableObject` : le second réclame
/// `import Combine` depuis Swift 6, et l'observation suffit ici.
@MainActor
@Observable
private final class ModelePastillePrix {
    var message: String?
    var masques = false
}

/// Rendu de la pastille — repris à l'identique de `bandeauPrix` (macOS).
private struct VuePastillePrix: View {
    let modele: ModelePastillePrix

    var body: some View {
        VStack(spacing: 0) {
            if let message = modele.message {
                HStack(spacing: 8) {
                    Image(systemName: modele.masques ? "eye.slash" : "eye")
                    Text(message)
                }
                .font(.headline)
                // Couleur posée explicitement : cette vue est hors de la
                // hiérarchie de `ContentView`, elle n'hérite donc pas du
                // `foregroundStyle` appliqué là-bas.
                .foregroundStyle(Color.textePrincipal)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.orangeInternational.opacity(0.4),
                                                lineWidth: 1))
                .shadow(radius: 10)
                .padding(.top, 18)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: modele.message)
    }
}
#endif
