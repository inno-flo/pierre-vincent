import SwiftUI
import Quartz   // fournit QLPreviewPanel (Quick Look natif de macOS)

/// Petit pont vers Quick Look natif de macOS.
/// On lui donne une URL de fichier, et il affiche l'aperçu plein écran
/// exactement comme dans le Finder (barre d'espace pour ouvrir/fermer).
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()
    private var url: URL?

    /// Ouvre (ou ferme) l'aperçu Quick Look pour l'URL donnée.
    func afficher(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.reloadData()
        } else {
            panel.dataSource = self
            panel.delegate = self
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Vrai si la fenêtre Quick Look est actuellement affichée.
    var estVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists()
            && (QLPreviewPanel.shared()?.isVisible ?? false)
    }

    /// Ferme la fenêtre Quick Look si elle est ouverte.
    func fermer() {
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        }
    }

    // Nombre d'éléments à prévisualiser (ici : un seul).
    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        url == nil ? 0 : 1
    }

    // L'élément à prévisualiser (l'URL de l'image).
    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem {
        (url as NSURL?) ?? NSURL()
    }
}

/// Modificateur SwiftUI pratique : déclenche Quick Look quand `urlAApercevoir`
/// prend une valeur, puis remet ce déclencheur à zéro.
extension View {
    func apercuQuickLook(_ url: Binding<URL?>) -> some View {
        self.onChange(of: url.wrappedValue) { _, nouvelle in
            if let u = nouvelle {
                QuickLookController.shared.afficher(u)
                // On remet à nil pour pouvoir redéclencher le même fichier.
                DispatchQueue.main.async { url.wrappedValue = nil }
            }
        }
    }
}
