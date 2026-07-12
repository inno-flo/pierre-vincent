import SwiftUI
import SwiftData

/// Petite fiche pour ajouter, remplacer ou retirer la photo d'une entrée.
/// S'ouvre en double-cliquant la vignette dans le tableau.
struct EditeurPhoto: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var oeuvre: Oeuvre
    var onFini: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Photo de l'entrée").font(.headline)

            PhotoField(photoNom: $oeuvre.photoNom)

            HStack {
                Spacer()
                Button("Terminé") {
                    onFini()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 320, height: 320)
    }
}
