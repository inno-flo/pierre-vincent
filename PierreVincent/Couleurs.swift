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
}
