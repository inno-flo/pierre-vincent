#if os(iOS)
import SwiftUI

/// Choix de la transition d'ouverture de la visionneuse.
///
/// **Deux méthodes coexistent, et c'est voulu** : la seconde est un essai, la
/// première reste le repli. Basculer se fait ici, en un mot.
///
/// - `.zoomSysteme` — `navigationTransition(.zoom(sourceID:in:))`, l'effet
///   standard d'Apple, celui de Photos. Geste de retour interactif compris.
///   **Sa durée n'est pas réglable**, le système ne l'expose pas.
/// - `.ressortMaison` — on refait l'agrandissement soi-même : la visionneuse
///   s'ouvre depuis le cadre exact de la vignette pressée, avec un ressort dont
///   on choisit la raideur. On y gagne la vitesse, on y perd le retour
///   interactif d'Apple.
enum TransitionVisionneuse {
    case zoomSysteme
    case ressortMaison

    /// Méthode en vigueur. Repasser à `.zoomSysteme` suffit à revenir en
    /// arrière : les deux chemins restent complets dans le code.
    static let choisie: TransitionVisionneuse = .ressortMaison

    static var estRessort: Bool { choisie == .ressortMaison }

    /// Ouvre la visionneuse en neutralisant l'animation de PRÉSENTATION quand
    /// l'agrandissement est joué à la main.
    ///
    /// Le neutraliser sur le contenu présenté ne suffit pas — c'est le
    /// changement d'état qui déclenche la présentation, et c'est donc lui qu'il
    /// faut envelopper. Sans cela la feuille glisse depuis le bas de l'écran
    /// pendant que l'image s'agrandit : deux mouvements contradictoires, et
    /// c'est le glissement qu'on voit.
    static func presenter(_ action: () -> Void) {
        guard estRessort else { action(); return }
        var sansAnimation = Transaction()
        sansAnimation.disablesAnimations = true
        withTransaction(sansAnimation, action)
    }

    /// Ressort d'ouverture. Court et peu rebondissant : l'effet doit paraître
    /// vif, pas élastique.
    static let ressort: Animation = .spring(response: 0.32, dampingFraction: 0.78)
}

/// Cadres des vignettes visibles, en coordonnées écran, collectés pour que la
/// visionneuse sache d'où partir.
///
/// Passe par une `PreferenceKey` et non par un `@State` écrit depuis la
/// vignette : écrire un état pendant le calcul de la mise en page relance le
/// rendu en boucle. Seules les vignettes réellement construites y figurent —
/// les grilles sont paresseuses.
struct CadresVignettes: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect],
                       nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Publie le cadre de cette vignette, pour servir de point de départ.
    func publieCadreVignette(_ identifiant: UUID) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: CadresVignettes.self,
                                       value: [identifiant: geo.frame(in: .global)])
            }
        )
    }
}

/// Applique la transition d'ouverture retenue, et elle seule.
struct TransitionOuverture: ViewModifier {
    let identifiant: UUID
    let espace: Namespace.ID

    func body(content: Content) -> some View {
        switch TransitionVisionneuse.choisie {
        case .zoomSysteme:
            content.navigationTransition(.zoom(sourceID: identifiant, in: espace))
        case .ressortMaison:
            // Rien ici : l'animation de présentation se coupe à l'ouverture,
            // sur le changement d'état (voir `presenter`).
            content
        }
    }
}
#endif
