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
                        .scaledToFit()
                        .padding(6)
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
            .frame(width: 180, height: 180)
            // On accepte le type générique « fichier » : plus robuste que de
            // lister les types image, car le Finder fournit une URL de fichier.
            .onDrop(of: [UTType.fileURL], isTargeted: $survol) { fournisseurs in
                traiterDrop(fournisseurs)
            }

            HStack {
                Button("Choisir…") { choisirFichier() }
                    .controlSize(.small)
                if !photoNom.isEmpty {
                    Button(role: .destructive) {
                        PhotoStore.supprimerPhoto(nom: photoNom)
                        photoNom = ""
                    } label: { Text("Retirer") }
                    .controlSize(.small)
                }
            }
        }
    }

    /// Reçoit le fichier glissé. On lit l'URL du fichier via son identifiant de
    /// type (fileURL), puis on vérifie que c'est bien une image acceptée.
    private func traiterDrop(_ fournisseurs: [NSItemProvider]) -> Bool {
        guard let fournisseur = fournisseurs.first else { return false }

        fournisseur.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let u = item as? URL {
                url = u
            }
            guard let fichier = url else { return }

            // Vérifie l'extension (jpeg/jpg/png/heic).
            let ext = fichier.pathExtension.lowercased()
            let extsOK = ["jpg", "jpeg", "png", "heic"]
            guard extsOK.contains(ext) else { return }

            DispatchQueue.main.async {
                if !photoNom.isEmpty { PhotoStore.supprimerPhoto(nom: photoNom) }
                if let nom = PhotoStore.importerImage(depuis: fichier) {
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
