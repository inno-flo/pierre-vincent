#if os(iOS)
import SwiftUI
import SwiftData

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

    /// Méthode en vigueur : **le ressort maison**.
    ///
    /// Depuis que l'ouverture passe par le menu contextuel, le point de départ
    /// n'est plus la vignette mais l'APERÇU du menu — une taille intermédiaire,
    /// au centre de l'écran. La transition système, elle, repart toujours de la
    /// vignette : elle rejouait donc un agrandissement déjà joué par le menu,
    /// d'où deux mouvements superposés.
    ///
    /// Le ressort part de l'aperçu et va au plein écran : un seul mouvement,
    /// dans la continuité de ce que le doigt vient de faire.
    static let choisie: TransitionVisionneuse = .ressortMaison

    static var estRessort: Bool { choisie == .ressortMaison }

    /// Ouvre la visionneuse SANS animation de présentation.
    ///
    /// **C'est le menu contextuel qui porte le mouvement d'ouverture** : son
    /// aperçu grossit sous le doigt, puis s'étend quand on le tape. Toute
    /// animation ajoutée ici s'y superpose — on voyait deux agrandissements
    /// se chevaucher.
    ///
    /// Neutraliser sur le contenu présenté ne suffirait pas : c'est le
    /// changement d'état qui déclenche la présentation, et c'est donc lui
    /// qu'il faut envelopper.
    static func presenter(_ action: () -> Void) {
        var sansAnimation = Transaction()
        sansAnimation.disablesAnimations = true
        withTransaction(sansAnimation, action)
    }

    /// Ressort d'ouverture. Court et peu rebondissant : l'effet doit paraître
    /// vif, pas élastique.
    static let ressort: Animation = .spring(response: 0.32, dampingFraction: 0.78)

    /// Taille de l'aperçu du menu contextuel, en points.
    ///
    /// Sert DEUX fois : à dimensionner l'aperçu lui-même, et à donner à la
    /// visionneuse son point de départ. Les deux doivent rester d'accord,
    /// sinon l'agrandissement partirait d'une taille qu'on n'a jamais vue.
    static let taillePreview = CGSize(width: 320, height: 420)
}

/// Applique la transition d'ouverture retenue, et elle seule.
struct TransitionOuverture: ViewModifier {
    let identifiant: UUID
    let espace: Namespace.ID

    func body(content: Content) -> some View {
        // AUCUNE transition posée ici, dans les deux cas : depuis que
        // l'ouverture passe par le menu contextuel, c'est lui qui joue
        // l'agrandissement. La transition de zoom en ajoutait un SECOND,
        // superposé au premier — d'où un rendu confus.
        //
        // Les deux méthodes restent décrites dans l'enum : elles redeviendront
        // utiles le jour où la visionneuse s'ouvrira autrement que par le menu.
        content
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
    /// Commande « Œuvres proches » (CLIP), en second — nul partout sauf sur
    /// le Catalogue de la Réserve (voir `VueiOS.offreOeuvresProchesCLIP`).
    var onOeuvreProche: (() -> Void)? = nil

    func makeUIView(context: Context) -> UIView {
        let vue = UIView()
        vue.backgroundColor = .clear
        vue.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinateur.tapSimple))
        vue.addGestureRecognizer(tap)
        context.coordinator.contexteModele = context.environment.modelContext
        return vue
    }

    func updateUIView(_ vue: UIView, context: Context) {
        context.coordinator.oeuvre = oeuvre
        context.coordinator.onTap = onTap
        context.coordinator.onAfficher = onAfficher
        context.coordinator.onOeuvreProche = onOeuvreProche
        context.coordinator.contexteModele = context.environment.modelContext
    }

    func makeCoordinator() -> Coordinateur {
        Coordinateur(oeuvre: oeuvre, onTap: onTap, onAfficher: onAfficher,
                    onOeuvreProche: onOeuvreProche)
    }

    final class Coordinateur: NSObject, UIContextMenuInteractionDelegate {
        var oeuvre: Oeuvre
        var onTap: () -> Void
        var onAfficher: () -> Void
        var onOeuvreProche: (() -> Void)?
        /// Pour enregistrer la bascule de `favori` — captée depuis
        /// l'environnement SwiftUI, `Oeuvre` n'exposant pas son contexte.
        var contexteModele: ModelContext?

        init(oeuvre: Oeuvre, onTap: @escaping () -> Void,
             onAfficher: @escaping () -> Void, onOeuvreProche: (() -> Void)? = nil) {
            self.oeuvre = oeuvre
            self.onOeuvreProche = onOeuvreProche
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
                hote.preferredContentSize = TransitionVisionneuse.taillePreview
                return hote
            } actionProvider: { [weak self] _ in
                // Le libellé et l'icône reflètent l'état ACTUEL : recalculés
                // à chaque ouverture du menu, donc jamais périmés.
                let estFavori = self?.oeuvre.favori ?? false
                let bascule = UIAction(
                    title: estFavori ? "Retirer des favoris" : "Ajouter aux favoris",
                    image: UIImage(systemName: estFavori ? "star.slash" : "star")
                ) { [weak self] _ in
                    guard let self else { return }
                    // Bascule seule : l'œuvre reste dans SA feuille d'origine,
                    // et apparaît EN PLUS dans Favoris — jamais de doublon ni
                    // de déplacement.
                    basculerFavori(self.oeuvre, contexte: self.contexteModele)
                }
                // Second item, seulement là où `onOeuvreProche` est fourni
                // (Catalogue de la Réserve) : ouvre la même feuille
                // « Œuvres proches (CLIP) » que la rubrique Affinités CLIP.
                guard let onOeuvreProche = self?.onOeuvreProche else {
                    return UIMenu(children: [bascule])
                }
                let proches = UIAction(
                    title: "Œuvres proches",
                    image: UIImage(systemName: "wand.and.rays")
                ) { _ in onOeuvreProche() }
                return UIMenu(children: [bascule, proches])
            }
        }

        // PAS de suspension de la détection de secousse ici. Elle a existé,
        // pour empêcher le clavier de remonter avec l'aperçu — mais le remède
        // rendait le mal plus fréquent : rétablir le premier répondant après
        // chaque menu le faisait ensuite surgir à l'ouverture de n'importe
        // quel menu de barre d'outils. La détection ne passe plus par la
        // chaîne des répondants du tout (voir `DetecteurSecousse`).

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
