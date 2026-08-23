#if os(iOS)
import UIKit
import AudioToolbox

/// Retour donné quand un appui prolongé aboutit : une vibration ET un son bref.
///
/// **Centralisé ici** parce que le geste existe dans quatre vues — les
/// vignettes de `VueGalerie`, et les lignes comme les vignettes de `VueiOS`,
/// `VueOeuvresStructuree` et `VueDonsStructuree`. Quatre copies auraient fini
/// par diverger.
@MainActor
enum RetourAppuiLong {
    /// Générateur CONSERVÉ entre les gestes, et non créé au moment de frapper :
    /// un générateur neuf déclenche à froid, ce qui se ressent comme un choc
    /// mou. On le prépare dès que le doigt se pose (voir `preparer`).
    private static let moteur = UIImpactFeedbackGenerator(style: .heavy)

    /// Son système du « tock » de clavier — le tic le plus proche de ce qu'on
    /// veut ici.
    ///
    /// **Réserves à connaître.** Cet identifiant numérique n'est pas une
    /// constante publiée par Apple : il fonctionne de longue date, mais rien
    /// ne le garantit dans une version future. Et comme tout son système, il
    /// est **muet quand l'iPhone est en mode silencieux** — la vibration, elle,
    /// passe toujours. Le son est donc un supplément, jamais le seul signal.
    private static let sonTock: SystemSoundID = 1104

    /// À appeler dès le contact : chauffe le moteur, qui répond alors
    /// instantanément quand l'appui aboutit.
    static func preparer() { moteur.prepare() }

    /// À appeler quand l'appui prolongé a abouti.
    static func jouer() {
        moteur.impactOccurred(intensity: 1.0)
        AudioServicesPlaySystemSound(sonTock)
    }
}
#endif
