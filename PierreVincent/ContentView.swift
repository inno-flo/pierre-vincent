import SwiftUI
import SwiftData
import AppKit

/// Vue principale : une seule fenêtre, cinq onglets.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @State private var messageImport: String?

    var body: some View {
        TabView {
            // Onglet 1 : vue compilée, lecture seule.
            VueFeuille(feuille: nil, lectureSeule: true, titre: "Œuvres")
                .tabItem { Label("Œuvres", systemImage: "square.grid.2x2") }

            VueFeuille(feuille: .tableauxVendus, lectureSeule: false, titre: "Tableaux vendus")
                .tabItem { Label("Tableaux vendus", systemImage: "paintpalette") }

            VueFeuille(feuille: .dessinsVendus, lectureSeule: false, titre: "Dessins vendus")
                .tabItem { Label("Dessins vendus", systemImage: "pencil.and.outline") }

            VueFeuille(feuille: .tapisVendus, lectureSeule: false, titre: "Tapis vendus")
                .tabItem { Label("Tapis vendus", systemImage: "square.grid.3x3.square") }

            VueFeuille(feuille: .oeuvresDonnees, lectureSeule: false, titre: "Œuvres données")
                .tabItem { Label("Œuvres données", systemImage: "gift") }
        }
        .frame(minWidth: 900, minHeight: 560)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    ouvrirDossierDonnees()
                } label: { Label("Ouvrir le dossier des données", systemImage: "folder") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    importerDonnees()
                } label: { Label("Importer…", systemImage: "square.and.arrow.down") }
            }
        }
        .alert("Import", isPresented: Binding(
            get: { messageImport != nil },
            set: { if !$0 { messageImport = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(messageImport ?? "") }
    }

    /// Ouvre, dans le Finder, le dossier unique qui contient TOUTES vos données
    /// (la base + les photos). C'est ce dossier qu'il faut copier pour changer
    /// de Mac. Il est normalement caché dans la Bibliothèque : ce bouton évite
    /// d'avoir à le chercher à la main.
    private func ouvrirDossierDonnees() {
        let dossier = PhotoStore.dossierRacine
        NSWorkspace.shared.activateFileViewerSelecting([dossier])
    }

    private func importerDonnees() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.prompt = "Importer ce dossier"
        p.message = "Choisissez le dossier de migration (contenant import.csv et Photos)"
        guard p.runModal() == .OK, let dossier = p.url else { return }
        let r = Import.importer(depuis: dossier, context: context)
        if let err = r.erreur {
            messageImport = "Échec : \(err)"
        } else {
            messageImport = "\(r.importees) entrée(s) importée(s)."
        }
    }
}
