import Foundation
import ImageIO
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Cache de vignettes en mémoire, pour un défilement fluide.
///
/// Problème résolu : afficher directement les images d'origine (lourdes) dans
/// une liste/galerie oblige à les recharger et redécoder depuis le disque à
/// chaque apparition de cellule → saccades. Ici, on prépare UNE fois une petite
/// version (vignette) de chaque image, on la garde en mémoire, et on la
/// réutilise. Le chargement se fait en arrière-plan pour ne pas bloquer l'écran.
@MainActor
final class CacheVignettes {
    static let shared = CacheVignettes()

    // Cache mémoire borné : nom de fichier -> vignette déjà préparée.
    // La limite est commune aux variantes carrée et avec ratio : les images
    // anciennes sont évacuées automatiquement, notamment sous pression
    // mémoire, au lieu de rester en mémoire pendant toute la session.
    private let cache: NSCache<NSString, ImagePlateforme> = {
        let cache = NSCache<NSString, ImagePlateforme>()
        cache.countLimit = 48
        return cache
    }()
    // Noms en cours de chargement, pour éviter de lancer deux fois le même.
    private var enCours: Set<String> = []

    private init() {}

    /// Demande la préparation d'une vignette (en arrière-plan si nécessaire).
    /// `cote` = taille cible en points (ex. 120 pour une liste, 240 pour galerie).
    /// `preserverRatio` = true : garde le ratio d'origine (pas de crop carré) ;
    /// false : recadre en carré centré (pour les listes).
    /// Quand la vignette est prête, `quandPrete` est appelé sur le fil principal.
    func demanderVignette(nom: String, cote: CGFloat,
                          preserverRatio: Bool = false,
                          quandPrete: @escaping (ImagePlateforme) -> Void) {
        guard !nom.isEmpty else { return }
        // Clé distincte selon le mode : un même fichier peut avoir une version
        // carrée (liste) ET une version au ratio d'origine (galerie).
        let cle = preserverRatio ? nom + "|ratio" : nom
        if let dejaLa = cache.object(forKey: cle as NSString) {
            quandPrete(dejaLa)
            return
        }
        if enCours.contains(cle) { return }
        enCours.insert(cle)

        let url = PhotoStore.dossierPhotos.appendingPathComponent(nom)
        let cotePixels = cote * 2   // un peu plus fin que l'affichage (écrans Retina)

        // File SÉRIE dédiée, et non `Task.detached` : en galerie, des dizaines
        // de vignettes sont demandées d'un coup. Autant de tâches détachées
        // saturent le vivier coopératif, et Xcode signale alors un risque de
        // blocage — « priority inversion », un fil de priorité haute attendant
        // un fil de priorité plus basse. Une file sérialisée à une seule
        // qualité de service supprime le mélange.
        //
        // Conséquence voulue : les vignettes se préparent l'une après l'autre,
        // dans l'ordre où elles ont été demandées, donc de haut en bas.
        Self.filePreparation.async {
            let vignette = preserverRatio
                ? Self.fabriquerVignetteRatio(url: url, coteMaxPixels: cotePixels)
                : Self.fabriquerVignette(url: url, cotePixels: cotePixels)
            Task { @MainActor in
                self.enCours.remove(cle)
                if let v = vignette {
                    self.cache.setObject(v, forKey: cle as NSString)
                    quandPrete(v)
                }
            }
        }
    }

    /// File unique de fabrication des vignettes.
    ///
    /// `nonisolated` : elle est touchée depuis le fil principal comme depuis
    /// elle-même, et n'a pas à passer par l'acteur principal.
    nonisolated private static let filePreparation = DispatchQueue(
        label: "PierreVincent.vignettes", qos: .userInitiated)

    /// Renvoie une vignette déjà en cache si présente (sans en déclencher).
    func vignettePrete(nom: String, preserverRatio: Bool = false) -> ImagePlateforme? {
        let cle = preserverRatio ? nom + "|ratio" : nom
        return cache.object(forKey: cle as NSString)
    }

    /// Fabrique une petite image à partir du fichier d'origine.
    /// ImageIO réduit l'image directement pendant le décodage : l'image
    /// pleine taille n'est donc jamais chargée en mémoire pour fabriquer une
    /// vignette.
    nonisolated private static func fabriquerVignette(url: URL, cotePixels: CGFloat)
        -> ImagePlateforme? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        // Pour obtenir un carré de la taille demandée après le recadrage,
        // ImageIO doit conserver assez de pixels sur le plus grand côté.
        let coteMax = coteMaximalePourCarre(source: source, cotePixels: cotePixels)
        guard let imageReduite = imageReduite(source: source, coteMaximale: coteMax) else {
            return nil
        }

