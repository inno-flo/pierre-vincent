import Foundation
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

    // Cache mémoire : nom de fichier -> vignette déjà préparée.
    private var cache: [String: ImagePlateforme] = [:]
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
        if let dejaLa = cache[cle] { quandPrete(dejaLa); return }
        if enCours.contains(cle) { return }
        enCours.insert(cle)

        let url = PhotoStore.dossierPhotos.appendingPathComponent(nom)
        let cotePixels = cote * 2   // un peu plus fin que l'affichage (écrans Retina)

        Task.detached(priority: .userInitiated) {
            let vignette = preserverRatio
                ? Self.fabriquerVignetteRatio(url: url, coteMaxPixels: cotePixels)
                : Self.fabriquerVignette(url: url, cotePixels: cotePixels)
            await MainActor.run {
                self.enCours.remove(cle)
                if let v = vignette {
                    self.cache[cle] = v
                    quandPrete(v)
                }
            }
        }
    }

    /// Renvoie une vignette déjà en cache si présente (sans en déclencher).
    func vignettePrete(nom: String, preserverRatio: Bool = false) -> ImagePlateforme? {
        cache[preserverRatio ? nom + "|ratio" : nom]
    }

    /// Fabrique une petite image à partir du fichier d'origine.
    /// Multiplateforme (NSImage sur Mac, UIImage sur iPhone).
    nonisolated private static func fabriquerVignette(url: URL, cotePixels: CGFloat)
        -> ImagePlateforme? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        #if os(macOS)
        guard let source = NSImage(data: data) else { return nil }
        // Recadrage CARRÉ au centre de l'image source (évite la déformation).
        let s = source.size
        let cote = min(s.width, s.height)
        let origine = NSRect(x: (s.width - cote) / 2, y: (s.height - cote) / 2,
                             width: cote, height: cote)
        let cible = NSSize(width: cotePixels, height: cotePixels)
        let vignette = NSImage(size: cible)
        vignette.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: cible),
                    from: origine,   // on ne prend que le carré central
                    operation: .copy, fraction: 1.0)
        vignette.unlockFocus()
        return vignette
        #else
        guard let source = UIImage(data: data) else { return nil }
        let s = source.size
        let cote = min(s.width, s.height)
        // Rectangle carré centré, en points de l'image source.
        let origineX = (s.width - cote) / 2
        let origineY = (s.height - cote) / 2
        let cible = CGSize(width: cotePixels, height: cotePixels)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: cible, format: format)
        return renderer.image { _ in
            // On dessine l'image entière mais décalée/agrandie de sorte que seul
            // le carré central tombe dans la zone visible (recadrage centré).
            let echelle = cotePixels / cote
            let dessinRect = CGRect(x: -origineX * echelle,
                                    y: -origineY * echelle,
                                    width: s.width * echelle,
                                    height: s.height * echelle)
            source.draw(in: dessinRect)
        }
        #endif
    }

    /// Fabrique une vignette qui PRÉSERVE le ratio d'origine (pas de crop).
    /// L'image entière est réduite pour tenir dans une boîte de `coteMaxPixels`
    /// (sur son plus grand côté). Utilisée par la galerie.
    nonisolated private static func fabriquerVignetteRatio(url: URL, coteMaxPixels: CGFloat)
        -> ImagePlateforme? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        #if os(macOS)
        guard let source = NSImage(data: data) else { return nil }
        let s = source.size
        guard s.width > 0, s.height > 0 else { return nil }
        // Facteur pour que le plus grand côté atteigne coteMaxPixels.
        let facteur = coteMaxPixels / max(s.width, s.height)
        let cible = NSSize(width: s.width * facteur, height: s.height * facteur)
        let vignette = NSImage(size: cible)
        vignette.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: cible),
                    from: NSRect(origin: .zero, size: s),
                    operation: .copy, fraction: 1.0)
        vignette.unlockFocus()
        return vignette
        #else
        guard let source = UIImage(data: data) else { return nil }
        let s = source.size
        guard s.width > 0, s.height > 0 else { return nil }
        let facteur = coteMaxPixels / max(s.width, s.height)
        let cible = CGSize(width: s.width * facteur, height: s.height * facteur)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: cible, format: format)
        return renderer.image { _ in
            source.draw(in: CGRect(origin: .zero, size: cible))
        }
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
        .onAppear {
            guard image == nil, !nom.isEmpty else { return }
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
        .onAppear {
            guard image == nil, !nom.isEmpty else { return }
            CacheVignettes.shared.demanderVignette(nom: nom, cote: cote) { v in
                image = v
            }
        }
    }
}
