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
import SwiftUI
import CoreMotion

/// Détecte le secouement de l'appareil et bascule le masquage des prix.
///
/// **Passe par CoreMotion, et NON par la chaîne des répondants.** La version
/// précédente était un `UIViewController` de taille nulle qui se déclarait
/// `canBecomeFirstResponder` et prenait le focus au seul titre de recevoir
/// `motionEnded` — le SEUL premier répondant d'une app qui ne contient aucun
/// champ de saisie.
///
/// Ce montage faisait **remonter le clavier système**, d'abord à l'ouverture
/// d'un menu contextuel, puis — dès qu'on a rétabli le focus après coup — à
/// l'ouverture de n'importe quel menu de barre d'outils. Chaque présentation
/// fait réévaluer le premier répondant, et un répondant qui ne vend aucune vue
/// de saisie obtient le clavier par défaut.
///
/// Lire l'accéléromètre supprime la cause : l'app n'a plus de premier
/// répondant du tout.
final class DetecteurSecousse: @unchecked Sendable {
    static let partage = DetecteurSecousse()
    private init() {}

    private let moteur = CMMotionManager()
    /// Dernière bascule, pour ne pas enchaîner plusieurs déclenchements sur
    /// un même secouement — qui dure le temps de plusieurs mesures.
    private var derniereBascule = Date.distantPast

    /// Seuil de déclenchement, en g. L'appareil au repos mesure 1 g (la
    /// pesanteur) ; un secouement franc dépasse largement 2 g. Trop bas, une
    /// marche rapide suffirait à masquer les prix.
    private let seuil = 2.2
    /// Délai minimal entre deux bascules.
    private let repos: TimeInterval = 1.0

    func demarrer() {
        guard moteur.isAccelerometerAvailable, !moteur.isAccelerometerActive else { return }
        moteur.accelerometerUpdateInterval = 1.0 / 50.0
        // Livraison sur la file PRINCIPALE : la bascule met à jour un réglage
        // que `@AppStorage` observe, donc l'interface.
        moteur.startAccelerometerUpdates(to: .main) { [weak self] mesure, _ in
            guard let self, let a = mesure?.acceleration else { return }
            let intensite = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            guard intensite > self.seuil else { return }
            let maintenant = Date()
            guard maintenant.timeIntervalSince(self.derniereBascule) > self.repos else { return }
            self.derniereBascule = maintenant

            let actuel = UserDefaults.standard.bool(forKey: MasquagePrix.cle)
            UserDefaults.standard.set(!actuel, forKey: MasquagePrix.cle)
        }
    }
}

extension View {
    /// Active la détection du secouement pour basculer le masquage des prix.
    func detecteSecoussePourPrix() -> some View {
        onAppear { DetecteurSecousse.partage.demarrer() }
    }
}
#endif
