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

    /// Accent orange — celui de « Ventes et dons », et la valeur par défaut.
    static let orangeInternational = Color(red: 1.0, green: 0.31, blue: 0.0)

    /// Accent bleu ardoise — celui de la section « Réserve ».
    ///
    /// Deux accents cohabitent : la couleur dit d'un coup d'œil dans quelle
    /// section on se trouve, sans lire le titre. Éclairci en mode sombre, où
    /// le bleu profond se confondrait avec le fond.
    static var bleuArdoise: Color {
        couleurTheme(
            cremeClair: (70, 100, 135), cremeSombre: (132, 168, 205),
            grisClair:  (70, 100, 135), grisSombre:  (132, 168, 205),
            vertClair:  (70, 100, 135), vertSombre:  (132, 168, 205))
    }

    /// Accent taupe chaud — celui de la rubrique **Favoris**.
    ///
    /// Troisième accent, aux côtés de l'orange (« Ventes et dons ») et du bleu
    /// ardoise (« Réserve ») : Favoris est une rubrique ISOLÉE, qui n'appartient
    /// à aucune des deux sections, et sa teinte propre le dit.
    ///
    /// Un brun-gris chaud, franchement distinct des deux autres.
    ///
    /// **La valeur claire est contrainte par la pastille de comptage**, qui
    /// pose du texte BLANC sur un fond plein de cette teinte : (125, 106, 88)
    /// donne 5,15:1, au-dessus du seuil AA. Un taupe plus clair est vite
    /// illisible — (138, 118, 98), essayé d'abord, tombait à 4,33:1. Même
    /// écueil que la sélection de sidebar macOS, où la plus claire des deux
    /// nuances comparées avait dû être écartée pour cette raison.
    ///
    /// Éclairci en mode sombre, où un taupe foncé se confondrait avec le fond
    /// — même parti que `bleuArdoise`, et même compromis assumé : la teinte
    /// claire y sert surtout d'icône et de contour.
    static var taupeChaud: Color {
        couleurTheme(
            cremeClair: (125, 106, 88), cremeSombre: (192, 172, 148),
            grisClair:  (125, 106, 88), grisSombre:  (192, 172, 148),
            vertClair:  (125, 106, 88), vertSombre:  (192, 172, 148))
    }

    /// Fond général de l'app — **la PAGE**, sous les cartes.
    ///
    /// **Sur iOS, c'est le fond GROUPÉ** (`systemGroupedBackground`, gris très
    /// clair en mode clair), et non `systemBackground` (blanc). L'app suit
    /// partout la sémantique groupée d'iOS : page légèrement grise, cartes
    /// blanches posées dessus (`fondLegende`). C'est cet écart, et lui seul,
    /// qui détache les cartes ; intervertir les deux les rend indistinguables,
    /// ce qui avait rendu la sidebar entièrement blanche.
    ///
    /// En mode sombre l'écart est le même dans l'autre sens : page noire,
    /// cartes gris foncé.
    ///
    /// `fondGroupe`, créée un temps pour la seule sidebar, a été absorbée ici :
    /// les deux désignaient exactement la même couleur, et deux noms pour une
    /// même teinte finissent par diverger.
    ///
    /// **macOS : valeur FIXE, et non `.windowBackgroundColor`.** Sur macOS 26,
    /// cette couleur système résout en BLANC PUR (255,255,255) — identique à
    /// `fondLegende` — au lieu du gris de fenêtre traditionnel de macOS (voir
    /// CLAUDE.md, « windowBackgroundColor = controlBackgroundColor »). La
    /// valeur ci-dessous est calée sur le gris de page iOS
    /// (`systemGroupedBackground`, mesuré à 242,242,247), pour un rendu
    /// homogène entre les deux plateformes. Le mode sombre garde le
    /// comportement système par défaut, non concerné par ce défaut de macOS.
    static var cremeFond: Color {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil) { app in
            let sombre = app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if sombre { return .windowBackgroundColor }
            return NSColor(red: 242/255, green: 242/255, blue: 247/255, alpha: 1)
        })
        #else
        return Color(uiColor: .systemGroupedBackground)
        #endif
    }

    /// Fond des cellules / tuiles / légendes — **la CARTE**, posée sur la page.
    ///
    /// **Sur iOS, c'est `secondarySystemGroupedBackground`** : BLANC en mode
    /// clair, gris foncé en sombre. Il forme la paire avec `cremeFond`, et les
    /// deux doivent rester du même jeu — un fond groupé sous une carte non
    /// groupée (ou l'inverse) donne deux teintes identiques, donc une carte
    /// invisible.
    static var fondLegende: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    /// Fond d'une TUILE posée DANS une carte — le troisième niveau.
    ///
    /// **Sans lui, les tuiles de la Synthèse étaient invisibles** : elles
    /// utilisaient `fondLegende`, exactement comme la carte qui les contient,
    /// donc une teinte sur la même teinte. Le défaut ne datait pas de
    /// l'inversion des fonds — c'était gris sur gris avant, blanc sur blanc
    /// après —, seule sa couleur a changé.
    ///
    /// iOS a une hiérarchie à trois niveaux faite pour cela : page
    /// (`systemGrouped`, 242) → carte (`secondarySystemGrouped`, 255) → tuile
    /// (`tertiarySystemGrouped`, 242). L'alternance clair/blanc/clair est
    /// voulue par Apple ; en sombre elle est progressive (0 → 28 → 44).
    ///
    /// **Sur macOS, calée sur `cremeFond`** : il n'existe pas d'équivalent
    /// natif à un troisième niveau « tertiaire » côté macOS, et
    /// `underPageBackgroundColor` (246,246,246), utilisé avant que `cremeFond`
    /// ait sa propre valeur fixe, en différait légèrement (242,242,247) —
    /// un écart involontaire entre page et tuile. Les deux partagent
    /// maintenant exactement la même teinte, comme le fait déjà iOS en mode
    /// clair (page et tuile valent toutes deux 242,242,247 ; seule la carte,
    /// blanche, tranche entre les deux).
    static var fondTuile: Color {
        #if os(macOS)
        return cremeFond
        #else
        return Color(uiColor: .tertiarySystemGroupedBackground)
        #endif
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
    /// remplacement du bleu de sélection système. Le libellé est en BLANC dans
    /// les deux modes (`texteSelectionSidebarMac`).
    ///
    /// Mode clair : (142, 134, 127), la plus foncée des deux nuances qui ont
    /// été comparées à l'écran — le texte blanc contrastait mal sur la claire
    /// (209, 187, 167). Le choix est arrêté : le bouton de comparaison en pied
    /// de sidebar et son réglage `selectionFoncee` ont été retirés.
    /// Le mode sombre garde son propre marron, où le blanc passe déjà bien.
    static var fondSelectionSidebarMac: Color {
        couleurTheme(
            cremeClair: (142, 134, 127), cremeSombre: (89, 67, 47),
            grisClair:  (142, 134, 127), grisSombre:  (89, 67, 47),
            vertClair:  (142, 134, 127), vertSombre:  (89, 67, 47))
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


/// Accent de la rubrique affichée, transporté par l'environnement.
///
/// **Pourquoi l'environnement plutôt qu'un paramètre.** L'accent sert dans une
/// dizaine de vues imbriquées — vignettes, pastilles, prix, boutons de la
/// visionneuse, éditeur —, dont plusieurs sont partagées entre les deux
/// sections. Le passer de main en main aurait demandé un paramètre à chaque
/// étage ; posé une fois sur la colonne de contenu, il descend tout seul, y
/// compris dans les feuilles et les présentations plein écran.
///
/// Valeur par défaut : l'orange. Une vue qui ne déclare rien reste donc dans
/// la teinte de « Ventes et dons ».
private struct CleAccentRubrique: EnvironmentKey {
    static let defaultValue = Color.orangeInternational
}

extension EnvironmentValues {
    var accentRubrique: Color {
        get { self[CleAccentRubrique.self] }
        set { self[CleAccentRubrique.self] = newValue }
    }
}
