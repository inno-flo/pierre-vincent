import Foundation
import SwiftData

// MARK: - Rangement des signatures sur le disque

/// Les signatures calculées, conservées d'une session à l'autre.
///
/// **Pourquoi PAS un champ de `Oeuvre`.** Un vecteur Vision pèse trois
/// kilo-octets ; mille œuvres en font trois mégaoctets. Rangé dans le modèle
/// SwiftData, il devrait aussi entrer dans le format d'échange `.pvbase`
/// (règle du projet : tout champ ajouté au modèle y va, sous peine de se
/// perdre en silence) — or ce fichier frôle déjà les 640 Mo et se construit
/// entièrement en mémoire. La signature n'est pas une donnée de l'œuvre, c'est
/// un CALCUL sur sa photo : elle se refait, elle ne se transporte pas.
///
/// **Indexées par `photoNom`, et non par l'identifiant de l'œuvre.** C'est ce
/// qui rend le cache auto-nettoyant : une photo remplacée ou recompressée
/// reçoit un nouveau nom de fichier (voir `RecompressionPhotos`), son ancienne
/// signature ne correspond donc plus à rien et la nouvelle image est
/// recalculée d'elle-même. Indexer par œuvre aurait laissé une signature
/// périmée décrire une photo qui a changé, sans aucun signe à l'écran.
@MainActor
@Observable
final class BanqueSignatures {

    static let partagee = BanqueSignatures()
    private init() {}

    private(set) var signatures: [String: SignatureOeuvre] = [:]
    private var chargee = false

    /// Fichier de rangement, à côté du dossier des photos.
    private static var fichier: URL {
        let dossier = PhotoStore.dossierRacine
            .appendingPathComponent("Signatures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier,
                                                 withIntermediateDirectories: true)
        return dossier.appendingPathComponent("signatures.json")
    }

    /// Charge le fichier au premier besoin. Les entrées d'une version
    /// antérieure du descripteur sont **écartées** : mêlées aux nouvelles,
    /// elles produiraient des distances calculées sur deux façons de mesurer
    /// différentes, donc des regroupements faux sans le moindre symptôme.
    func charger() {
        guard !chargee else { return }
        chargee = true
        guard let donnees = try? Data(contentsOf: Self.fichier),
              let lues = try? JSONDecoder().decode([String: SignatureOeuvre].self,
                                                   from: donnees)
        else { return }
        signatures = lues.filter { $0.value.version == SignatureOeuvre.versionCourante }
    }

    func enregistrer() {
        guard let donnees = try? JSONEncoder().encode(signatures) else { return }
        try? donnees.write(to: Self.fichier, options: .atomic)
    }

    func signature(pour nom: String) -> SignatureOeuvre? {
        charger()
        return signatures[nom]
    }

    func poser(_ signature: SignatureOeuvre, pour nom: String) {
        signatures[nom] = signature
    }

    /// Oublie les signatures dont la photo n'est plus référencée par aucune
    /// œuvre, et rend le nombre d'entrées retirées.
    @discardableResult
    func purger(nomsUtiles: Set<String>) -> Int {
        charger()
        let avant = signatures.count
        signatures = signatures.filter { nomsUtiles.contains($0.key) }
        return avant - signatures.count
    }

    /// Efface tout — pour une analyse complète demandée explicitement.
    func vider() {
        charger()
        signatures.removeAll()
    }
}

// MARK: - La passe d'analyse

/// Calcul des signatures manquantes.
///
/// **La base est figée, mais l'analyse reste relançable.** Comme les
/// signatures sont indexées par nom de fichier photo, une relance ne recalcule
/// que ce qu'elle ne trouve pas : ajouter deux ou trois œuvres et relancer,
/// c'est deux ou trois calculs, pas mille. La commande « tout recalculer »
/// existe à part, pour le jour où la façon de mesurer changerait.
enum AnalyseAffinites {

    /// État des lieux, sans rien calculer — de quoi annoncer des chiffres
    /// réels avant de lancer une opération longue.
    struct Bilan {
        /// Œuvres concernées (celles qui ont une photo).
        let avecPhoto: Int
        /// Parmi elles, celles dont la signature manque encore.
        let aCalculer: Int

