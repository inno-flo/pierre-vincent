import Foundation
import CoreGraphics
import ImageIO
import Vision
import Accelerate

/// Signature visuelle d'une photo : ce qui permet de rapprocher deux œuvres
/// sur leur STYLE et leurs COULEURS, sans rien savoir de leur genre.
///
/// **Trois descripteurs, et non un seul.** L'empreinte de Vision
/// (`GenerateImageFeaturePrintRequest`) sait très bien dire « ces deux images
/// se ressemblent », mais elle a été entraînée à reconnaître des SUJETS : deux
/// natures mortes lui paraissent proches même quand l'une est un lavis gris et
/// l'autre une huile éclatante. C'est exactement l'inverse de ce qu'on
/// cherche. On lui adjoint donc deux descripteurs calculés ici même, tous deux
/// aveugles au sujet :
///
/// - un **histogramme de couleurs** en espace Lab, qui dit la gamme
///   chromatique — et rien d'autre ;
/// - trois **mesures de matière** (contraste, contours, granularité), qui
///   disent la facture : un crayon fin et une huile empâtée ne s'y confondent
///   pas, quel que soit ce qu'ils représentent.
///
/// Le poids relatif de la couleur et du style est réglé à l'écran par un
/// curseur — voir `DistanceSignature.totale(_:_:poidsCouleur:)`.
///
/// Tout est calculé **en local**, avec les seuls frameworks Apple (Vision,
/// ImageIO, Accelerate). Aucune bibliothèque tierce, aucun accès réseau.
struct SignatureOeuvre: Codable, Sendable {

    /// Version du descripteur. Toute modification de la façon de calculer
    /// l'un des champs ci-dessous doit l'incrémenter : les signatures d'une
    /// version antérieure sont alors ignorées au chargement et recalculées.
    /// Sans ce numéro, une base mêlerait deux façons de mesurer, et les
    /// distances entre elles n'auraient aucun sens.
    static let versionCourante = 1

    var version: Int

    // MARK: Couleur

    /// Histogramme des couleurs en espace **Lab**, `binsL * binsA * binsB`
    /// cases, de somme 1.
    ///
    /// Lab et non RVB : c'est un espace **perceptuel**, où une même distance
    /// numérique correspond à peu près au même écart vu à l'œil. Deux verts
    /// voisins en RVB peuvent sembler très différents, et l'inverse est vrai
    /// aussi — un histogramme RVB rapprocherait donc des œuvres qui ne se
    /// ressemblent pas.
    var histogramme: [Float]

    /// Cinq teintes dominantes, pour l'AFFICHAGE seulement (la pastille de
    /// couleurs montrée en tête de chaque famille). La distance, elle, se
    /// calcule sur l'histogramme, bien plus fin.
    var palette: [TeinteDominante]

    /// Clarté moyenne (L*, de 0 = noir à 100 = blanc).
    var clarte: Float
    /// Saturation perçue moyenne (chroma = √(a²+b²)) : 0 = gris, > 40 = vif.
    var chroma: Float
    /// Tiédeur : b* moyen. Positif = dominante chaude (jaune, ocre),
    /// négatif = dominante froide (bleu).
    var tiedeur: Float

    // MARK: Matière

    /// Écart-type de la clarté, ramené à 0…1. Un lavis délavé est bas, un
    /// fusain très contrasté est haut.
    var contraste: Float
    /// Densité de contours (gradient de Sobel moyen), ramenée à 0…1.
    /// Distingue un trait net d'un modelé fondu.
    var contours: Float
    /// Part de haute fréquence — l'écart entre l'image et sa version floutée,
    /// ramené à 0…1. C'est le « grain » : touche visible, grain du papier.
    var granularite: Float

    // MARK: Empreinte Vision

    /// Le vecteur produit par Vision, en Float32 bruts et **déjà normalisé**
    /// à une longueur de 1.
    ///
    /// Stocké en `Data` et non en `[Float]` : écrit en clair dans le JSON, le
    /// tableau prendrait une dizaine de kilo-octets par œuvre. En octets
    /// bruts, il en prend trois.
    ///
    /// **Longueur mesurée : 768 nombres** (révision courante de Vision, macOS
    /// 26). Elle n'est écrite nulle part dans le code — tout ce qui la
    /// concerne se lit sur le tableau lui-même : une révision future qui
    /// changerait cette taille ne casserait donc rien, et les signatures
    /// existantes seraient de toute façon écartées par `versionCourante`.
    var empreinteBrute: Data

