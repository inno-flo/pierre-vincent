#if os(macOS)
import SwiftUI
import AppKit

/// Capte l'appui sur la barre d'espace au niveau de la fenêtre, sans perturber
/// la sélection du tableau (contrairement à un bouton caché avec raccourci).
/// Quand l'utilisateur presse Espace, on appelle `action`.
/// On ignore l'appui si le focus est dans un champ de saisie (pour ne pas
/// gêner la frappe d'espaces dans du texte).
struct CaptureEspace: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let vue = VueCapteur()
        vue.action = action
        return vue
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? VueCapteur)?.action = action
    }

    final class VueCapteur: NSView {
        var action: (() -> Void)?
        private var moniteur: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // On retire un éventuel ancien moniteur avant d'en poser un nouveau.
            if let m = moniteur { NSEvent.removeMonitor(m); moniteur = nil }
            guard window != nil else { return }

            moniteur = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }

                // Barre d'espace = keyCode 49.
                guard event.keyCode == 49 else { return event }

                // Si le focus est dans un champ de saisie, on laisse l'espace
                // passer (pour taper des espaces dans le texte). On couvre les
                // deux cas : NSTextView (zones multilignes comme Remarques) et
                // NSTextField / son éditeur de champ (champs d'une ligne).
                if let responder = self.window?.firstResponder {
                    if responder is NSTextView { return event }
                    if responder is NSTextField { return event }
                    // L'éditeur interne d'un NSTextField est un NSText/NSTextView
                    // dont le délégué est le champ : ce cas est déjà couvert
                    // ci-dessus, mais on reste prudent avec une vérification.
                    if String(describing: type(of: responder)).contains("Text") {
                        return event
                    }
                }

                self.action?()
                return nil   // on consomme l'événement (l'espace ne se propage pas)
            }
        }

        deinit {
            if let m = moniteur { NSEvent.removeMonitor(m) }
        }
    }
}


/// Capte ⌘A au niveau de la fenêtre, sur le même patron que `CaptureEspace`.
///
/// Un `Button().keyboardShortcut("a", modifiers: .command).hidden()` remplissait
/// ce rôle, mais ne répondait que dans certaines rubriques : ce raccourci-là
/// dépend du focus SwiftUI et de la concurrence avec le « Tout sélectionner »
/// standard du menu Édition, qui vise le premier répondant. Le moniteur
/// `NSEvent` ne dépend d'aucun des deux — c'est le seul mécanisme clavier qui
/// se soit montré fiable sur ce projet (voir CLAUDE.md).
struct CaptureCommandeA: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let vue = VueCapteur()
        vue.action = action
        return vue
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? VueCapteur)?.action = action
    }

    final class VueCapteur: NSView {
        var action: (() -> Void)?
        private var moniteur: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let m = moniteur { NSEvent.removeMonitor(m); moniteur = nil }
            guard window != nil else { return }

            moniteur = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }
                guard event.modifierFlags.contains(.command),
                      event.charactersIgnoringModifiers?.lowercased() == "a"
                else { return event }

                // Dans un champ de saisie, ⌘A doit sélectionner le TEXTE :
                // on laisse alors l'événement suivre son cours.
                if let responder = self.window?.firstResponder {
                    if responder is NSTextView || responder is NSTextField { return event }
                    if String(describing: type(of: responder)).contains("Text") {
                        return event
                    }
                }

                self.action?()
                return nil   // consommé : pas de bip, pas de double traitement
            }
        }

        deinit {
            if let m = moniteur { NSEvent.removeMonitor(m) }
        }
    }
}


/// Capte la touche Échap au niveau de la fenêtre, même patron que
/// `CaptureEspace`. Monté seulement tant qu'il y a quelque chose à fermer.
///
/// Moniteur `NSEvent` et non `.onKeyPress(.escape)` : sur ce projet, les
/// mécanismes clavier de SwiftUI se sont montrés dépendants d'un focus qu'on
/// ne maîtrise pas (voir CLAUDE.md, et le cas de ⌘A).
struct CaptureEchap: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let vue = VueCapteur()
        vue.action = action
        return vue
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? VueCapteur)?.action = action
    }

    final class VueCapteur: NSView {
        var action: (() -> Void)?
        private var moniteur: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let m = moniteur { NSEvent.removeMonitor(m); moniteur = nil }
            guard window != nil else { return }

            moniteur = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }
                guard event.keyCode == 53 else { return event }   // Échap
                self.action?()
                return nil
            }
        }

        deinit {
            if let m = moniteur { NSEvent.removeMonitor(m) }
        }
    }
}


