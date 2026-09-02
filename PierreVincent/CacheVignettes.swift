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
/// Drapeau partagé entre le fil principal (qui le pose) et la file de
/// fabrication (qui le lit). Un verrou suffit : la valeur est un simple
/// booléen, touché deux ou trois fois par vignette.
///
/// `@unchecked Sendable` parce que la protection est assurée par le verrou et
/// non par le compilateur.
private final class JetonAbandon: @unchecked Sendable {
    private let verrou = NSLock()
    private var valeur = false

    var abandonne: Bool {
        verrou.lock(); defer { verrou.unlock() }
        return valeur
    }
    func abandonner() { verrou.lock(); valeur = true; verrou.unlock() }
    func reprendre()  { verrou.lock(); valeur = false; verrou.unlock() }
}

@MainActor
final class CacheVignettes {
    static let shared = CacheVignettes()

    // Cache mémoire borné : clé -> vignette déjà préparée.
    // La limite est commune à toutes les variantes : les images anciennes sont
    // évacuées automatiquement, notamment sous pression mémoire, au lieu de
    // rester en mémoire pendant toute la session.
    private let cache: NSCache<NSString, ImagePlateforme> = {
        let cache = NSCache<NSString, ImagePlateforme>()
        cache.countLimit = 48
        return cache
    }()

    /// Demandeurs en attente, par clé. Plusieurs cellules peuvent réclamer la
    /// MÊME vignette : elles sont toutes servies par une seule fabrication.
    ///
    /// **Ce regroupement est indispensable.** Auparavant une demande portant
    /// sur une clé déjà en cours était simplement ignorée, et son rappel
    /// perdu : la deuxième cellule n'était jamais prévenue et restait sur son
    /// icône grise jusqu'à ce qu'on quitte la vue et y revienne.
    private var attentes: [String: [UUID: CheckedContinuation<ImagePlateforme?, Never>]] = [:]

    /// Fabrications lancées, avec leur jeton d'abandon.
    private var enCours: [String: JetonAbandon] = [:]

    private init() {}

    /// Clé de cache.
    ///
    /// Elle inclut **la taille**, et pas seulement le nom et la variante : la
    /// galerie demande 320 pt quand les listes structurées en demandent 240, et
    /// le mode Liste une taille qui suit la hauteur de rangée. Sans la taille,
    /// la première vignette préparée était resservie à toutes les autres — donc
    /// floue si elle avait été fabriquée plus petite.
    ///
    /// La taille est arrondie à un palier de 40 pt pour éviter qu'une hauteur
    /// de rangée réglable ne fabrique une variante par pixel.
    nonisolated private static func cle(nom: String, cote: CGFloat,
                                        preserverRatio: Bool) -> String {
        let palier = max(40, (Int(cote) + 39) / 40 * 40)
        return "\(nom)|\(preserverRatio ? "ratio" : "carre")|\(palier)"
    }