        var toutEstFait: Bool { aCalculer == 0 }
    }

    struct Resultat {
        let calculees: Int
        let echecs: Int
    }

    /// Le lot concerné : les œuvres de la **Réserve** qui ont une photo.
    ///
    /// La demande porte sur ce fonds-là, et lui seul : ce sont les œuvres
    /// encore détenues, celles qu'on cherche à rapprocher pour les accrocher
    /// ou les ranger ensemble. Une œuvre vendue ou donnée n'a plus à être
    /// rapprochée de quoi que ce soit.
    static func lotReserve(_ toutes: [Oeuvre]) -> [Oeuvre] {
        toutes.filter { $0.feuille == .reserve && estEnReserve($0) && !$0.photoNom.isEmpty }
    }

    /// Lance l'analyse et rend le texte à afficher — partagé par la commande
    /// du menu Fichier et par le bouton de la vue, pour que les deux disent
    /// exactement la même chose.
    @MainActor
    static func executerEtDecrire(toutes: [Oeuvre], toutRecalculer: Bool) async -> String {
        let lot = lotReserve(toutes)
        guard !lot.isEmpty else {
            return "Aucune œuvre de la Réserve ne porte de photo : il n'y a rien à analyser."
        }
        // Au passage : les signatures de photos qui n'existent plus n'ont
        // aucune raison d'encombrer le fichier.
        BanqueSignatures.partagee.purger(nomsUtiles: Set(toutes.map(\.photoNom)))

        let avant = bilan(oeuvres: lot)
        guard toutRecalculer || !avant.toutEstFait else {
            return "Les \(avant.avecPhoto) œuvres de la Réserve sont déjà analysées. "
                 + "Rien à faire."
        }
        let r = await analyser(oeuvres: lot, toutRecalculer: toutRecalculer)
        // Prévient la vue que la banque a changé — l'analyse peut avoir été
        // lancée depuis le menu Fichier, donc hors de `VueAffinites`, qui n'a
        // alors aucun autre moyen de le savoir.
        signalerChangement()
        var texte = "\(r.calculees) œuvre(s) analysée(s)."
        if r.echecs > 0 {
            texte += " \(r.echecs) photo(s) illisible(s) ont été laissées de côté."
        }
        return texte
    }

    /// Clé du compteur qui dit « la banque de signatures a changé ».
    static let cleVersionBanque = "affinitesVersionBanque"

    private static func signalerChangement() {
        let d = UserDefaults.standard
        d.set(d.integer(forKey: cleVersionBanque) + 1, forKey: cleVersionBanque)
    }

    /// Les photos des œuvres à analyser, sans doublon.
    ///
    /// Deux œuvres peuvent partager un nom de fichier après un import répété :
    /// on ne calcule alors qu'une fois.
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
        let banque = BanqueSignatures.partagee
        banque.charger()
        let noms = photos(de: oeuvres)
        let manquantes = noms.filter { banque.signatures[$0] == nil }.count
        return Bilan(avecPhoto: noms.count, aCalculer: manquantes)
    }

    /// Calcule les signatures manquantes, une photo à la fois.
    ///
    /// **Rend la main entre deux fichiers** (`Task.detached` par photo) : sans
    /// cela l'interface se figerait du premier au dernier, et le compteur de
    /// progression sauterait d'un coup à la fin au lieu d'avancer — même
    /// raison que dans `ImportPhotos`.
    ///
    /// L'enregistrement se fait par paquets de cinquante, et non seulement à
    /// la fin : une analyse interrompue (fermeture de l'app, panne) garde
    /// alors l'essentiel de son travail, et la relance reprend là où elle en
    /// était.
    @MainActor
    static func analyser(oeuvres: [Oeuvre], toutRecalculer: Bool = false) async -> Resultat {
        let banque = BanqueSignatures.partagee
        banque.charger()
        if toutRecalculer { banque.vider() }

        let aFaire = photos(de: oeuvres).filter { banque.signatures[$0] == nil }
        guard !aFaire.isEmpty else { return Resultat(calculees: 0, echecs: 0) }

        let suivi = ProgressionImport.partagee
        suivi.demarrer(total: aFaire.count, libelle: "Analyse")
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
            // Décodage, mesures et appel à Vision : tout se passe hors du fil
            // principal, qui ne fait que ranger le résultat.
            let signature = await Task.detached(priority: .utility) {
                await CalculSignature.signature(pour: url)
            }.value

            if let signature {
                banque.poser(signature, pour: nom)
                calculees += 1
            } else {
                echecs += 1
            }
            suivi.avancer()

            if (rang + 1) % 50 == 0 { banque.enregistrer() }
        }
        return Resultat(calculees: calculees, echecs: echecs)
    }
}