/// Capte les flèches ← et → au niveau de la fenêtre, et les CONSOMME.
///
/// Monté seulement pendant l'affichage de la visionneuse. C'est ce qui empêche
/// la galerie en arrière-plan de les recevoir : elle porte ses propres
/// `.onKeyPress(.leftArrow/.rightArrow)`, et sans interception on naviguait
/// dans le panneau au lieu des images — visible dans l'inspecteur.
///
/// Un moniteur local est appelé AVANT la chaîne de répondants, donc avant
/// `.onKeyPress` : renvoyer `nil` suffit à couper court.
struct CaptureFlechesLaterales: NSViewRepresentable {
    let onGauche: () -> Void
    let onDroite: () -> Void

    func makeNSView(context: Context) -> NSView {
        let vue = VueCapteur()
        vue.onGauche = onGauche
        vue.onDroite = onDroite
        return vue
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let vue = nsView as? VueCapteur else { return }
        vue.onGauche = onGauche
        vue.onDroite = onDroite
    }

    final class VueCapteur: NSView {
        var onGauche: (() -> Void)?
        var onDroite: (() -> Void)?
        private var moniteur: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let m = moniteur { NSEvent.removeMonitor(m); moniteur = nil }
            guard window != nil else { return }

            moniteur = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }
                switch event.keyCode {
                case 123: self.onGauche?()   // ←
                case 124: self.onDroite?()   // →
                default:  return event
                }
                return nil
            }
        }

        deinit {
            if let m = moniteur { NSEvent.removeMonitor(m) }
        }
    }
}


/// Zone de l'interface qui reçoit les flèches ↑↓, pilotée explicitement par
/// l'application (et non par le focus SwiftUI ni par le premier répondant
/// AppKit, qui se sont tous deux révélés non fiables ici : le panneau qui
/// paraissait focalisé n'était pas celui qui recevait les touches).
///
/// La zone bascule sur un geste **de l'utilisateur** : choisir une rubrique
/// dans la sidebar met « sidebar », sélectionner une œuvre met « contenu ».
enum ZoneClavier {
    static let cle = "zoneClavier"
    static let sidebar = "sidebar"
    static let contenu = "contenu"

    static var actuelle: String {
        UserDefaults.standard.string(forKey: cle) ?? sidebar
    }
    static func definir(_ zone: String) {
        UserDefaults.standard.set(zone, forKey: cle)
    }
}

/// Capte les flèches ↑ et ↓ au niveau de la fenêtre et appelle `action(delta)`
/// — mais **uniquement** quand la zone active est `zone`. Les autres cas sont
/// relayés tels quels, pour qu'un autre capteur (ou AppKit) s'en charge.
///
/// L'événement est consommé quand il est traité : c'est ce qui supprime le bip
/// système et empêche un scroll view de défiler à la place de la navigation.
struct CaptureFleches: NSViewRepresentable {
    /// Zone dans laquelle ce capteur est compétent.
    let zone: String
    /// Vrai pour se désactiver (édition en cours, par exemple).
    var suspendu: Bool = false
    /// -1 pour ↑, +1 pour ↓.
    let action: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let vue = VueCapteurFleches()
        vue.configurer(zone: zone, suspendu: suspendu, action: action)
        return vue
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? VueCapteurFleches)?.configurer(zone: zone, suspendu: suspendu, action: action)
    }

    final class VueCapteurFleches: NSView {
        private var zone = ZoneClavier.sidebar
        private var suspendu = false
        private var action: ((Int) -> Void)?
        private var moniteur: Any?

        func configurer(zone: String, suspendu: Bool, action: @escaping (Int) -> Void) {
            self.zone = zone
            self.suspendu = suspendu
            self.action = action
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let m = moniteur { NSEvent.removeMonitor(m); moniteur = nil }
            guard window != nil else { return }

            moniteur = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                // 126 = flèche haut, 125 = flèche bas.
                let delta: Int
                switch event.keyCode {
                case 126: delta = -1
                case 125: delta = +1
                default:  return event
                }
                guard !self.suspendu else { return event }
                // Ce capteur ne traite que « sa » zone.
                guard ZoneClavier.actuelle == self.zone else { return event }
                // Jamais pendant une saisie de texte (même garde que CaptureEspace).
                if let responder = self.window?.firstResponder {
                    if responder is NSTextView || responder is NSTextField { return event }
                    if String(describing: type(of: responder)).contains("Text") { return event }
                }
                self.action?(delta)
                return nil   // traité : on consomme (pas de bip, pas de défilement)
            }
        }

        deinit {
            if let m = moniteur { NSEvent.removeMonitor(m) }
        }
    }
}

#endif
