import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Couleurs partagées de l'application.
extension Color {

    /// Orange international (accent de l'app).
    static let orangeInternational = Color(red: 1.0, green: 0.31, blue: 0.0)

    /// Fond général de l'app :
    /// - mode clair : crème (proche de l'interface de Claude) ;
    /// - mode sombre : le fond sombre standard du système.
    static let cremeFond: Color = {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil) { apparence in
            let sombre = apparence.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if sombre {
                // Fond sombre standard des fenêtres macOS.
                return NSColor.windowBackgroundColor
            } else {
                // Crème en mode clair.
                return NSColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1)
            }
        })
        #else
        return Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor.systemBackground
            } else {
                return UIColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1)
            }
        })
        #endif
    }()

    /// Fond de la légende des vignettes : blanc en clair, noir en sombre.
    static let fondLegende: Color = {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil) { apparence in
            let sombre = apparence.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return sombre ? NSColor.black : NSColor.white
        })
        #else
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? .black : .white
        })
        #endif
    }()

    /// Texte sur la légende : noir en clair, blanc en sombre (inverse du fond).
    static let texteLegende: Color = {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil) { apparence in
            let sombre = apparence.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return sombre ? NSColor.white : NSColor.black
        })
        #else
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? .white : .black
        })
        #endif
    }()

    // MARK: Thème « Graphite » de la vue Synthèse (sombre fixe)
    // Valeurs hex reprises telles quelles de la maquette Claude Design.

    /// Fond général de la Synthèse.
    static let graphitePageBg   = Color(red: 0x1A/255, green: 0x1A/255, blue: 0x1C/255)
    /// Fond des grandes cartes (Œuvres, Montants, Enchères).
    static let graphiteCardBg   = Color(red: 0x24/255, green: 0x24/255, blue: 0x26/255)
    /// Fond des tuiles internes (une nuance plus claire que la carte).
    static let graphiteTileBg   = Color(red: 0x2E/255, green: 0x2E/255, blue: 0x31/255)
    /// Texte principal (titres, libellés) sur fond sombre.
    static let graphiteTexte    = Color(red: 0xF2/255, green: 0xF2/255, blue: 0xF2/255)
    /// Bordure des cartes.
    static let graphiteBordure  = Color.white.opacity(0.08)

    /// Filet autour des vignettes de galerie :
    /// blanc cassé en mode clair, gris sombre en mode sombre.
    static let filetVignette: Color = {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil) { apparence in
            let sombre = apparence.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return sombre
                ? NSColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1)
                : NSColor(red: 0.93, green: 0.92, blue: 0.89, alpha: 1)   // blanc cassé
        })
        #else
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1)
                : UIColor(red: 0.93, green: 0.92, blue: 0.89, alpha: 1)   // blanc cassé
        })
        #endif
    }()
}
