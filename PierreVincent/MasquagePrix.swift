import SwiftUI

/// Gère le masquage temporaire des prix dans toute l'application.
///
/// Sur iPhone : on bascule l'état en secouant l'appareil.
/// Sur Mac : via les commandes « Afficher / Masquer les prix » du menu
/// « Présentation ».
///
/// L'état est mémorisé (@AppStorage) : il est conservé quand on quitte l'app.
enum MasquagePrix {
    /// Clé de stockage partagée par toutes les vues.
    static let cle = "prixMasques"
}

/// Modificateur qui floute son contenu lorsque les prix sont masqués.
/// On l'applique à chaque affichage de prix.
struct FloutagePrix: ViewModifier {
    @AppStorage(MasquagePrix.cle) private var prixMasques = false

    func body(content: Content) -> some View {
        content
            .blur(radius: prixMasques ? 6 : 0)
            // Empêche de « lire » le prix via le sélecteur d'accessibilité
            // lorsqu'il est masqué.
            .accessibilityHidden(prixMasques)
            .animation(.easeInOut(duration: 0.2), value: prixMasques)
    }
}

/// Variante qui ne floute que si `actif` est vrai (sinon ne fait rien).
/// Utile quand une même fonction d'affichage sert pour des prix et non-prix.
struct FloutageConditionnel: ViewModifier {
    let actif: Bool
    @AppStorage(MasquagePrix.cle) private var prixMasques = false

    func body(content: Content) -> some View {
        content
            .blur(radius: (actif && prixMasques) ? 6 : 0)
            .accessibilityHidden(actif && prixMasques)
            .animation(.easeInOut(duration: 0.2), value: prixMasques)
    }
}

extension View {
    /// Floute cette vue (un prix) quand le masquage des prix est actif.
    func flouteSiPrixMasques() -> some View {
        modifier(FloutagePrix())
    }
}

/// Affiche un montant en euros, floutable quand les prix sont masqués.
/// À utiliser partout à la place de `Text(formaterEuros(x))`.
struct PrixText: View {
    let montant: Double
    init(_ montant: Double) { self.montant = montant }

    var body: some View {
        Text(formaterEuros(montant))
            .flouteSiPrixMasques()
    }
}

#if os(iOS)
import UIKit

/// Détecte le secouement de l'appareil et bascule le masquage des prix.
/// UIKit envoie l'événement `.motionShake` ; on passe par une petite vue
/// UIKit hôte car SwiftUI ne l'expose pas directement.
struct DetecteurSecousse: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ControleurSecousse {
        ControleurSecousse()
    }
    func updateUIViewController(_ uiViewController: ControleurSecousse, context: Context) {}
}

final class ControleurSecousse: UIViewController {
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !isFirstResponder { becomeFirstResponder() }
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else { return }
        // Bascule l'état persistant : masqué <-> visible.
        let actuel = UserDefaults.standard.bool(forKey: MasquagePrix.cle)
        UserDefaults.standard.set(!actuel, forKey: MasquagePrix.cle)
    }
}

extension View {
    /// Active la détection du secouement pour basculer le masquage des prix.
    func detecteSecoussePourPrix() -> some View {
        background(DetecteurSecousse().frame(width: 0, height: 0))
    }
}
#endif
