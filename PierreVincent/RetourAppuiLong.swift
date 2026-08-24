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

    /// Durée d'appui avant que le geste aboutisse.
    ///
    /// 0,19 s, réglé à l'usage — la demi-seconde d'origine paraissait lente,
    /// puis 0,375 s l'était encore. Défini ICI pour que les quatre points
    /// d'appel restent d'accord ; le réglage se fait en un seul endroit.
    ///
    /// **Plancher à ne pas franchir sans y regarder** : trop court, le geste
    /// cesse de se distinguer d'un tap, et la fiche de détail deviendrait
    /// difficile à ouvrir sans déclencher la visionneuse.
    static let duree: Double = 0.19

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
