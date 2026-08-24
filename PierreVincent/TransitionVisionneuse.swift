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

    /// Méthode en vigueur : **celle d'Apple**.
    ///
    /// Le ressort maison a été essayé pour gagner en vitesse, puisque la
    /// transition système ne laisse pas régler sa durée. Il ouvre bien depuis
    /// la vignette, mais reste en deçà : l'agrandissement système est plus
    /// fluide, et il apporte le geste de retour interactif — celui qui suit le
    /// doigt à la fermeture.
    ///
    /// Le chemin `.ressortMaison` reste COMPLET dans le code : changer ce seul
    /// mot y ramène. Ne pas le supprimer sans raison.
    static let choisie: TransitionVisionneuse = .zoomSysteme

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

/// Menu contextuel à aperçu, façon Photos — **en UIKit**.
///
/// **Pourquoi pas `.contextMenu(menuItems:preview:)` de SwiftUI.** Celui-ci
/// affiche bien l'aperçu, mais ne prévient pas quand l'utilisateur le TAPE :
/// il fallait alors une commande « Afficher en grand » dans le menu, là où
/// Photos ouvre en plein écran d'un simple tap sur l'image. `UIKit` expose ce
/// rappel (`willPerformPreviewActionForMenuWith`), SwiftUI non.
///
/// La vue posée en overlay prend AUSSI le tap simple, faute de quoi elle le
/// confisquerait à la carte SwiftUI en dessous.
///
/// Le retour haptique est fourni par le système : ne pas en ajouter un second.
struct InteractionApercu: UIViewRepresentable {
    let oeuvre: Oeuvre
    /// Tap simple — ouvre la fiche de détail.
    let onTap: () -> Void
    /// Tap sur l'aperçu du menu — ouvre la visionneuse.
    let onAfficher: () -> Void

    func makeUIView(context: Context) -> UIView {
        let vue = UIView()
        vue.backgroundColor = .clear
        vue.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinateur.tapSimple))
        vue.addGestureRecognizer(tap)
        return vue
    }

    func updateUIView(_ vue: UIView, context: Context) {
        context.coordinator.oeuvre = oeuvre
        context.coordinator.onTap = onTap
        context.coordinator.onAfficher = onAfficher
    }

    func makeCoordinator() -> Coordinateur {
        Coordinateur(oeuvre: oeuvre, onTap: onTap, onAfficher: onAfficher)
    }

    final class Coordinateur: NSObject, UIContextMenuInteractionDelegate {
        var oeuvre: Oeuvre
        var onTap: () -> Void
        var onAfficher: () -> Void

        init(oeuvre: Oeuvre, onTap: @escaping () -> Void,
             onAfficher: @escaping () -> Void) {
            self.oeuvre = oeuvre
            self.onTap = onTap
            self.onAfficher = onAfficher
        }

        @objc func tapSimple() { onTap() }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            UIContextMenuConfiguration(identifier: nil) { [oeuvre] in
                let hote = UIHostingController(rootView: ApercuOeuvre(oeuvre: oeuvre))
                hote.view.backgroundColor = .black
                // Sans taille préférée, l'aperçu prend la dimension
                // intrinsèque de l'image — plusieurs milliers de points.
                hote.preferredContentSize = CGSize(width: 320, height: 420)
                return hote
            } actionProvider: { _ in
                UIMenu(children: [
                    // INERTE pour l'instant : la rubrique « Favoris » n'existe
                    // pas encore. L'entrée tient sa place dans le menu.
                    UIAction(title: "Ajouter aux favoris",
                             image: UIImage(systemName: "star")) { _ in }
                ])
            }
        }

        /// Appelé quand on TAPE l'aperçu — le geste de Photos.
        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
            animator: UIContextMenuInteractionCommitAnimating
        ) {
            // En complétion : la visionneuse s'ouvre une fois le menu refermé,
            // sinon les deux présentations se chevauchent.
            animator.addCompletion { [onAfficher] in onAfficher() }
        }
    }
}

/// Contenu de l'aperçu : la photo seule, en grand.
struct ApercuOeuvre: View {
    let oeuvre: Oeuvre

    var body: some View {
        if let image = PhotoStore.chargerImage(nom: oeuvre.photoNom) {
            Image(imagePlateforme: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
        }
    }
}

#endif
