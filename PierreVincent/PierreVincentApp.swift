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
            // Active l'annulation/rétablissement (Cmd Z / Cmd Maj Z).
            c.mainContext.undoManager = UndoManager()
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
            // Retire le menu « Nouveau » inutile pour un utilitaire mono-fenêtre.
            CommandGroup(replacing: .newItem) {}
            // On garde le menu Édition standard, qui fournit Annuler/Rétablir.
        }
    }
}
