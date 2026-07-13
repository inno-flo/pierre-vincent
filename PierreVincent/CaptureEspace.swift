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

#endif
