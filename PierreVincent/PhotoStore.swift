import Foundation
import ImageIO
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

    /// Enregistre des DONNÉES image brutes (déjà encodées : png, jpeg…) sans
    /// les décoder ni les réencoder. Beaucoup plus rapide et léger que de passer
    /// par une image en mémoire — utile à l'import massif depuis un fichier.
    static func enregistrerDonnees(_ data: Data, extension ext: String) -> String? {
        let e = ext.isEmpty ? "png" : ext
        let nom = UUID().uuidString + "." + e
        let dest = dossierPhotos.appendingPathComponent(nom)
        do {
            try data.write(to: dest)
            return nom
        } catch {
            return nil
        }
    }

    /// Charge une image à partir de son nom de fichier stocké.
    static func chargerImage(nom: String) -> ImagePlateforme? {
        guard !nom.isEmpty else { return nil }
        #if os(iOS)
        // Déjà préparée par `prechargerImage` : on évite lecture et décodage.
        if let prete = cacheImages.object(forKey: nom as NSString) { return prete }
        #endif
        let url = dossierPhotos.appendingPathComponent(nom)
        #if os(macOS)
        return NSImage(contentsOf: url)
        #else
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
        #endif
    }

    #if os(iOS)
    /// Petit cache d'images PRÊTES À AFFICHER, pour la visionneuse.
    ///
    /// Volontairement minuscule : ces images sont décompressées en mémoire, et
    /// la base en compte des centaines. On ne garde que les dernières vues.
    private static let cacheImages: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 6
        return cache
    }()

    /// Charge et **décode** une image en tâche de fond, pour qu'elle soit prête
    /// quand on l'affichera.
    ///
    /// Appelée dès que le doigt se pose sur une vignette, avant même que
    /// l'appui prolongé n'aboutisse : sans cela, la lecture du fichier et le
    /// décodage tombent en plein milieu de l'animation d'ouverture et la font
    /// saccader — à la PREMIÈRE ouverture seulement, le système gardant
    /// ensuite le fichier en cache.
    ///
    /// `byPreparingForDisplay` fait le décodage tout de suite. Sans lui,
    /// `UIImage` le diffère jusqu'au premier tracé, c'est-à-dire jusqu'au pire
    /// moment.
    static func prechargerImage(nom: String) {
        guard !nom.isEmpty, cacheImages.object(forKey: nom as NSString) == nil else { return }
        let url = dossierPhotos.appendingPathComponent(nom)
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else { return }
            let prete = image.preparingForDisplay() ?? image
            cacheImages.setObject(prete, forKey: nom as NSString)
        }
    }
    #endif

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

    // MARK: Compression

    /// Poids maximal d'une photo importée, en octets.
    static let poidsMaxImport = 450 * 1024

    /// Côté long maximal après réduction. 2000 px reste confortable pour un
    /// affichage plein écran sur Mac comme sur iPhone, tout en divisant par
    /// quatre le nombre de pixels d'une photo d'iPhone (4032 px).
    static let coteMaxImport = 2000

    /// Importe une image en la RÉDUISANT et la COMPRESSANT sous `poidsMaxImport`.
    /// Renvoie le nom du fichier créé, ou nil en cas d'échec.
    ///
    /// Deux leviers, dans cet ordre : on réduit d'abord la définition, puis on
    /// baisse la qualité par paliers jusqu'à passer sous le seuil. Compresser
    /// sans réduire donnerait une image molle — à 450 Ko, 12 Mpx font environ
    /// 0,03 bit par pixel.
    ///
    /// Sortie en HEIC : à définition égale il permet une qualité nettement plus
    /// élevée que le JPEG pour le même poids, et l'app est 100 % Apple.
    static func importerImageCompressee(depuis url: URL) -> String? {
        // Fichier déjà sous le seuil : on le recopie TEL QUEL, octet pour
        // octet. Le ré-encoder ne ferait que dégrader l'image — et, en PNG,
        // l'alourdir considérablement — sans rien gagner en poids.
        if let donnees = try? Data(contentsOf: url), donnees.count <= poidsMaxImport {
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
            return enregistrerDonnees(donnees, extension: ext)
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        // Réduction : `CGImageSourceCreateThumbnailAtIndex` décode directement
        // à la taille voulue, sans jamais charger l'image entière en mémoire.
        let optionsReduction: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // respecte l'orientation EXIF
            kCGImageSourceThumbnailMaxPixelSize: coteMaxImport
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0, optionsReduction as CFDictionary) else { return nil }

        // Qualité dégressive : on s'arrête dès qu'on passe sous le seuil, pour
        // ne pas dégrader inutilement une photo qui y tient facilement.
        for pas in stride(from: 90, through: 20, by: -5) {
            let qualite = CGFloat(pas) / 100
            guard let donnees = encoder(image, qualite: qualite) else { continue }
            if donnees.count <= poidsMaxImport {
                return enregistrerDonnees(donnees, extension: "heic")
            }
        }
        // Dernier recours : on garde la qualité minimale même si le seuil est
        // dépassé, plutôt que de perdre la photo.
        if let donnees = encoder(image, qualite: 0.20) {
            return enregistrerDonnees(donnees, extension: "heic")
        }
        return nil
    }

    /// Encode une image en HEIC à la qualité demandée.
    private static func encoder(_ image: CGImage, qualite: CGFloat) -> Data? {
        let donnees = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
                donnees, UTType.heic.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(
            dest, image,
            [kCGImageDestinationLossyCompressionQuality: qualite] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return donnees as Data
    }

    /// Décrit la photo stockée : poids, définition, puis nom du fichier.
    /// Sert au champ « Image » de l'inspecteur et de l'éditeur, et permet de
    /// vérifier d'un coup d'œil que la compression a tenu ses 450 Ko.
    static func infosImage(nom: String) -> String {
        guard !nom.isEmpty,
              let url = urlPhoto(nom: nom),
              let attributs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let octets = attributs[.size] as? Int else { return "Aucune photo" }

        let formateur = ByteCountFormatter()
        formateur.countStyle = .file
        var texte = formateur.string(fromByteCount: Int64(octets))

        // Définition lue dans l'en-tête, sans décoder l'image.
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let largeur = props[kCGImagePropertyPixelWidth] as? Int,
           let hauteur = props[kCGImagePropertyPixelHeight] as? Int {
            texte += " · \(largeur) × \(hauteur) px"
        }
        return texte + "\n" + nom
    }

    /// Mots-clés IPTC d'un fichier image (vide si absents).
    /// C'est là que Photos range les étiquettes saisies par l'utilisateur.
    static func motsCles(de url: URL) -> [String] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any],
              let mots = iptc[kCGImagePropertyIPTCKeywords] as? [String] else { return [] }
        return mots
    }

    /// Légende IPTC d'un fichier image (vide si absente).
    static func legende(de url: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any],
              let texte = iptc[kCGImagePropertyIPTCCaptionAbstract] as? String else { return "" }
        return texte
    }

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
