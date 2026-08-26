#if os(iOS)
import SwiftUI
import UIKit

/// Pastille « Import en cours », affichée dans une fenêtre à part — même
/// mécanisme et même style que `PastillePrix`, mais SANS minuteur : elle
/// reste tant que l'import dure, et disparaît quand il se termine, pas après
/// une durée fixe.
///
/// **Pourquoi une `UIWindow`** : `EchangeBase.importerEnRemplacant` se lance
/// depuis `ContentView`, à la racine — pas derrière une feuille ici — mais le
/// même mécanisme que `PastillePrix` est repris pour rester cohérent et
/// passer devant n'importe quelle présentation future.
@MainActor
final class PastilleImportBase {
    static let shared = PastilleImportBase()
    private init() {}

    private let modele = ModeleImportBase()
    private var fenetre: UIWindow?

    /// À appeler juste avant de lancer l'import.
    func afficher() {
        preparerFenetre()
        modele.visible = true
    }

    /// À appeler une fois l'import terminé (succès ou échec).
    func masquer() {
        modele.visible = false
    }

    private func preparerFenetre() {
        guard fenetre == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
                ?? scenes.first else { return }

        let hote = UIHostingController(rootView: VueImportBase(modele: modele))
        hote.view.backgroundColor = .clear

        let f = FenetreTransparenteImport(windowScene: scene)
        f.rootViewController = hote
        f.backgroundColor = .clear
        f.windowLevel = .alert + 1
        f.isHidden = false
        fenetre = f
    }
}

/// Même rôle que `FenetreTransparente` de `PastillePrix` : laisse passer
/// tous les touchers, la fenêtre ne fait qu'afficher.
private final class FenetreTransparenteImport: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

@MainActor
@Observable
private final class ModeleImportBase {
    var visible = false
}

/// Rendu — repris à l'identique de `VuePastillePrix`, avec un indicateur de
/// progression en plus (l'import peut prendre plusieurs secondes sur une
/// grosse base, une pastille sans spinner laisserait croire à un blocage).
private struct VueImportBase: View {
    let modele: ModeleImportBase

    var body: some View {
        VStack(spacing: 0) {
            if modele.visible {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Import en cours")
                }
                .font(.headline)
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
        .animation(.easeInOut(duration: 0.2), value: modele.visible)
    }
}
#endif