// MARK: - Distances préparées

/// Les trois composantes de distance, calculées UNE fois pour toutes les
/// paires d'un lot d'œuvres.
///
/// **C'est ce qui rend le curseur instantané.** Recalculer la distance
/// complète à chaque déplacement du curseur demanderait de reparcourir des
/// vecteurs de 768 nombres pour chacune des cinq cent mille paires que forment
/// mille œuvres — bien trop pour suivre un curseur qu'on déplace. Les trois
/// composantes, elles, ne
/// dépendent PAS du curseur : seule leur pondération en dépend. Préparées une
/// fois, les recombiner ne coûte plus que trois multiplications par paire.
struct MatricesAffinites: Sendable {

    /// Nombre d'œuvres du lot.
    let nombre: Int
    /// Les noms de photo, dans le même ordre que les lignes et colonnes.
    let noms: [String]

    // Demi-matrices (triangle supérieur seulement : la distance est
    // symétrique, et la diagonale vaut zéro).
    private let dCouleur: [Float]
    private let dMatiere: [Float]
    private let dEmpreinte: [Float]

    /// Position de la paire (i, j), avec i < j, dans les tableaux ci-dessus.
    private func index(_ i: Int, _ j: Int) -> Int {
        i * nombre - i * (i + 1) / 2 + (j - i - 1)
    }

    /// La distance entre deux œuvres du lot, pour un réglage de curseur donné.
    func distance(_ i: Int, _ j: Int, poidsCouleur: Float) -> Float {
        if i == j { return 0 }
        let p = i < j ? index(i, j) : index(j, i)
        let style = (1 - DistanceSignature.partEmpreinte) * dMatiere[p]
                  + DistanceSignature.partEmpreinte * dEmpreinte[p]
        return poidsCouleur * dCouleur[p] + (1 - poidsCouleur) * style
    }

    /// Prépare les trois demi-matrices. **À appeler hors du fil principal** :
    /// c'est ici que passe tout le temps de calcul.
    static func preparer(noms: [String], signatures: [SignatureOeuvre])
        -> MatricesAffinites {
        let n = signatures.count
        let paires = n * (n - 1) / 2
        var couleur = [Float](repeating: 0, count: max(paires, 0))
        var matiere = [Float](repeating: 0, count: max(paires, 0))
        var empreinte = [Float](repeating: 0, count: max(paires, 0))

        var p = 0
        for i in 0..<max(n, 0) {
            for j in (i + 1)..<max(n, 0) {
                couleur[p] = DistanceSignature.couleur(signatures[i], signatures[j])
                matiere[p] = DistanceSignature.matiere(signatures[i], signatures[j])
                empreinte[p] = DistanceSignature.empreinte(signatures[i], signatures[j])
                p += 1
            }
        }
        return MatricesAffinites(nombre: n, noms: noms, dCouleur: couleur,
                                 dMatiere: matiere, dEmpreinte: empreinte)
    }
}

// MARK: - Regroupement

/// Une famille d'œuvres qui se ressemblent.
struct GroupeAffinite: Identifiable {
    let id: Int
    /// Membres du groupe, le plus REPRÉSENTATIF en tête (voir `medoide`).
    let oeuvres: [Oeuvre]
    /// Palette affichée en tête de famille : celle de son œuvre la plus
    /// représentative, et non une moyenne — une moyenne de couleurs vives
    /// donne un gris, qui ne dirait rien de la famille.
    let palette: [TeinteDominante]
    /// Caractérisation en quelques mots (« clair · vif · contrasté · chaud »).
    let caractere: String
}