    /// Le vecteur relu depuis `empreinteBrute`.
    var empreinte: [Float] {
        empreinteBrute.withUnsafeBytes { octets in
            Array(octets.bindMemory(to: Float.self))
        }
    }
}

/// Une des teintes dominantes d'une œuvre, telle qu'elle sera affichée.
struct TeinteDominante: Codable, Sendable {
    /// Composantes sRGB, de 0 à 1.
    var r: Float
    var v: Float
    var b: Float
    /// Part de l'image occupée par cette teinte, de 0 à 1.
    var poids: Float
}

// MARK: - Découpage de l'histogramme

/// Nombre de cases de l'histogramme sur chaque axe de l'espace Lab.
///
/// Volontairement grossier sur L (4 cases) et plus fin sur a et b (6 chacun) :
/// c'est la TEINTE qui distingue deux gammes de couleurs, la clarté étant déjà
/// portée à part par `clarte` et `contraste`.
enum DecoupageLab {
    static let binsL = 4
    static let binsA = 6
    static let binsB = 6
    static var total: Int { binsL * binsA * binsB }

    /// Bornes des axes a* et b*. Au-delà, les valeurs sont ramenées au bord :
    /// les couleurs réellement présentes dans des photos d'œuvres dépassent
    /// rarement ±60.
    static let borneAB: Float = 70
}

// MARK: - Calcul de la signature

enum CalculSignature {

    /// Côté de l'image donnée à Vision. L'empreinte n'a pas besoin de plus,
    /// et ImageIO décode directement à cette taille — l'image pleine (2000 px)
    /// n'est jamais chargée en mémoire.
    static let coteVision = 320

    /// Côté de la grille sur laquelle sont mesurés couleurs et matière.
    /// 96×96 = 9216 points, largement assez pour une statistique de teinte,
    /// et assez petit pour que les boucles ci-dessous soient instantanées.
    static let coteAnalyse = 96

    /// Calcule la signature d'un fichier photo. `nil` si l'image est illisible
    /// ou si Vision échoue.
    ///
    /// **Appelée hors du fil principal.** Elle décode, mesure et interroge
    /// Vision : rien de tout cela n'a sa place sur `MainActor`.
    static func signature(pour url: URL) async -> SignatureOeuvre? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = imageReduite(source: source, cote: coteVision)
        else { return nil }

        // 1. L'empreinte Vision. En premier : c'est la seule étape qui peut
        //    échouer pour une raison autre qu'un fichier illisible.
        guard let empreinte = await empreinteVision(image) else { return nil }

        // 2. Couleurs et matière, sur une grille réduite tirée de la MÊME
        //    image déjà décodée — pas de second décodage.
        guard let pixels = grilleRVB(image, cote: coteAnalyse) else { return nil }
        let mesures = mesurer(pixels: pixels, cote: coteAnalyse)

