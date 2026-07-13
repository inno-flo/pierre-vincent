import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
/// Type d'image de la plateforme : NSImage sur Mac.
typealias ImagePlateforme = NSImage
#else
import UIKit
/// Type d'image de la plateforme : UIImage sur iPhone/iPad.
typealias ImagePlateforme = UIImage
#endif

/// Gère le stockage des photos sur le disque, à côté de la base de données.
/// Les images sont enregistrées dans un dossier « Photos » à l'intérieur du
/// conteneur Application Support de l'app. On garde ainsi la base légère et
/// on peut recopier tout le dossier vers un autre appareil.
///
/// Ce fichier fonctionne sur Mac ET iPhone : le type d'image (NSImage/UIImage)
/// et les conversions sont adaptés à chaque plateforme via `#if os(macOS)`.
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

    /// Importe un fichier image (jpeg/png/heic).
    /// Convertit tout en PNG pour une compatibilité maximale, et renvoie
    /// le nom de fichier stocké (à sauvegarder dans l'entrée Oeuvre).
    static func importerImage(depuis url: URL) -> String? {
        #if os(macOS)
        guard let image = NSImage(contentsOf: url) else { return nil }
        #else
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        #endif
        return enregistrer(image: image)
    }

    /// Enregistre une image en PNG dans le dossier Photos.
    static func enregistrer(image: ImagePlateforme) -> String? {
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
    static func chargerImage(nom: String) -> ImagePlateforme? {
        guard !nom.isEmpty else { return nil }
        let url = dossierPhotos.appendingPathComponent(nom)
        #if os(macOS)
        return NSImage(contentsOf: url)
        #else
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
        #endif
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

    /// Convertit une image en données PNG.
    static func pngData(de image: ImagePlateforme) -> Data? {
        #if os(macOS)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #else
        return image.pngData()
        #endif
    }

    /// Convertit une image en données JPEG (pour l'export « standard »).
    static func jpegData(de image: ImagePlateforme, qualite: CGFloat = 0.9) -> Data? {
        #if os(macOS)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg,
                                  properties: [.compressionFactor: qualite])
        #else
        return image.jpegData(compressionQuality: qualite)
        #endif
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

// MARK: - Pont SwiftUI pour afficher une image de la plateforme

import SwiftUI

extension Image {
    /// Crée une Image SwiftUI à partir d'une image de la plateforme
    /// (NSImage sur Mac, UIImage sur iPhone). Évite d'écrire des `#if` partout
    /// dans les vues.
    init(imagePlateforme: ImagePlateforme) {
        #if os(macOS)
        self.init(nsImage: imagePlateforme)
        #else
        self.init(uiImage: imagePlateforme)
        #endif
    }
}