    /// Prépare (ou récupère) une vignette et la renvoie quand elle est prête.
    ///
    /// `cote` = taille cible en points (ex. 76 pour une liste, 320 pour la
    /// galerie). `preserverRatio` = true : garde le ratio d'origine ; false :
    /// recadre en carré centré.
    ///
    /// **`async`, et non un rappel.** L'appelante est un `.task(id:)`, que
    /// SwiftUI annule tout seul quand la cellule disparaît ou change de photo :
    /// l'attente se dénoue alors d'elle-même, et si plus personne n'attend
    /// cette vignette, sa fabrication est abandonnée avant d'occuper la file.
    /// Sans cela, changer de rubrique laissait la file terminer des dizaines de
    /// vignettes devenues invisibles, retardant d'autant celles qu'on regarde.
    func vignette(nom: String, cote: CGFloat,
                  preserverRatio: Bool = false) async -> ImagePlateforme? {
        guard !nom.isEmpty else { return nil }
        let cle = Self.cle(nom: nom, cote: cote, preserverRatio: preserverRatio)
        if let dejaLa = cache.object(forKey: cle as NSString) { return dejaLa }

        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { suite in
                attentes[cle, default: [:]][id] = suite
                lancer(cle: cle, nom: nom, cote: cote, preserverRatio: preserverRatio)
            }
        } onCancel: {
            Task { @MainActor in self.abandonner(cle: cle, id: id) }
        }
    }

    /// Lance la fabrication si elle ne tourne pas déjà pour cette clé.
    private func lancer(cle: String, nom: String, cote: CGFloat, preserverRatio: Bool) {
        // Déjà en cours : cette demande sera servie par la même fabrication.
        // On réarme le jeton au cas où la précédente vague de demandeurs avait
        // tout abandonné — sinon la fabrication serait sautée alors que
        // quelqu'un l'attend de nouveau.
        if let jeton = enCours[cle] {
            jeton.reprendre()
            return
        }

        let jeton = JetonAbandon()
        enCours[cle] = jeton

        let url = PhotoStore.dossierPhotos.appendingPathComponent(nom)
        let cotePixels = cote * 2   // un peu plus fin que l'affichage (Retina)

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
            // Personne n'attend plus cette vignette : on passe au suivant sans
            // rien décoder. Le test est fait ICI, au tour de la demande dans la
            // file, donc une fabrication déjà commencée va jusqu'au bout.
            let vignette: ImagePlateforme? = jeton.abandonne
                ? nil
                : (preserverRatio
                    ? Self.fabriquerVignetteRatio(url: url, coteMaxPixels: cotePixels)
                    : Self.fabriquerVignette(url: url, cotePixels: cotePixels))

            Task { @MainActor in
                self.enCours[cle] = nil
                if let v = vignette { self.cache.setObject(v, forKey: cle as NSString) }

                // Servir TOUS les demandeurs de cette clé, pas seulement le
                // premier : c'est tout l'objet du regroupement.
                let suites = self.attentes.removeValue(forKey: cle) ?? [:]
                for suite in suites.values { suite.resume(returning: vignette) }
            }
        }
    }

    /// Retire un demandeur qui a renoncé (cellule disparue, photo changée).
    /// Une continuation doit être reprise exactement une fois : on la sert donc
    /// avec `nil` au lieu de la laisser en suspens.
    private func abandonner(cle: String, id: UUID) {
        guard let suite = attentes[cle]?.removeValue(forKey: id) else { return }
        suite.resume(returning: nil)
        guard attentes[cle]?.isEmpty ?? false else { return }
        attentes[cle] = nil
        // Plus personne n'attend : la fabrication peut être sautée si elle
        // n'a pas encore démarré.
        enCours[cle]?.abandonner()
    }

    /// File unique de fabrication des vignettes.
    ///
    /// `nonisolated` : elle est touchée depuis le fil principal comme depuis
    /// elle-même, et n'a pas à passer par l'acteur principal.
    ///
    /// **`.utility`, pas `.userInitiated`.** Xcode signalait une inversion de
    /// priorité à la ligne de `CGImageSourceCreateThumbnailAtIndex` : un fil
    /// `.userInitiated` y attendait un fil interne d'ImageIO tournant à une
    /// qualité de service inférieure (« Default »). La fabrication de
    /// vignettes se fait déjà entièrement en arrière-plan (voir
    /// `vignette(nom:cote:)`, `async`) et ne bloque jamais directement un
    /// geste de l'utilisateur : rien ne justifiait la qualité de service
    /// `.userInitiated`, qui ne faisait que promettre au système une urgence
    /// qu'ImageIO ne pouvait pas honorer côté décodage. `.utility` retire
    /// cette promesse en trop, donc l'inversion qu'elle provoquait.
    nonisolated private static let filePreparation = DispatchQueue(
        label: "PierreVincent.vignettes", qos: .utility)

    /// Renvoie une vignette déjà en cache si présente (sans en déclencher).
    func vignettePrete(nom: String, cote: CGFloat,
                       preserverRatio: Bool = false) -> ImagePlateforme? {
        guard !nom.isEmpty else { return nil }
        return cache.object(forKey: Self.cle(nom: nom, cote: cote,
                                             preserverRatio: preserverRatio) as NSString)
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
                if let img = image ?? CacheVignettes.shared.vignettePrete(nom: nom, cote: coteSource, preserverRatio: preserverRatio) {
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
        // `await` et non un rappel : SwiftUI annule cette tâche quand la
        // cellule disparaît, ce qui libère la fabrication devenue inutile.
        .task(id: nom) {
            image = nil
            image = await CacheVignettes.shared.vignette(
                nom: nom, cote: coteSource, preserverRatio: preserverRatio)
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
            if let img = image ?? CacheVignettes.shared.vignettePrete(nom: nom, cote: cote) {
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
            image = await CacheVignettes.shared.vignette(nom: nom, cote: cote)
        }
    }
}
