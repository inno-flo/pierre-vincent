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

    /// Renvoie la vignette déjà en cache, ou nil si pas encore prête.
    func vignettePrete(nom: String) -> ImagePlateforme? {
        cache[nom]
    }

    /// Demande la préparation d'une vignette (en arrière-plan si nécessaire).
    /// `cote` = taille cible en points (ex. 120 pour une liste, 240 pour galerie).
    /// Quand la vignette est prête, `quandPrete` est appelé sur le fil principal.
    func demanderVignette(nom: String, cote: CGFloat,
                          quandPrete: @escaping (ImagePlateforme) -> Void) {
        guard !nom.isEmpty else { return }
        if let dejaLa = cache[nom] { quandPrete(dejaLa); return }
        if enCours.contains(nom) { return }   // déjà en préparation
        enCours.insert(nom)

        let url = PhotoStore.dossierPhotos.appendingPathComponent(nom)
        let cotePixels = cote * 2   // un peu plus fin que l'affichage (écrans Retina)

        // Chargement + redimensionnement hors du fil principal.
        Task.detached(priority: .userInitiated) {
            let vignette = Self.fabriquerVignette(url: url, cotePixels: cotePixels)
            await MainActor.run {
                self.enCours.remove(nom)
                if let v = vignette {
                    self.cache[nom] = v
                    quandPrete(v)
                }
            }
        }
    }

    /// Fabrique une petite image à partir du fichier d'origine.
    /// Multiplateforme (NSImage sur Mac, UIImage sur iPhone).
    nonisolated private static func fabriquerVignette(url: URL, cotePixels: CGFloat)
        -> ImagePlateforme? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        #if os(macOS)
        guard let source = NSImage(data: data) else { return nil }
        let cible = NSSize(width: cotePixels, height: cotePixels)
        let vignette = NSImage(size: cible)
        vignette.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: cible),
                    from: NSRect(origin: .zero, size: source.size),
                    operation: .copy, fraction: 1.0)
        vignette.unlockFocus()
        return vignette
        #else
        guard let source = UIImage(data: data) else { return nil }
        let cible = CGSize(width: cotePixels, height: cotePixels)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1   // on gère nous-mêmes la densité via cotePixels
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

    @State private var image: ImagePlateforme?

    var body: some View {
        Group {
            if let img = image ?? CacheVignettes.shared.vignettePrete(nom: nom) {
                Image(imagePlateforme: img).resizable().scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 40)).foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            guard image == nil, !nom.isEmpty else { return }
            CacheVignettes.shared.demanderVignette(nom: nom, cote: coteSource) { v in
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
