import Foundation
import CoreML
import CoreGraphics
import ImageIO
import Accelerate

// MARK: - Signature CLIP

/// Signature d'une photo par **CLIP** (MobileCLIP-S0, converti en Core ML par
/// Apple), pour comparer la qualité de ses regroupements à ceux du moteur
/// maison de `SignatureOeuvre`.
///
/// Volontairement réduite à UN SEUL nombre : le vecteur d'embedding,
/// normalisé. Pas de couleur ni de matière calculées à côté — c'est CLIP
/// seul qu'on met à l'épreuve ici, sans le mélanger à nos propres mesures.
/// Mélanger les deux aurait comparé « CLIP + nos mesures » à « Vision + nos
/// mesures », masquant justement la différence qui nous intéresse.
///
/// Voir `PierreVincent/ModeleCLIP/README.md` pour la licence du modèle
/// (recherche seulement) avant tout usage au-delà de cet essai.
struct SignatureCLIP: Codable, Sendable {
    /// Incrémenter en cas de changement de modèle ou de prétraitement : les
    /// signatures d'une version antérieure sont alors ignorées au chargement.
    static let versionCourante = 1
    var version: Int

    /// Le vecteur, en octets bruts (voir `SignatureOeuvre.empreinteBrute` pour
    /// la même raison : un tableau de 512 nombres en clair dans le JSON
    /// pèserait bien plus cher que sa version binaire).
    var vecteurBrut: Data
    var vecteur: [Float] {
        vecteurBrut.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

/// Calcule les signatures CLIP. C'est un `actor` — et non un simple enum
/// comme `CalculSignature` — parce qu'il y a ici un ÉTAT à protéger : le
/// modèle chargé, réutilisé d'une photo à l'autre. Un acteur le sérialise
/// naturellement, dans le droit fil de la file sérielle de `CacheVignettes` :
/// une prédiction Core ML à la fois, jamais une tâche par image.
///
/// **Passe par `MLModel` brut, pas par la classe `mobileclip_s0_image`
/// générée par Xcode.** Le projet fixe `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor` : cette classe étant générée DANS notre cible, elle en hérite,
/// et ses méthodes deviennent isolées au fil principal — inutilisables
/// depuis cet acteur, qui existe justement pour sortir l'inférence du fil
/// principal. `MLModel` est un type système, non concerné par ce réglage :
/// on retrouve le modèle par son nom de ressource compilée (`.mlmodelc`) et
/// on construit l'entrée à la main, comme le fait la classe générée en
/// coulisses.
actor MoteurCLIP {
    static let shared = MoteurCLIP()
    private init() {}

    /// Côté de l'image donnée au modèle — sa taille d'entrée EXACTE
    /// (256×256). Décodée directement à cette taille par ImageIO : l'image
    /// pleine n'est jamais chargée, même règle que partout ailleurs dans
    /// l'app.
    private static let cote = 256
    private static let nomRessource = "mobileclip_s0_image"

    private var modele: MLModel?
    /// Vrai une fois qu'un essai de chargement a échoué — évite de retenter
    /// le chargement à chaque photo si le modèle est absent du bundle
    /// (téléchargement non fait, voir `ModeleCLIP/README.md`).
    private var chargementEchoue = false

    private func modeleCharge() async -> MLModel? {
        if let modele { return modele }
        guard !chargementEchoue else { return nil }
        guard let url = Bundle.main.url(forResource: Self.nomRessource,
                                        withExtension: "mlmodelc"),
              let m = try? await MLModel.load(contentsOf: url,
                                              configuration: MLModelConfiguration())
        else {
            chargementEchoue = true
            return nil
        }
        modele = m
        return m
    }

    /// `nil` si le modèle n'est pas disponible, ou si la photo est illisible.
    func signature(pour url: URL) async -> SignatureCLIP? {
        guard let modele = await modeleCharge(),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = Self.imageReduite(source: source, cote: Self.cote),
              let tampon = try? MLFeatureValue(cgImage: image, pixelsWide: Self.cote,
                                               pixelsHigh: Self.cote,
                                               pixelFormatType: kCVPixelFormatType_32ARGB,
                                               options: nil).imageBufferValue,
              let entree = try? MLDictionaryFeatureProvider(
                dictionary: ["image": MLFeatureValue(pixelBuffer: tampon)]),
              let sortie = try? await modele.prediction(from: entree),
              let arr = sortie.featureValue(for: "final_emb_1")?.multiArrayValue
        else { return nil }

        var v = [Float](repeating: 0, count: arr.count)
        for i in 0..<arr.count { v[i] = arr[i].floatValue }
        let norme = sqrt(vDSP.sum(vDSP.multiply(v, v)))
        guard norme > 0 else { return nil }
        v = vDSP.divide(v, norme)

        return SignatureCLIP(version: SignatureCLIP.versionCourante,
                             vecteurBrut: v.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    /// Vrai si le modèle est présent et se charge — sert à afficher un
    /// message clair si le fichier n'a pas été téléchargé (voir README).
    func disponible() async -> Bool { await modeleCharge() != nil }

    nonisolated private static func imageReduite(source: CGImageSource, cote: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: cote
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Distance entre deux signatures CLIP : cosinus, ramenée à 0…1 comme les
/// distances de `DistanceSignature` — 0 = identiques, 1 = opposées.
enum DistanceCLIP {
    static func cosinus(_ a: SignatureCLIP, _ b: SignatureCLIP) -> Float {
        let va = a.vecteur, vb = b.vecteur
        guard va.count == vb.count, !va.isEmpty else { return 1 }
        let produit = vDSP.dot(va, vb)
        return min(max((1 - produit) / 2, 0), 1)
    }
}

// MARK: - Banque de signatures CLIP

/// Pendant de `BanqueSignatures`, dans un fichier À PART
/// (`signatures_clip.json`) : les deux moteurs ne se mélangent jamais, y
/// compris sur disque, pour qu'on puisse effacer ou recalculer l'un sans
/// toucher l'autre.
@MainActor
@Observable
final class BanqueSignaturesCLIP {
    static let partagee = BanqueSignaturesCLIP()
    private init() {}

    private(set) var signatures: [String: SignatureCLIP] = [:]
    private var chargee = false

    private static var fichier: URL {
        let dossier = PhotoStore.dossierRacine
            .appendingPathComponent("Signatures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier,
                                                 withIntermediateDirectories: true)
        return dossier.appendingPathComponent("signatures_clip.json")
    }

    func charger() {
        guard !chargee else { return }
        chargee = true
        guard let donnees = try? Data(contentsOf: Self.fichier),
              let lues = try? JSONDecoder().decode([String: SignatureCLIP].self,
                                                   from: donnees)
        else { return }
        signatures = lues.filter { $0.value.version == SignatureCLIP.versionCourante }
    }

    func enregistrer() {
        guard let donnees = try? JSONEncoder().encode(signatures) else { return }
        try? donnees.write(to: Self.fichier, options: .atomic)
    }

    func poser(_ signature: SignatureCLIP, pour nom: String) { signatures[nom] = signature }

    @discardableResult
    func purger(nomsUtiles: Set<String>) -> Int {
        charger()
        let avant = signatures.count
        signatures = signatures.filter { nomsUtiles.contains($0.key) }
        return avant - signatures.count
    }

    func vider() { charger(); signatures.removeAll() }
}

// MARK: - La passe d'analyse CLIP

/// Pendant de `AnalyseAffinites`. Même logique de relance partielle (indexée
/// par nom de fichier photo) : ajouter deux ou trois œuvres et relancer ne
/// recalcule que ces deux ou trois signatures.
enum AnalyseAffinitesCLIP {

    struct Bilan {
        let avecPhoto: Int
        let aCalculer: Int
        var toutEstFait: Bool { aCalculer == 0 }
    }

    struct Resultat {
        let calculees: Int
        let echecs: Int
        /// Vrai si le modèle lui-même est introuvable (fichier non
        /// téléchargé) — à distinguer d'une simple photo illisible.
        let modeleAbsent: Bool
    }

    static let cleVersionBanque = "affinitesClipVersionBanque"

    private static func signalerChangement() {
        let d = UserDefaults.standard
        d.set(d.integer(forKey: cleVersionBanque) + 1, forKey: cleVersionBanque)
    }

    private static func photos(de oeuvres: [Oeuvre]) -> [String] {
        var vues = Set<String>()
        var liste: [String] = []
        for o in oeuvres where !o.photoNom.isEmpty {
            if vues.insert(o.photoNom).inserted { liste.append(o.photoNom) }
        }
        return liste
    }

    @MainActor
    static func bilan(oeuvres: [Oeuvre]) -> Bilan {
        let banque = BanqueSignaturesCLIP.partagee
        banque.charger()
        let noms = photos(de: oeuvres)
        let manquantes = noms.filter { banque.signatures[$0] == nil }.count
        return Bilan(avecPhoto: noms.count, aCalculer: manquantes)
    }

    @MainActor
    static func analyser(oeuvres: [Oeuvre], toutRecalculer: Bool = false) async -> Resultat {
        guard await MoteurCLIP.shared.disponible() else {
            return Resultat(calculees: 0, echecs: 0, modeleAbsent: true)
        }
        let banque = BanqueSignaturesCLIP.partagee
        banque.charger()
        if toutRecalculer { banque.vider() }

        let aFaire = photos(de: oeuvres).filter { banque.signatures[$0] == nil }
        guard !aFaire.isEmpty else {
            return Resultat(calculees: 0, echecs: 0, modeleAbsent: false)
        }

        let suivi = ProgressionImport.partagee
        suivi.demarrer(total: aFaire.count, libelle: "Analyse CLIP")
        defer {
            suivi.terminer()
            banque.enregistrer()
        }

        var calculees = 0
        var echecs = 0
        for (rang, nom) in aFaire.enumerated() {
            guard let url = PhotoStore.urlPhoto(nom: nom) else {
                echecs += 1
                suivi.avancer()
                continue
            }
            let signature = await MoteurCLIP.shared.signature(pour: url)
            if let signature {
                banque.poser(signature, pour: nom)
                calculees += 1
            } else {
                echecs += 1
            }
            suivi.avancer()
            if (rang + 1) % 50 == 0 { banque.enregistrer() }
        }
        return Resultat(calculees: calculees, echecs: echecs, modeleAbsent: false)
    }

    /// Lance l'analyse et rend le texte à afficher, comme
    /// `AnalyseAffinites.executerEtDecrire` — même patron, deux moteurs.
    @MainActor
    static func executerEtDecrire(toutes: [Oeuvre], toutRecalculer: Bool) async -> String {
        let lot = AnalyseAffinites.lotReserve(toutes)
        guard !lot.isEmpty else {
            return "Aucune œuvre de la Réserve ne porte de photo : il n'y a rien à analyser."
        }
        guard await MoteurCLIP.shared.disponible() else {
            return "Le modèle CLIP n'est pas installé. Voir "
                 + "PierreVincent/ModeleCLIP/README.md pour le télécharger."
        }
        BanqueSignaturesCLIP.partagee.purger(nomsUtiles: Set(toutes.map(\.photoNom)))

        let avant = bilan(oeuvres: lot)
        guard toutRecalculer || !avant.toutEstFait else {
            return "Les \(avant.avecPhoto) œuvres de la Réserve sont déjà analysées "
                 + "(CLIP). Rien à faire."
        }
        let r = await analyser(oeuvres: lot, toutRecalculer: toutRecalculer)
        signalerChangement()
        var texte = "\(r.calculees) œuvre(s) analysée(s) (CLIP)."
        if r.echecs > 0 {
            texte += " \(r.echecs) photo(s) illisible(s) ont été laissées de côté."
        }
        return texte
    }
}

// MARK: - Distances et regroupement CLIP

/// Les distances CLIP, préparées une fois pour tout un lot — même principe
/// que `MatricesAffinites`, mais une SEULE demi-matrice : CLIP ne se règle
/// pas par curseur Couleur/Style, il n'y a qu'une distance.
struct MatriceCLIP: Sendable {
    let nombre: Int
    private let d: [Float]

    private func index(_ i: Int, _ j: Int) -> Int {
        i * nombre - i * (i + 1) / 2 + (j - i - 1)
    }

    func distance(_ i: Int, _ j: Int) -> Float {
        if i == j { return 0 }
        return i < j ? d[index(i, j)] : d[index(j, i)]
    }

    static func preparer(signatures: [SignatureCLIP]) -> MatriceCLIP {
        let n = signatures.count
        let paires = n * (n - 1) / 2
        var dd = [Float](repeating: 0, count: max(paires, 0))
        var p = 0
        for i in 0..<max(n, 0) {
            for j in (i + 1)..<max(n, 0) {
                dd[p] = DistanceCLIP.cosinus(signatures[i], signatures[j])
                p += 1
            }
        }
        return MatriceCLIP(nombre: n, d: dd)
    }
}

/// Cache en mémoire process de la dernière matrice CLIP calculée, même rôle
/// et même clé (`cleLot`) que `CacheMatricesAffinites` — voir sa
/// documentation dans `Affinites.swift`. Un cache SÉPARÉ, pas partagé avec
/// l'autre moteur : les deux distances n'ont rien de comparable terme à
/// terme, et les mélanger effacerait l'un des deux sans prévenir.
@MainActor
final class CacheMatriceCLIP {
    static let partagee = CacheMatriceCLIP()
    private init() {}

    private var cle: String?
    private var matrice: MatriceCLIP?

    func pour(_ cle: String) -> MatriceCLIP? {
        self.cle == cle ? matrice : nil
    }

    func enregistrer(_ matrice: MatriceCLIP, pour cle: String) {
        self.cle = cle
        self.matrice = matrice
    }
}

/// Une famille CLIP. Pas de palette ni de caractérisation en mots : CLIP ne
/// nous donne qu'un vecteur, sans les mesures interprétables que
/// `SignatureOeuvre` calcule à côté (clarté, chroma…). `cohesion` reste le
/// même nombre, comparable, que celui de `GroupeAffinite` — c'est lui qui
/// permet de dire objectivement quel moteur fait des familles plus serrées.
struct GroupeAffiniteCLIP: Identifiable {
    let id: Int
    let oeuvres: [Oeuvre]
    let cohesion: Float
}

/// Constitution des familles CLIP.
///
/// **Le même algorithme que `Regroupement`, à l'identique** — voisins
/// mutuels réciproques puis seuil (`Regroupement.partitionner`,
/// `.ordonnerGenerique`, `.prochesGenerique`). Seule la distance change :
/// c'est délibéré, pour que la comparaison entre les deux vues porte sur la
/// SEULE chose qui diffère vraiment — CLIP contre notre propre mesure —, et
/// non sur deux façons de trancher les familles.
enum RegroupementCLIP {

    struct Resultat {
        let groupes: [GroupeAffiniteCLIP]
        let isolees: [Oeuvre]
    }

    static func grouper(oeuvres: [Oeuvre], matrice: MatriceCLIP, seuil: Float,
                        genres: [Set<String>] = [],
                        memeGenreSeulement: Bool = false) -> Resultat {
        let n = oeuvres.count
        guard n > 1, matrice.nombre == n else {
            return Resultat(groupes: [], isolees: oeuvres)
        }
        let distance: (Int, Int) -> Float = { matrice.distance($0, $1) }
        let paquets = Regroupement.partitionner(n: n, seuil: seuil, genres: genres,
                                                memeGenreSeulement: memeGenreSeulement,
                                                distance: distance)

        var groupes: [GroupeAffiniteCLIP] = []
        var isolees: [Oeuvre] = []
        for membres in paquets {
            guard membres.count > 1 else {
                isolees.append(oeuvres[membres[0]])
                continue
            }
            let (ordre, cohesion) = Regroupement.ordonnerGenerique(membres, distance: distance)
            groupes.append(GroupeAffiniteCLIP(id: ordre[0],
                                              oeuvres: ordre.map { oeuvres[$0] },
                                              cohesion: cohesion))
        }
        groupes.sort { ($0.oeuvres.count, -$0.id) > ($1.oeuvres.count, -$1.id) }
        return Resultat(groupes: groupes, isolees: isolees)
    }

    static func proches(de index: Int, parmi oeuvres: [Oeuvre], matrice: MatriceCLIP,
                        combien: Int) -> [(oeuvre: Oeuvre, distance: Float)] {
        guard matrice.nombre == oeuvres.count else { return [] }
        let resultats = Regroupement.prochesGenerique(de: index, n: oeuvres.count,
                                                       combien: combien) {
            matrice.distance($0, $1)
        }
        return resultats.map { (oeuvres[$0.0], $0.1) }
    }
}