        return SignatureOeuvre(
            version: SignatureOeuvre.versionCourante,
            histogramme: mesures.histogramme,
            palette: mesures.palette,
            clarte: mesures.clarte,
            chroma: mesures.chroma,
            tiedeur: mesures.tiedeur,
            contraste: mesures.contraste,
            contours: mesures.contours,
            granularite: mesures.granularite,
            empreinteBrute: empreinte)
    }

    // MARK: Étape 1 — Vision

    /// Interroge Vision et rend le vecteur normalisé, en octets bruts.
    ///
    /// **Normalisé à une longueur de 1** : la distance euclidienne entre deux
    /// vecteurs unitaires est alors bornée (entre 0 et 2), ce qui permet de la
    /// combiner avec les deux autres descripteurs, eux aussi bornés. Sans
    /// cette mise à l'échelle, l'empreinte écraserait les deux autres ou
    /// disparaîtrait devant eux, selon les images.
    private static func empreinteVision(_ image: CGImage) async -> Data? {
        let requete = GenerateImageFeaturePrintRequest()
        guard let observation = try? await requete.perform(on: image) else { return nil }

        // Vision annonce lui-même le type de ses éléments : `float` aujourd'hui,
        // `double` sur une révision future. On lit ce qu'il dit plutôt que de
        // supposer, sinon le vecteur serait relu de travers sans le moindre
        // message d'erreur.
        var valeurs: [Float]
        switch observation.elementType {
        case .float:
            valeurs = observation.data.withUnsafeBytes { octets in
                Array(octets.bindMemory(to: Float.self))
            }
        case .double:
            valeurs = observation.data.withUnsafeBytes { octets in
                octets.bindMemory(to: Double.self).map { Float($0) }
            }
        @unknown default:
            return nil
        }
        guard !valeurs.isEmpty else { return nil }

        let norme = sqrt(vDSP.sum(vDSP.multiply(valeurs, valeurs)))
        guard norme > 0 else { return nil }
        valeurs = vDSP.divide(valeurs, norme)

        return valeurs.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    // MARK: Étape 2 — couleurs et matière

    /// Résultat brut des mesures faites sur la grille de pixels.
    private struct Mesures {
        var histogramme: [Float]
        var palette: [TeinteDominante]
        var clarte: Float
        var chroma: Float
        var tiedeur: Float
        var contraste: Float
        var contours: Float
        var granularite: Float
    }

    /// Mesure tout ce qui ne vient pas de Vision, en un seul balayage.
    private static func mesurer(pixels: [UInt8], cote: Int) -> Mesures {
        let nb = cote * cote
        var histogramme = [Float](repeating: 0, count: DecoupageLab.total)
        // Les valeurs Lab de chaque point, gardées pour la palette ; et la
        // clarté seule, gardée pour les mesures de matière.
        var labs = [SIMD3<Float>](repeating: .zero, count: nb)
        var clartes = [Float](repeating: 0, count: nb)
        var sommeL: Float = 0, sommeChroma: Float = 0, sommeB: Float = 0

        for i in 0..<nb {
            let r = Float(pixels[i * 4]) / 255
            let v = Float(pixels[i * 4 + 1]) / 255
            let b = Float(pixels[i * 4 + 2]) / 255
            let lab = versLab(r: r, v: v, b: b)

            labs[i] = lab
            clartes[i] = lab.x
            sommeL += lab.x
            sommeChroma += sqrt(lab.y * lab.y + lab.z * lab.z)
            sommeB += lab.z
            ajouter(lab, a: &histogramme)
        }

        // Somme ramenée à 1 : deux images de tailles différentes deviennent
        // comparables (ici elles ont la même, mais la propriété doit tenir
        // pour que la distance de Hellinger garde son sens).
        let total = Float(nb)
        for i in histogramme.indices { histogramme[i] /= total }

        let matiere = mesurerMatiere(clartes: clartes, cote: cote)

        return Mesures(
            histogramme: histogramme,
            palette: palette(labs: labs, pixels: pixels, histogramme: histogramme),
            clarte: sommeL / total,
            chroma: sommeChroma / total,
            tiedeur: sommeB / total,
            contraste: matiere.contraste,
            contours: matiere.contours,
            granularite: matiere.granularite)
    }

    /// Ajoute un point à l'histogramme en répartissant son poids sur les cases
    /// VOISINES, au prorata de sa position dans sa case.
    ///
    /// **Sans cette répartition, l'histogramme serait inexploitable.** Deux
    /// beiges à peine distincts peuvent tomber de part et d'autre d'une
    /// frontière de case : comptés en dur, ils n'auraient alors plus AUCUNE
    /// case en commun, et la distance entre les deux œuvres serait maximale
    /// alors qu'elles se ressemblent. En répartissant, un point proche d'une
    /// frontière alimente les deux cases, et l'écart mesuré redevient continu.
    private static func ajouter(_ lab: SIMD3<Float>, a histogramme: inout [Float]) {
        let (i0, i1, fi) = repartition(lab.x, min: 0, max: 100, bins: DecoupageLab.binsL)
        let (j0, j1, fj) = repartition(lab.y, min: -DecoupageLab.borneAB,
                                       max: DecoupageLab.borneAB, bins: DecoupageLab.binsA)
        let (k0, k1, fk) = repartition(lab.z, min: -DecoupageLab.borneAB,
                                       max: DecoupageLab.borneAB, bins: DecoupageLab.binsB)

        let nA = DecoupageLab.binsA, nB = DecoupageLab.binsB
        // Les huit sommets du cube entourant le point.
        for (i, pi) in [(i0, 1 - fi), (i1, fi)] where pi > 0 {
            for (j, pj) in [(j0, 1 - fj), (j1, fj)] where pj > 0 {
                for (k, pk) in [(k0, 1 - fk), (k1, fk)] where pk > 0 {
                    histogramme[(i * nA + j) * nB + k] += pi * pj * pk
                }
            }
        }
    }

    /// Les deux cases voisines d'une valeur et la part revenant à la seconde.
    private static func repartition(_ valeur: Float, min borneMin: Float,
                                    max borneMax: Float, bins: Int)
        -> (Int, Int, Float) {
        let normalisee = (valeur - borneMin) / (borneMax - borneMin)
        let position = Swift.min(Swift.max(normalisee, 0), 1) * Float(bins) - 0.5
        let bas = Int(floor(position))
        let fraction = position - Float(bas)
        let i0 = Swift.min(Swift.max(bas, 0), bins - 1)
        let i1 = Swift.min(Swift.max(bas + 1, 0), bins - 1)
        return (i0, i1, fraction < 0 ? 0 : (fraction > 1 ? 1 : fraction))
    }

    // MARK: Matière

    private struct Matiere {
        var contraste: Float
        var contours: Float
        var granularite: Float
    }

    /// Les trois mesures de facture, toutes calculées sur la seule CLARTÉ.
    ///
    /// La couleur en est délibérément absente : c'est ce qui les rend aveugles
    /// au sujet comme à la gamme chromatique. Deux œuvres de couleurs
    /// opposées mais de même facture s'y retrouvent proches, et c'est le but.
    ///
    /// Les trois diviseurs sont des échelles **empiriques** : ils n'ont pas
    /// d'autre rôle que de ramener les trois nombres dans un même ordre de
    /// grandeur (0…1), pour qu'aucun n'écrase les deux autres dans la
    /// distance. Les changer change les regroupements — pas leur validité.
    private static func mesurerMatiere(clartes: [Float], cote: Int) -> Matiere {
        let nb = clartes.count
        let moyenne = vDSP.sum(clartes) / Float(nb)

        // Contraste : l'écart-type de la clarté.
        let ecarts = vDSP.add(-moyenne, clartes)
        let variance = vDSP.sum(vDSP.multiply(ecarts, ecarts)) / Float(nb)
        let contraste = Swift.min(sqrt(variance) / 50, 1)

        // Contours : gradient de Sobel, moyenné sur l'intérieur de l'image.
        var sommeGradient: Float = 0
        var sommeGrain: Float = 0
        var comptes = 0
        for y in 1..<(cote - 1) {
            for x in 1..<(cote - 1) {
                let i = y * cote + x
                let hg = clartes[i - cote - 1], h = clartes[i - cote], hd = clartes[i - cote + 1]
                let g = clartes[i - 1],        c = clartes[i],        d = clartes[i + 1]
                let bg = clartes[i + cote - 1], b = clartes[i + cote], bd = clartes[i + cote + 1]

                let gx = (hd + 2 * d + bd) - (hg + 2 * g + bg)
                let gy = (bg + 2 * b + bd) - (hg + 2 * h + hd)
                sommeGradient += sqrt(gx * gx + gy * gy)

                // Granularité : l'écart au voisinage moyen (flou 3×3). Ce qui
                // reste, c'est la haute fréquence — le grain, la touche.
                let flou = (hg + h + hd + g + c + d + bg + b + bd) / 9
                sommeGrain += abs(c - flou)
                comptes += 1
            }
        }
        let n = Float(Swift.max(comptes, 1))
        let contours = Swift.min((sommeGradient / n) / 60, 1)
        let granularite = Swift.min((sommeGrain / n) / 8, 1)

        return Matiere(contraste: contraste, contours: contours, granularite: granularite)
    }

    // MARK: Palette

    /// Cinq teintes dominantes, par k-moyennes en espace Lab.
    ///
    /// **Départ DÉTERMINISTE** : les centres de départ sont les cinq cases les mieux
    /// remplies de l'histogramme, et non un tirage au hasard. Deux analyses
    /// de la même photo donnent donc exactement la même palette — sans quoi
    /// relancer l'analyse changerait les couleurs affichées sans raison
    /// visible.
    private static func palette(labs: [SIMD3<Float>], pixels: [UInt8],
                                histogramme: [Float]) -> [TeinteDominante] {
        let k = 5
        var centres = casesLesPlusRemplies(histogramme, k: k)
        guard !centres.isEmpty else { return [] }

        var appartenance = [Int](repeating: 0, count: labs.count)
        for _ in 0..<12 {
            var bouge = false
            for (i, lab) in labs.enumerated() {
                var meilleur = 0
                var meilleureDistance = Float.greatestFiniteMagnitude
                for (c, centre) in centres.enumerated() {
                    let d = distance2(lab, centre)
                    if d < meilleureDistance { meilleureDistance = d; meilleur = c }
                }
                if appartenance[i] != meilleur { appartenance[i] = meilleur; bouge = true }
            }
            // Nouveaux centres = moyenne des points de chaque groupe.
            var sommes = [SIMD3<Float>](repeating: .zero, count: centres.count)
            var effectifs = [Int](repeating: 0, count: centres.count)
            for (i, lab) in labs.enumerated() {
                sommes[appartenance[i]] += lab
                effectifs[appartenance[i]] += 1
            }
            for c in centres.indices where effectifs[c] > 0 {
                centres[c] = sommes[c] / Float(effectifs[c])
            }
            if !bouge { break }
        }

        // La couleur AFFICHÉE est la moyenne des pixels d'origine du groupe,
        // en sRGB — pas la reconversion du centre Lab, qui demanderait une
        // transformation inverse dont on n'a pas besoin ici.
        var sommesRVB = [SIMD3<Float>](repeating: .zero, count: centres.count)
        var effectifs = [Int](repeating: 0, count: centres.count)
        for i in labs.indices {
            let c = appartenance[i]
            sommesRVB[c] += SIMD3<Float>(Float(pixels[i * 4]), Float(pixels[i * 4 + 1]),
                                         Float(pixels[i * 4 + 2]))
            effectifs[c] += 1
        }

        let total = Float(labs.count)
        var teintes: [TeinteDominante] = []
        for c in centres.indices where effectifs[c] > 0 {
            let moyenne = sommesRVB[c] / Float(effectifs[c]) / 255
            teintes.append(TeinteDominante(r: moyenne.x, v: moyenne.y, b: moyenne.z,
                                           poids: Float(effectifs[c]) / total))
        }
        return teintes.sorted { $0.poids > $1.poids }
    }

    /// Les `k` cases les mieux remplies de l'histogramme, rendues sous forme
    /// de coordonnées Lab (le centre de chaque case).
    private static func casesLesPlusRemplies(_ histogramme: [Float], k: Int)
        -> [SIMD3<Float>] {
        let meilleures = histogramme.enumerated()
            .filter { $0.element > 0 }
            .sorted { $0.element > $1.element }
            .prefix(k)

        let nA = DecoupageLab.binsA, nB = DecoupageLab.binsB
        return meilleures.map { (index, _) in
            let k3 = index % nB
            let j = (index / nB) % nA
            let i = index / (nB * nA)
            let l = (Float(i) + 0.5) / Float(DecoupageLab.binsL) * 100
            let a = (Float(j) + 0.5) / Float(nA) * 2 * DecoupageLab.borneAB - DecoupageLab.borneAB
            let b = (Float(k3) + 0.5) / Float(nB) * 2 * DecoupageLab.borneAB - DecoupageLab.borneAB
            return SIMD3<Float>(l, a, b)
        }
    }

    private static func distance2(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b
        return d.x * d.x + d.y * d.y + d.z * d.z
    }

    // MARK: Conversions et décodage

    /// sRGB (0…1) vers Lab (D65).
    ///
    /// Deux étapes : on annule d'abord la correction gamma de sRGB (les
    /// valeurs d'un fichier image ne sont pas proportionnelles à la lumière),
    /// puis on passe par l'espace XYZ, seul chemin vers Lab.
    private static func versLab(r: Float, v: Float, b: Float) -> SIMD3<Float> {
        func lineaire(_ c: Float) -> Float {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let rl = lineaire(r), vl = lineaire(v), bl = lineaire(b)

        let x = (0.4124 * rl + 0.3576 * vl + 0.1805 * bl) / 0.95047
        let y = (0.2126 * rl + 0.7152 * vl + 0.0722 * bl)
        let z = (0.0193 * rl + 0.1192 * vl + 0.9505 * bl) / 1.08883

        func f(_ t: Float) -> Float {
            t > 0.008856 ? cbrt(t) : (7.787 * t + 16.0 / 116.0)
        }
        let fx = f(x), fy = f(y), fz = f(z)
        return SIMD3<Float>(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// Décode directement une image réduite, sans jamais charger la pleine
    /// taille en mémoire — même technique que `CacheVignettes`.
    /// `WithTransform` applique l'orientation EXIF.
    private static func imageReduite(source: CGImageSource, cote: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: cote
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Redessine l'image dans une grille carrée de `cote`×`cote` en sRGB, et
    /// rend les octets RVBA.
    ///
    /// Le carré DÉFORME l'image (le ratio n'est pas conservé) : c'est sans
    /// conséquence ici, puisqu'on ne mesure que des statistiques de couleur et
    /// de texture, jamais des formes. Un recadrage perdrait au contraire les
    /// bords, souvent porteurs du fond et donc de la gamme.
    private static func grilleRVB(_ image: CGImage, cote: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: cote * cote * 4)
        guard let espace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let succes: Bool = pixels.withUnsafeMutableBytes { tampon -> Bool in
            guard let base = tampon.baseAddress,
                  let contexte = CGContext(
                    data: base, width: cote, height: cote,
                    bitsPerComponent: 8, bytesPerRow: cote * 4, space: espace,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            contexte.interpolationQuality = .medium
            contexte.draw(image, in: CGRect(x: 0, y: 0, width: cote, height: cote))
            return true
        }
        return succes ? pixels : nil
    }
}

// MARK: - Distances

/// Comment on mesure l'écart entre deux signatures.
///
/// Les trois composantes sont chacune bornées entre 0 (identiques) et 1 (aussi
/// éloignées que possible). C'est cette borne commune qui permet de les
/// combiner par une simple moyenne pondérée : sans elle, la composante à la
/// plus grande amplitude déciderait seule du résultat.
enum DistanceSignature {

    /// Écart de GAMME CHROMATIQUE, par la distance de Hellinger entre les deux
    /// histogrammes.
    ///
    /// Hellinger plutôt qu'une distance euclidienne entre histogrammes : elle
    /// compare des proportions, ne s'affole pas quand une case est à zéro d'un
    /// côté, et reste bornée à 1 quoi qu'il arrive.
    static func couleur(_ a: SignatureOeuvre, _ b: SignatureOeuvre) -> Float {
        guard a.histogramme.count == b.histogramme.count else { return 1 }
        var recouvrement: Float = 0
        for i in a.histogramme.indices {
            recouvrement += sqrt(a.histogramme[i] * b.histogramme[i])
        }
        return sqrt(max(0, 1 - recouvrement))
    }

    /// Écart de FACTURE, sur les trois mesures de matière.
    static func matiere(_ a: SignatureOeuvre, _ b: SignatureOeuvre) -> Float {
        let dc = a.contraste - b.contraste
        let dk = a.contours - b.contours
        let dg = a.granularite - b.granularite
        // Divisé par √3 : trois axes bornés à 1 chacun donnent au pire √3.
        return min(sqrt(dc * dc + dk * dk + dg * dg) / 1.7320508, 1)
    }

    /// Écart de RESSEMBLANCE GLOBALE, sur l'empreinte Vision.
    ///
    /// Les deux vecteurs étant unitaires, leur distance euclidienne va de 0 à
    /// 2 : on divise par 2 pour rejoindre l'échelle des deux autres.
    static func empreinte(_ a: SignatureOeuvre, _ b: SignatureOeuvre) -> Float {
        let va = a.empreinte, vb = b.empreinte
        guard va.count == vb.count, !va.isEmpty else { return 0.5 }
        return min(sqrt(vDSP.distanceSquared(va, vb)) / 2, 1)
    }

    /// Part de l'empreinte Vision dans le versant « style » de la distance.
    ///
    /// Elle n'y est PAS majoritaire, et c'est délibéré : c'est celle des trois
    /// composantes qui reste la plus marquée par le sujet représenté, alors
    /// que la demande porte sur le style. Elle apporte ce que les mesures de
    /// matière ne voient pas — la composition, l'organisation générale — sans
    /// ramener le regroupement au genre.
    static let partEmpreinte: Float = 0.4

    /// La distance finale, telle que la règle le curseur.
    ///
    /// `poidsCouleur` va de 0 (rapprocher sur le seul style) à 1 (sur la seule
    /// gamme de couleurs).
    static func totale(_ a: SignatureOeuvre, _ b: SignatureOeuvre,
                       poidsCouleur: Float) -> Float {
        let style = (1 - partEmpreinte) * matiere(a, b) + partEmpreinte * empreinte(a, b)
        return poidsCouleur * couleur(a, b) + (1 - poidsCouleur) * style
    }
}
