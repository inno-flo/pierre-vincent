#if os(iOS)
import UIKit
import AudioToolbox

/// Retour donné quand un appui prolongé aboutit : une vibration ET un son bref.
///
/// **Usage réduit.** Les vignettes de galerie sont passées au menu contextuel
/// à aperçu, qui fournit son PROPRE retour haptique : y ajouter celui-ci
/// ferait double emploi. Il ne sert plus qu'à l'appui prolongé sur la photo de
/// la fiche de détail (`DetailiOS`).
///
/// Conservé tel quel : le réglage y est centralisé, et tout geste d'appui
/// prolongé qu'on rajouterait devra s'y raccorder plutôt que d'en refaire un.
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
    /// 0,07 s, réglé à l'usage par réductions successives depuis 0,5 s.
    /// Défini ICI pour que les points d'appel restent d'accord ; le réglage se
    /// fait donc en un seul endroit.
    ///
    /// **On est descendu très bas.** À ce niveau le geste ne se distingue
    /// presque plus d'un tap un peu appuyé, et le tap ouvre la FICHE quand
    /// l'appui ouvre la VISIONNEUSE : si des fiches deviennent difficiles à
    /// ouvrir, c'est cette valeur qu'il faut remonter, pas le geste qu'il faut
    /// revoir.
    ///
    /// Second effet, moins visible : le préchargement de l'image
    /// (`PhotoStore.prechargerImage`) est lancé au contact et dispose de ce
    /// délai pour décoder. Plus il raccourcit, plus l'ouverture risque de
    /// saccader la première fois.
    static let duree: Double = 0.07

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
