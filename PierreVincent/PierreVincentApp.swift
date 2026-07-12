import SwiftUI
import SwiftData

/// Point d'entrée de l'application « Pierre-Vincent ».
@main
struct PierreVincentApp: App {
    /// Conteneur SwiftData : la base de données locale des œuvres.
    /// Le fichier est stocké dans Application Support/Pierre-Vincent.
    var conteneur: ModelContainer = {
        let schema = Schema([Oeuvre.self])
        let dossier = PhotoStore.dossierRacine
        let config = ModelConfiguration(
            schema: schema,
            url: dossier.appendingPathComponent("PierreVincent.store")
        )
        do {
            let c = try ModelContainer(for: schema, configurations: [config])
            // On attache NOTRE gestionnaire d'annulation partagé au contexte,
            // pour pouvoir y câbler Cmd Z / Cmd Maj Z depuis le menu.
            c.mainContext.undoManager = GestionAnnulation.shared.undoManager
            return c
        } catch {
            fatalError("Impossible de créer la base de données : \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(conteneur)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // On remplace Annuler/Rétablir pour viser le gestionnaire SwiftData.
            CommandGroup(replacing: .undoRedo) {
                Button("Annuler") {
                    let u = GestionAnnulation.shared.undoManager
                    if u.canUndo { u.undo() }
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Rétablir") {
                    let u = GestionAnnulation.shared.undoManager
                    if u.canRedo { u.redo() }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
    }
}
