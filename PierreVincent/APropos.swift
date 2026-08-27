#if os(macOS)
import AppKit

/// Panneau « À propos » de Pierre-Vincent, avec la liste des bibliothèques
/// tierces (Credits) — seules dépendances externes de l'app, toutes gérées
/// par Swift Package Manager.
///
/// **Pourquoi `orderFrontStandardAboutPanel` et non une fenêtre maison** :
/// c'est le mécanisme standard Apple pour ajouter des mentions de licence au
/// panneau « À propos » système, via la clé `.credits`. Le reste du panneau
/// (icône, nom, version, copyright) reste celui que fournit le système —
/// rien d'autre à maintenir si la version de l'app change.
///
/// **À tenir à jour** : toute bibliothèque ajoutée ou retirée du projet doit
/// l'être ici aussi. La liste vient de `Package.resolved`
/// (`PierreVincent.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`).
@MainActor
func afficherAPropos() {
    let credits = NSMutableAttributedString()

    let titreStyle: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 11)
    ]
    let corpsStyle: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11)
    ]
    let paragrapheCentre: NSMutableParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        return p
    }()

    func ajouterBibliotheque(_ nom: String, _ version: String,
                             _ copyright: String, licence: String) {
        if credits.length > 0 { credits.append(NSAttributedString(string: "\n\n")) }
        credits.append(NSAttributedString(string: "\(nom) \(version)\n", attributes: titreStyle))
        credits.append(NSAttributedString(string: "\(copyright)\nSous licence \(licence).",
                                          attributes: corpsStyle))
    }

    ajouterBibliotheque("XLKit", "1.1.6",
                        "Copyright © 2025 The Acharya", licence: "MIT")
    ajouterBibliotheque("ZIPFoundation", "0.9.20",
                        "Copyright © 2017–2025 Thomas Zoechling", licence: "MIT")
    ajouterBibliotheque("swift-textfile", "0.5.2",
                        "Copyright © 2018 Steffan Andrews", licence: "MIT")

    credits.addAttribute(.paragraphStyle, value: paragrapheCentre,
                         range: NSRange(location: 0, length: credits.length))

    NSApp.orderFrontStandardAboutPanel(options: [
        .credits: credits
    ])
}
#endif