/// Constitution des familles.
///
/// **Méthode : voisins mutuels, seuil, puis composantes connexes.**
/// Deux œuvres sont reliées si chacune figure parmi les proches voisines de
/// l'autre ET si leur distance passe sous le seuil ; les groupes sont ensuite
/// les paquets d'œuvres reliées de proche en proche.
///
/// L'exigence de RÉCIPROCITÉ est ce qui empêche l'effet de chaîne : sans
/// elle, une œuvre médiocrement proche de deux familles les soude en une
/// seule, et au-delà d'un certain seuil tout finit dans un unique gros
/// paquet. Avec elle, il faut que les deux œuvres se « choisissent »
/// mutuellement.
///
/// Le résultat est **déterministe** — contrairement à un k-moyennes, qui
/// dépend de son tirage initial et donnerait des familles différentes à
/// chaque affichage.
enum Regroupement {

    /// Nombre de voisins examinés pour chaque œuvre.
    static let voisinsExamines = 6

    struct Resultat {
        let groupes: [GroupeAffinite]
        /// Œuvres qui ne rejoignent aucune famille au seuil courant.
        let isolees: [Oeuvre]
    }

    /// - Parameters:
    ///   - oeuvres: le lot à regrouper, déjà filtré par la rubrique.
    ///   - signatures: leur signature, dans le même ordre.
    ///   - matrices: les distances préparées, dans le même ordre.
    ///   - poidsCouleur: 0 = style seul, 1 = couleurs seules.
    ///   - seuil: distance maximale pour relier deux œuvres.
    /// - Parameter genres: pour chaque œuvre, ses genres en minuscules. Sert
    ///   uniquement quand `memeGenreSeulement` est vrai.
    /// - Parameter memeGenreSeulement: n'autorise un lien qu'entre deux œuvres
    ///   partageant au moins un genre. C'est le « indépendamment ou non de
    ///   leur genre » de la demande : le genre agit ici comme une CONDITION
    ///   sur les liens, jamais comme un ingrédient de la distance — celle-ci
    ///   ne mesure que le style et les couleurs, dans les deux cas.
    static func grouper(oeuvres: [Oeuvre], signatures: [SignatureOeuvre],
                        matrices: MatricesAffinites,
                        poidsCouleur: Float, seuil: Float,
                        genres: [Set<String>] = [],
                        memeGenreSeulement: Bool = false) -> Resultat {
        let n = oeuvres.count
        guard n > 1, matrices.nombre == n else {
            return Resultat(groupes: [], isolees: oeuvres)
        }

        // 1. Les `voisinsExamines` plus proches de chaque œuvre.
        var voisins = [Set<Int>](repeating: [], count: n)
        for i in 0..<n {
            var candidats: [(Int, Float)] = []
            candidats.reserveCapacity(n - 1)
            for j in 0..<n where j != i {
                candidats.append((j, matrices.distance(i, j, poidsCouleur: poidsCouleur)))
            }
            candidats.sort { $0.1 < $1.1 }
            voisins[i] = Set(candidats.prefix(voisinsExamines).map(\.0))
        }

        // 2. Les liens : réciproques ET sous le seuil.
        var partition = Partition(taille: n)
        for i in 0..<n {
            for j in voisins[i] where j > i && voisins[j].contains(i) {
                if memeGenreSeulement, genres.count == n,
                   genres[i].isDisjoint(with: genres[j]) { continue }
                if matrices.distance(i, j, poidsCouleur: poidsCouleur) <= seuil {
                    partition.reunir(i, j)
                }
            }
        }

        // 3. Les paquets ainsi formés.
        var paquets: [Int: [Int]] = [:]
        for i in 0..<n { paquets[partition.racine(i), default: []].append(i) }

        var groupes: [GroupeAffinite] = []
        var isolees: [Oeuvre] = []
        for membres in paquets.values {
            guard membres.count > 1 else {
                isolees.append(oeuvres[membres[0]])
                continue
            }
            let ordonnes = ordonner(membres, matrices: matrices, poidsCouleur: poidsCouleur)
            let representant = ordonnes[0]
            groupes.append(GroupeAffinite(
                id: representant,
                oeuvres: ordonnes.map { oeuvres[$0] },
                palette: signatures[representant].palette,
                caractere: caractere(de: signatures[representant])))
        }

        // Familles nombreuses en premier ; à égalité, l'ordre reste stable
        // grâce à l'identifiant, sans quoi les familles se réordonneraient
        // toutes seules d'un affichage à l'autre.
        groupes.sort { ($0.oeuvres.count, -$0.id) > ($1.oeuvres.count, -$1.id) }
        return Resultat(groupes: groupes, isolees: isolees)
    }

