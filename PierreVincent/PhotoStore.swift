import Foundation
import AppKit
import UniformTypeIdentifiers

/// Gère le stockage des photos sur le disque, à côté de la base de données.
/// Les images sont enregistrées dans un dossier « Photos » à l'intérieur du
/// conteneur Application Support de l'app. On garde ainsi la base légère et
/// on peut recopier tout le dossier vers un autre Mac.
enum PhotoStore {

    /// Dossier racine des données de l'app dans Application Support.
    static var dossierRacine: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dossier = base.appendingPathComponent("Pierre-Vincent", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier,
                                                 withIntermediateDirectories: true)
        return dossier
    }

    /// Dossier où sont rangées les photos.
    static var dossierPhotos: URL {
        let dossier = dossierRacine.appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier,
                                                 withIntermediateDirectories: true)
        return dossier
    }

    /// Importe un fichier image (jpeg/png/heic) glissé-déposé.
    /// Convertit tout en PNG pour une compatibilité maximale, et renvoie
    /// le nom de fichier stocké (à sauvegarder dans l'entrée Oeuvre).
    static func importerImage(depuis url: URL) -> String? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return enregistrer(image: image)
    }

    /// Enregistre une NSImage en PNG dans le dossier Photos.
    static func enregistrer(image: NSImage) -> String? {
        guard let png = pngData(de: image) else { return nil }
        let nom = UUID().uuidString + ".png"
        let dest = dossierPhotos.appendingPathComponent(nom)
        do {
            try png.write(to: dest)
            return nom
        } catch {
            return nil
        }
    }

    /// Charge une image à partir de son nom de fichier stocké.
    static func chargerImage(nom: String) -> NSImage? {
        guard !nom.isEmpty else { return nil }
        let url = dossierPhotos.appendingPathComponent(nom)
        return NSImage(contentsOf: url)
    }

    /// URL complète d'une photo (utile pour l'export).
    static func urlPhoto(nom: String) -> URL? {
        guard !nom.isEmpty else { return nil }
        return dossierPhotos.appendingPathComponent(nom)
    }

    /// Supprime le fichier photo du disque.
    static func supprimerPhoto(nom: String) {
        guard !nom.isEmpty else { return }
        let url = dossierPhotos.appendingPathComponent(nom)
        try? FileManager.default.removeItem(at: url)
    }

    /// Convertit une NSImage en données PNG.
    static func pngData(de image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Convertit une NSImage en données JPEG (pour l'export « standard »).
    static func jpegData(de image: NSImage, qualite: CGFloat = 0.9) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg,
                                  properties: [.compressionFactor: qualite])
    }

    /// Types de fichiers acceptés au glisser-déposer.
    static let typesAcceptes: [UTType] = [.jpeg, .png, .heic]

    /// Supprime du dossier Photos tous les fichiers qui ne sont plus référencés
    /// par une entrée. À appeler AU DÉMARRAGE de l'app : à ce moment l'historique
    /// d'annulation est vide, donc supprimer ces fichiers est sans risque pour
    /// le Cmd Z (contrairement à une suppression au moment du delete).
    ///
    /// `nomsUtilises` = l'ensemble des `photoNom` de toutes les entrées existantes.
    static func nettoyerPhotosOrphelines(nomsUtilises: Set<String>) {
        let fm = FileManager.default
        guard let fichiers = try? fm.contentsOfDirectory(
            at: dossierPhotos,
            includingPropertiesForKeys: nil) else { return }

        for fichier in fichiers {
            let nom = fichier.lastPathComponent
            // On ne touche qu'aux fichiers non référencés par une entrée.
            if !nomsUtilises.contains(nom) {
                try? fm.removeItem(at: fichier)
            }
        }
    }
}