        let cote = min(imageReduite.width, imageReduite.height)
        guard cote > 0 else { return nil }
        let origine = CGRect(x: (imageReduite.width - cote) / 2,
                             y: (imageReduite.height - cote) / 2,
                             width: cote,
                             height: cote)
        guard let imageCarree = imageReduite.cropping(to: origine) else { return nil }
        return imagePlateforme(depuis: imageCarree)
    }

    /// Fabrique une vignette qui PRÉSERVE le ratio d'origine (pas de crop).
    /// L'image entière est réduite pour tenir dans une boîte de `coteMaxPixels`
    /// (sur son plus grand côté). Utilisée par la galerie.
    nonisolated private static func fabriquerVignetteRatio(url: URL, coteMaxPixels: CGFloat)
        -> ImagePlateforme? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let imageReduite = imageReduite(source: source,
                                              coteMaximale: coteMaxPixels) else {
            return nil
        }
        return imagePlateforme(depuis: imageReduite)
    }

    /// Renvoie la taille de décodage nécessaire pour recadrer ensuite un carré.
    nonisolated private static func coteMaximalePourCarre(source: CGImageSource,
                                                          cotePixels: CGFloat) -> CGFloat {
        guard let proprietes = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let largeur = (proprietes[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let hauteur = (proprietes[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              largeur > 0,
              hauteur > 0 else {
            return cotePixels
        }

        let plusGrandCote = max(largeur, hauteur)
        let plusPetitCote = min(largeur, hauteur)
        return cotePixels * CGFloat(plusGrandCote / plusPetitCote)
    }

    /// Décode directement une image réduite à la taille maximale demandée.
    /// `WithTransform` applique l'orientation EXIF avant le recadrage ou le
    /// rendu dans SwiftUI.
    nonisolated private static func imageReduite(source: CGImageSource,
                                                 coteMaximale: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(ceil(coteMaximale)))
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Convertit l'image ImageIO vers le type natif de la plateforme.
    nonisolated private static func imagePlateforme(depuis image: CGImage)
        -> ImagePlateforme {
        #if os(macOS)
        NSImage(cgImage: image,
                size: NSSize(width: image.width, height: image.height))
        #else
        UIImage(cgImage: image)
        #endif
    }
}

/// Variante de vignette cachée qui REMPLIT l'espace disponible (pour la galerie,
/// où la largeur dépend de la colonne). On prépare une vignette de `coteSource`
/// points, puis on l'étire pour remplir le cadre parent.
struct VignetteCacheeFlexible: View {
    let nom: String
    let coteSource: CGFloat        // taille de la vignette préparée (qualité)
    var preserverRatio: Bool = false   // true : garde le ratio (galerie)

    @State private var image: ImagePlateforme?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let img = image ?? CacheVignettes.shared.vignettePrete(nom: nom, preserverRatio: preserverRatio) {
                    Image(imagePlateforme: img)
                        .resizable()
                        .scaledToFill()
                        // Contrainte EXACTE à la taille du cadre : sans ça, une
                        // image paysage déborde en largeur et chevauche les cartes
                        // voisines.
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 40)).foregroundStyle(.tertiary)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        // Même correctif que sur `VignetteCachee` : recharger quand le nom de
        // fichier change alors que la vue est déjà à l'écran.
        .task(id: nom) {
            image = nil
            guard !nom.isEmpty else { return }
            CacheVignettes.shared.demanderVignette(nom: nom, cote: coteSource,
                                                   preserverRatio: preserverRatio) { v in
                image = v
            }
        }
    }
}

/// Vue d'affichage d'une vignette avec cache : montre un fond neutre tant que
/// la vignette n'est pas prête, puis l'image légère. Évite les saccades.
struct VignetteCachee: View {
    let nom: String
    let cote: CGFloat
    var coinsArrondis: CGFloat = 6

    @State private var image: ImagePlateforme?

    var body: some View {
        Group {
            if let img = image ?? CacheVignettes.shared.vignettePrete(nom: nom) {
                Image(imagePlateforme: img).resizable().scaledToFill()
                    .frame(width: cote, height: cote)
                    .clipped()
                    .cornerRadius(coinsArrondis)
            } else {
                RoundedRectangle(cornerRadius: coinsArrondis)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: cote, height: cote)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary))
            }
        }
        // `.task(id: nom)` et NON `.onAppear` : la vue doit recharger quand le
        // nom de fichier change alors qu'elle est DÉJÀ à l'écran — remplacement
        // d'une photo depuis l'éditeur ou par glisser-déposer. Avec onAppear,
        // rien ne se redéclenchait et l'ancienne vignette restait affichée
        // jusqu'à ce qu'on quitte la vue et y revienne.
        .task(id: nom) {
            image = nil
            guard !nom.isEmpty else { return }
            CacheVignettes.shared.demanderVignette(nom: nom, cote: cote) { v in
                image = v
            }
        }
    }
}
