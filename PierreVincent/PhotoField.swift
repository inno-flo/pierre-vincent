#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Champ photo avec glisser-déposer d'un fichier .jpeg / .png / .heic.
/// Affiche l'aperçu si une photo existe, sinon une zone d'invite.
struct PhotoField: View {
    /// Nom de fichier de la photo (lié à l'entrée en cours d'édition).
    @Binding var photoNom: String
    @State private var survol = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(survol ? Color.accentColor : Color(nsColor: .separatorColor),
                                  style: StrokeStyle(lineWidth: survol ? 2 : 1,
                                                     dash: photoNom.isEmpty ? [5] : []))

                if let img = PhotoStore.chargerImage(nom: photoNom) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 320, height: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 26))
                            .foregroundStyle(.secondary)
                        Text("Glissez une image ici")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 320, height: 400)
            .onDrop(of: PhotoStore.typesAcceptes, isTargeted: $survol) { fournisseurs in
                traiterDrop(fournisseurs)
            }

            HStack {
                Button("Choisir…") { choisirFichier() }
                if !photoNom.isEmpty {
                    Button(role: .destructive) {
                        PhotoStore.supprimerPhoto(nom: photoNom)
                        photoNom = ""
                    } label: { Text("Retirer") }
                }
            }
        }
    }

    private func traiterDrop(_ fournisseurs: [NSItemProvider]) -> Bool {
        guard let f = fournisseurs.first else { return false }
        _ = f.loadObject(ofClass: URL.self) { url, _ in
            guard let url = url else { return }
            DispatchQueue.main.async {
                if !photoNom.isEmpty { PhotoStore.supprimerPhoto(nom: photoNom) }
                if let nom = PhotoStore.importerImage(depuis: url) {
                    photoNom = nom
                }
            }
        }
        return true
    }

    private func choisirFichier() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = PhotoStore.typesAcceptes
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if !photoNom.isEmpty { PhotoStore.supprimerPhoto(nom: photoNom) }
            if let nom = PhotoStore.importerImage(depuis: url) {
                photoNom = nom
            }
        }
    }
}

#endif
