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
        DetectionSecousse.controleur = self
        reprendreEcoute()
    }

    /// Redevient premier répondant, sauf si l'écoute est suspendue.
    func reprendreEcoute() {
        guard !DetectionSecousse.suspendue, !isFirstResponder else { return }
        becomeFirstResponder()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else { return }
        // Bascule l'état persistant : masqué <-> visible.
        let actuel = UserDefaults.standard.bool(forKey: MasquagePrix.cle)
        UserDefaults.standard.set(!actuel, forKey: MasquagePrix.cle)
    }
}

/// Interrupteur de la détection de secousse.
///
/// **Pourquoi il existe.** `ControleurSecousse` est le SEUL premier répondant
/// de l'app iOS : il n'affiche rien, il ne sert qu'à recevoir `motionEnded`.
/// Or un menu contextuel présente son aperçu dans sa PROPRE fenêtre, et le
/// système réévalue alors le premier répondant — un contrôleur qui ne vend
/// aucune vue de saisie fait remonter le clavier système, qu'on voyait
/// apparaître en même temps que l'aperçu.
///
/// On suspend donc l'écoute le temps du menu, puis on la reprend. Personne ne
/// secoue son téléphone pendant un appui prolongé : la fonction ne perd rien.
@MainActor
enum DetectionSecousse {
    fileprivate static weak var controleur: ControleurSecousse?
    fileprivate private(set) static var suspendue = false

    /// À appeler quand un menu contextuel s'affiche.
    static func suspendre() {
        suspendue = true
        controleur?.resignFirstResponder()
    }

    /// À appeler quand il se referme.
    static func reprendre() {
        suspendue = false
        controleur?.reprendreEcoute()
    }
}

extension View {
    /// Active la détection du secouement pour basculer le masquage des prix.
    func detecteSecoussePourPrix() -> some View {
        background(DetecteurSecousse().frame(width: 0, height: 0))
    }
}
#endif
