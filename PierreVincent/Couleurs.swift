import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Thèmes de couleurs de l'application. Mémorisé dans les réglages partagés.
enum ThemeApp {
    static let cle = "themeApp"
    /// Identifiant du thème actif : "creme", "gris" ou "vert".
    /// Note : l'interface ne propose plus de sélecteur de thème — crème est
    /// le thème de l'application. "gris" et "vert" restent définis dans le
    /// code, mais rien ne les active. Le thème marron, puis le bleu, ont été
    /// supprimés.
    static var actuel: String {
        UserDefaults.standard.string(forKey: cle) ?? "creme"
    }
}

/// Triplet RVB (0-255).
private typealias RVB = (CGFloat, CGFloat, CGFloat)

/// Construit une couleur adaptative selon le thème actif ET le mode clair/sombre.
/// Chaque thème fournit sa valeur claire et sombre. Pour le thème crème, une
/// valeur sombre nil signifie « fond système par défaut ».
private func couleurTheme(
    cremeClair: RVB, cremeSombre: RVB?,
    grisClair: RVB, grisSombre: RVB,
    vertClair: RVB, vertSombre: RVB
) -> Color {
    func n(_ c: RVB) -> RVB { (c.0/255, c.1/255, c.2/255) }
    #if os(macOS)
    return Color(nsColor: NSColor(name: nil) { app in
        let sombre = app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let c: RVB?
        switch ThemeApp.actuel {
        case "gris":   c = sombre ? grisSombre : grisClair
        case "vert":   c = sombre ? vertSombre : vertClair
        default:       c = sombre ? cremeSombre : cremeClair
        }
        guard let c else { return NSColor.windowBackgroundColor }
        let v = n(c); return NSColor(red: v.0, green: v.1, blue: v.2, alpha: 1)
    })
    #else
    return Color(uiColor: UIColor { traits in
        let sombre = traits.userInterfaceStyle == .dark
        let c: RVB?
        switch ThemeApp.actuel {
        case "gris":   c = sombre ? grisSombre : grisClair
        case "vert":   c = sombre ? vertSombre : vertClair
        default:       c = sombre ? cremeSombre : cremeClair
        }
        guard let c else { return UIColor.systemBackground }
        let v = n(c); return UIColor(red: v.0, green: v.1, blue: v.2, alpha: 1)
    })
    #endif
}

extension Color {

    /// Accent orange — identique dans tous les thèmes.
    static let orangeInternational = Color(red: 1.0, green: 0.31, blue: 0.0)

    /// Fond général de l'app.
    static var cremeFond: Color {
        couleurTheme(
            cremeClair: (250, 245, 235), cremeSombre: nil,
            grisClair:  (231, 236, 240), grisSombre:  (15, 21, 25),
            vertClair:  (230, 237, 230), vertSombre:  (18, 24, 20))
    }

    /// Fond des cellules / tuiles / légendes.
    static var fondLegende: Color {
        couleurTheme(
            cremeClair: (255, 255, 255), cremeSombre: (0, 0, 0),
            grisClair:  (255, 255, 255), grisSombre:  (22, 24, 28),
            vertClair:  (251, 253, 250), vertSombre:  (22, 24, 28))
    }

    /// Texte sur la légende. Noir/blanc selon le mode clair/sombre.
    static var texteLegende: Color {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil) { app in
            let sombre = app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return sombre ? .white : .black
        })
        #else
        return Color(uiColor: UIColor { t in
            return t.userInterfaceStyle == .dark ? .white : .black
        })
        #endif
    }

    /// Couleur du texte principal des vues (noir/blanc selon le mode).
    static var textePrincipal: Color {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil) { app in
            let sombre = app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return sombre ? .white : .black
        })
        #else
        return Color(uiColor: UIColor { t in
            return t.userInterfaceStyle == .dark ? .white : .black
        })
        #endif
    }

    /// Fond des cellules de la barre latérale iOS (blanc en clair, gris sombre).
    static var fondCelluleSidebar: Color {
        couleurTheme(
            cremeClair: (255, 255, 255), cremeSombre: (28, 28, 30),
            grisClair:  (255, 255, 255), grisSombre:  (28, 30, 34),
            vertClair:  (255, 255, 255), vertSombre:  (28, 30, 34))
    }

    /// Fond de la cellule sélectionnée dans la barre latérale iOS : une
    /// teinte visiblement plus soutenue que `fondCelluleSidebar`, pour
    /// donner un contraste net à la section active (sans utiliser l'orange
    /// de marque, réservé aux valeurs chiffrées).
    static var fondCelluleSidebarSelectionnee: Color {
        couleurTheme(
            cremeClair: (234, 224, 204), cremeSombre: (54, 54, 58),
            grisClair:  (204, 214, 221), grisSombre:  (46, 51, 58),
            vertClair:  (204, 219, 206), vertSombre:  (40, 51, 43))
    }

    /// Fond de la rubrique sélectionnée dans la sidebar macOS : un marron, en
    /// remplacement du bleu de sélection système.
    static var fondSelectionSidebarMac: Color {
        // Mode clair : marron éclairci de 50 % depuis le (163, 118, 78)
        // initial. Mode sombre : marron assombri de 50 % depuis (178, 134, 94).
        // Le libellé est en BLANC dans les deux cas (texteSelectionSidebarMac).
        couleurTheme(
            cremeClair: (209, 187, 167), cremeSombre: (89, 67, 47),
            grisClair:  (209, 187, 167), grisSombre:  (89, 67, 47),
            vertClair:  (209, 187, 167), vertSombre:  (89, 67, 47))
    }

    /// Libellé et icône de la rubrique sélectionnée dans la sidebar macOS :
    /// **blanc dans les deux modes**, sur le fond marron de la sélection.
    static var texteSelectionSidebarMac: Color { .white }

    // MARK: Thème « Graphite » de la vue Synthèse (sombre fixe)
    static let graphitePageBg   = Color(red: 0x1A/255, green: 0x1A/255, blue: 0x1C/255)
    static let graphiteCardBg   = Color(red: 0x24/255, green: 0x24/255, blue: 0x26/255)
    static let graphiteTileBg   = Color(red: 0x2E/255, green: 0x2E/255, blue: 0x31/255)
    static let graphiteTexte    = Color(red: 0xF2/255, green: 0xF2/255, blue: 0xF2/255)
    static let graphiteBordure  = Color.white.opacity(0.08)

    /// Filet autour des vignettes.
    static var filetVignette: Color {
        couleurTheme(
            cremeClair: (237, 235, 227), cremeSombre: (51, 51, 56),
            grisClair:  (234, 239, 243), grisSombre:  (26, 32, 39),
            vertClair:  (233, 239, 234), vertSombre:  (25, 33, 27))
    }
}