    /// Range les membres d'un groupe autour de son **médoïde** — celui dont la
    /// distance moyenne aux autres est la plus faible, donc le plus
    /// représentatif de la famille. Il vient en tête, les autres suivent par
    /// éloignement croissant.
    private static func ordonner(_ membres: [Int], matrices: MatricesAffinites,
                                 poidsCouleur: Float) -> [Int] {
        var medoide = membres[0]
        var meilleure = Float.greatestFiniteMagnitude
        for candidat in membres {
            var somme: Float = 0
            for autre in membres where autre != candidat {
                somme += matrices.distance(candidat, autre, poidsCouleur: poidsCouleur)
            }
            if somme < meilleure { meilleure = somme; medoide = candidat }
        }
        return membres.sorted {
            matrices.distance(medoide, $0, poidsCouleur: poidsCouleur)
                < matrices.distance(medoide, $1, poidsCouleur: poidsCouleur)
        }
    }

    /// Les œuvres les plus proches d'une œuvre donnée, la plus proche d'abord.
    static func proches(de index: Int, parmi oeuvres: [Oeuvre],
                        matrices: MatricesAffinites, poidsCouleur: Float,
                        combien: Int) -> [(oeuvre: Oeuvre, distance: Float)] {
        guard matrices.nombre == oeuvres.count, index < oeuvres.count else { return [] }
        var liste: [(Int, Float)] = []
        for j in oeuvres.indices where j != index {
            liste.append((j, matrices.distance(index, j, poidsCouleur: poidsCouleur)))
        }
        liste.sort { $0.1 < $1.1 }
        return liste.prefix(combien).map { (oeuvres[$0.0], $0.1) }
    }

    /// Caractérise une signature en quelques mots, pour l'afficher en tête de
    /// famille. Purement descriptif : c'est ce que les nombres disent, écrit
    /// en français.
    static func caractere(de s: SignatureOeuvre) -> String {
        var mots: [String] = []

        switch s.clarte {
        case ..<38:  mots.append("sombre")
        case ..<62:  mots.append("demi-teinte")
        default:     mots.append("clair")
        }

        switch s.chroma {
        case ..<12:  mots.append("presque gris")
        case ..<28:  mots.append("sourd")
        default:     mots.append("coloré")
        }

        switch s.contraste {
        case ..<0.25: mots.append("peu contrasté")
        case ..<0.5:  break
        default:      mots.append("contrasté")
        }

        if s.granularite > 0.35 { mots.append("matière apparente") }
        else if s.contours < 0.15 { mots.append("fondu") }

        // La tiédeur n'est nommée que lorsqu'elle est nette : une dominante
        // à peine marquée ne se voit pas, l'annoncer tromperait.
        if s.tiedeur > 12 { mots.append("chaud") }
        else if s.tiedeur < -6 { mots.append("froid") }

        return mots.joined(separator: " · ")
    }
}

/// Structure « union-trouve » : de quoi réunir des éléments par paires et
/// savoir ensuite qui se retrouve avec qui. Une vingtaine de lignes pour
/// remplacer un parcours de graphe complet.
private struct Partition {
    private var parents: [Int]

    init(taille: Int) { parents = Array(0..<taille) }

    /// Le représentant du paquet auquel appartient `i`, avec raccourcissement
    /// du chemin au passage (ce qui rend les appels suivants immédiats).
    mutating func racine(_ i: Int) -> Int {
        var courant = i
        while parents[courant] != courant { courant = parents[courant] }
        var aRelier = i
        while parents[aRelier] != courant {
            let suivant = parents[aRelier]
            parents[aRelier] = courant
            aRelier = suivant
        }
        return courant
    }

    mutating func reunir(_ a: Int, _ b: Int) {
        let ra = racine(a), rb = racine(b)
        if ra != rb { parents[rb] = ra }
    }
}
