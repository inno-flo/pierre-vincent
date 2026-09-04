#if os(iOS)
import SwiftUI
import SwiftData

/// Pendant iPhone de `VueAffinites` (macOS) : même moteur
/// (`SignatureOeuvre`, `Affinites.swift`), présentation adaptée à l'écran et
/// aux gestes du téléphone.
///
/// **Fichier séparé, et non une vue partagée avec `#if` internes.** Trois
/// différences sont STRUCTURELLES, pas cosmétiques :
/// - le bandeau de réglages doit défiler AVEC le contenu, pas flotter au-dessus
///   (`.safeAreaInset`) — sinon la barre de navigation perd sa translucidité,
///   piège déjà rencontré et documenté pour le récapitulatif de `VueiOS` ;
/// - les tailles de police doivent rester sémantiques (Dynamic Type), jamais
///   figées en points comme sur Mac ;
/// - l'ouverture d'une œuvre passe par une navigation poussée vers « Œuvres
///   proches », pas par une visionneuse — voir plus bas.
/// Un fichier commun aurait multiplié les branches `#if` sur des points où
/// les deux plateformes ne se contentent pas de varier en apparence.
///
/// **Structure du contenu : `ScrollView` + `VStack`, PAS `List`.** Un essai
/// de migration vers `List(.insetGrouped)` (pour que les en-têtes de réglage
/// héritent nativement de la police des en-têtes de sidebar) a été REVERTÉ :
/// nichée dans une seule ligne de `List`, une grille de plusieurs vignettes
/// se voyait attribuer par UIKit un seul aperçu partagé lors d'un appui
/// prolongé — toutes les vignettes d'une famille apparaissaient fusionnées
/// en une seule image. Retour à la base du Catalogue (`VueGalerie`, qui
/// n'a jamais eu ce problème) : les blocs de réglages sont ajoutés en tête
/// du contenu défilant, comme `BandeauTypes` l'est pour les pastilles de tri.
///
/// **Plus de visionneuse plein écran, plus de menu contextuel.** Ces deux
/// vues ouvraient autrefois une image en grand par appui prolongé (menu
/// contextuel « Œuvres proches »). Après plusieurs essais infructueux pour
/// fiabiliser cette poussée depuis un `.contextMenu` — sans simulateur ni
/// appareil pour vérifier en direct —, la visionneuse est retirée : un tap
/// simple sur une vignette ouvre directement « Œuvres proches » pour cette
/// œuvre, sans geste à distinguer ni menu à attendre.
struct VueAffinitesiOS: View {
    @Environment(\.accentRubrique) private var accent

    let toutes: [Oeuvre]

    @AppStorage("affinitesPoidsCouleur") private var poidsCouleur = 0.5
    @AppStorage("affinitesSeuil") private var seuil = 0.32
    @AppStorage("affinitesMemeGenre") private var memeGenre = false
    /// Compteur incrémenté une seule fois PAR ANALYSE TERMINÉE (voir
    /// `AnalyseAffinites.executerEtDecrire`) — pas à chaque photo. Sert de
    /// clé à `.task(id:)` : lire directement
    /// `BanqueSignatures.partagee.signatures.count` à sa place a longtemps
    /// fait REDÉMARRER `preparerLot()` à CHAQUE signature posée pendant
    /// l'analyse (cette valeur change à chaque photo, et une lecture d'une
    /// propriété `@Observable` dans une clé de `.task` est suivie comme
    /// n'importe quelle autre) — d'où l'écran qui clignotait entre le
    /// contenu et l'état de préparation. `versionBanque`, lui, ne bouge
    /// qu'une fois l'analyse entière terminée.
    @AppStorage(AnalyseAffinites.cleVersionBanque) private var versionBanque = 0

    @State private var lot: [Oeuvre] = []
    @State private var signatures: [SignatureOeuvre] = []
    @State private var genres: [Set<String>] = []
    @State private var matrices: MatricesAffinites?
    @State private var preparation = false
    @State private var bilan: AnalyseAffinites.Bilan?

    /// `lot` vaut `[]` avant même que `preparerLot()` ait tourné une seule
    /// fois — sans ce drapeau, l'état « Aucune œuvre à rapprocher » (pensé
    /// pour une Réserve réellement vide) s'affichait à CHAQUE ouverture,
    /// le temps du chargement (capture du 4 sept. 2026).
    @State private var chargementInitial = true
    /// `cleLot` déjà traité par `preparerLot()` — sans ce garde-fou, revenir
    /// d'« Œuvres proches » par le bouton natif fait RÉAPPARAÎTRE cette vue,
    /// ce qui relance `.task(id:)` MÊME SI `cleLot` n'a pas changé (un
    /// cycle apparition/disparition suffit, pas seulement un changement
    /// d'id) — et donc tout `preparerLot()` depuis zéro : l'écran de
    /// comparaison des signatures réapparaissait au lieu de retrouver
    /// directement les familles déjà calculées (constaté à l'écran).
    @State private var dernierCleLotTraite: String?
    @State private var procheDe: Oeuvre?
    /// Présentation d'« Œuvres proches », adossée à `procheDe`.
    private var procheDePresente: Binding<Bool> {
        Binding(get: { procheDe != nil },
                set: { if !$0 { procheDe = nil } })
    }
    /// Bouton flottant « Retour en haut », même mécanisme que toutes les
    /// vues Galerie/Liste de l'app (voir `BoutonRetourHaut.swift`).
    @State private var boutonHautVisible = false
    private let ancreHaut = "ancre-haut-affinites"

    @State private var analyseEnCours = false
    @State private var messageAnalyse: String?
    @State private var confirmerToutRecalculer = false
    /// Familles repliées par leur `id` (`GroupeAffinite.id`, ou `-1` pour
    /// « À part ») — repliées à la demande, ouvertes par défaut.
    @State private var famillesFermees: Set<Int> = []

    private let nbProches = 24

    var body: some View {
        Group {
            // **Priorité absolue** : tant qu'une analyse tourne, on ne montre
            // QUE sa progression — jamais la grille ni un état vide en même
            // temps. `ProgressionImport.partagee.enCours` est la source de
            // vérité exacte (contrairement à `analyseEnCours`, vrai aussi
            // pendant le bref aller-retour qui découvre qu'il n'y a rien à
            // faire, cas où aucune boucle ne démarre réellement).
            if ProgressionImport.partagee.enCours {
                progressionEnCours
            } else if chargementInitial {
                // `lot` vaut `[]` avant même que `preparerLot()` ait tourné
                // une seule fois — sans ce drapeau, l'état « Aucune œuvre à
                // rapprocher » (pensé pour une Réserve réellement vide)
                // s'affichait à CHAQUE ouverture le temps du chargement,
                // un écran qui ne disait rien d'utile (capture fournie).
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lot.isEmpty {
                etatVide(symbole: "photo.artframe",
                         titre: "Aucune œuvre à rapprocher",
                         detail: "La Réserve ne contient aucune œuvre avec photo.")
            } else if signatures.isEmpty && !preparation {
                etatVide(symbole: "wand.and.rays",
                         titre: "Rien n'est encore analysé",
                         detail: "L'analyse lit chaque photo une fois et retient sa "
                               + "signature. Elle ne se refait pas au lancement.",
                         bouton: "Analyser les \(lot.count) œuvres")
            } else if preparation {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Comparaison des \(signatures.count) œuvres…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                contenuDefilant
            }
        }
        .background(Color.cremeFond)
        .navigationTitle("Affinités")
        .toolbar { contenuBarreOutils }
        .task(id: cleLot) { await preparerLot() }
        .alert("Analyse des affinités", isPresented: Binding(
            get: { messageAnalyse != nil },
            set: { if !$0 { messageAnalyse = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(messageAnalyse ?? "") }
        .alert("Tout recalculer ?", isPresented: $confirmerToutRecalculer) {
            Button("Annuler", role: .cancel) {}
            Button("Tout recalculer") { lancerAnalyse(toutRecalculer: true) }
        } message: {
            Text("Les signatures déjà calculées seront effacées et refaites, "
               + "photo par photo. Rien n'est perdu — ni les œuvres, ni les "
               + "photos —, mais l'opération reprend depuis le début.")
        }
        // « Œuvres proches » est un ENFANT poussé de cette vue : le bouton
        // de retour natif ramène ainsi dans « Affinités », et non dans la
        // sidebar. `isPresented:` + un `Binding<Bool>` dérivé de `procheDe`,
        // pas `.navigationDestination(item:)` (essayé, peu fiable ici).
        .navigationDestination(isPresented: procheDePresente) {
            if let source = procheDe { vueOeuvresProches(de: source) }
        }
    }

    // MARK: Contenu défilant — réglages, bandeaux, familles

    private var contenuDefilant: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id(ancreHaut)
                VStack(alignment: .leading, spacing: 20) {
                    reglages
                    if let b = bilan, b.aCalculer > 0 { bandeauAAnalyser(b) }
                    sectionsFamilles
                }
                .padding(16)
            }
            .retourEnHaut(visible: $boutonHautVisible) {
                withAnimation { proxy.scrollTo(ancreHaut, anchor: .top) }
            }
        }
    }

    // MARK: « Œuvres proches » — écran enfant, poussé par `.navigationDestination`

    /// Reprend uniquement « Correspondances » (le curseur influence le
    /// classement de `Regroupement.proches`) — ni « Familles » ni « Genre »,
    /// sans objet une fois qu'on regarde les œuvres proches d'une seule
    /// œuvre. Le retour se fait par le bouton natif de navigation, plus
    /// besoin d'un bouton « Familles » posé dans le contenu.
    private func vueOeuvresProches(de source: Oeuvre) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                blocReglage(titre: "Correspondances") {
                    curseur(finGauche: "Couleurs", finDroite: "Style",
                            valeur: $poidsCouleur, plage: 0...1)
                }
                sectionProches(de: source)
            }
            .padding(16)
        }
        .background(Color.cremeFond)
        .navigationTitle("Œuvres proches")
    }

    // MARK: Les familles

    private var resultat: Regroupement.Resultat? {
        guard let matrices, !signatures.isEmpty else { return nil }
        return Regroupement.grouper(oeuvres: lot, signatures: signatures,
                                    matrices: matrices,
                                    poidsCouleur: Float(poidsCouleur),
                                    seuil: Float(seuil),
                                    genres: genres,
                                    memeGenreSeulement: memeGenre)
    }

    @ViewBuilder
    private var sectionsFamilles: some View {
        if let r = resultat {
            if r.groupes.isEmpty {
                Text("Aucune famille à ce réglage. Élargissez le curseur « Familles ».")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(r.groupes.enumerated()), id: \.element.id) { rang, groupe in
                sectionFamille(id: groupe.id, titre: "Famille \(rang + 1)",
                        sousTitre: "\(groupe.oeuvres.count) œuvres · \(groupe.caractere)",
                        palette: groupe.palette,
                        oeuvres: groupe.oeuvres)
            }
            if !r.isolees.isEmpty {
                sectionFamille(id: -1, titre: "À part",
                        sousTitre: "\(r.isolees.count) œuvres qui ne rejoignent "
                                 + "aucune famille à ce réglage",
                        palette: [],
                        oeuvres: r.isolees)
            }
        }
    }

    // MARK: Les œuvres proches d'une œuvre

    @ViewBuilder
    private func sectionProches(de source: Oeuvre) -> some View {
        let index = lot.firstIndex { $0.id == source.id }
        if let index, let matrices {
            let proches = Regroupement.proches(de: index, parmi: lot,
                                               matrices: matrices,
                                               poidsCouleur: Float(poidsCouleur),
                                               combien: nbProches)
            VStack(alignment: .leading, spacing: 14) {
                section(titre: "Référence",
                        sousTitre: Regroupement.caractere(de: signatures[index]),
                        palette: signatures[index].palette,
                        oeuvres: [source])
                section(titre: "Les plus proches",
                        sousTitre: "\(proches.count) œuvres, de la plus "
                                 + "ressemblante à la moins",
                        palette: [],
                        oeuvres: proches.map(\.oeuvre))
            }
        }
    }

    // MARK: Une section (en-tête + grille)

    private func section(titre: String, sousTitre: String,
                         palette: [TeinteDominante], oeuvres: [Oeuvre]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(titre).font(.headline)
                Spacer()
                if !palette.isEmpty { rubanPalette(palette) }
            }
            Text(sousTitre)
                .font(.footnote)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)],
                      spacing: 16) {
                ForEach(oeuvres) { o in carte(o) }
            }
        }
    }

    /// Variante COLLAPSABLE de `section`, réservée au classement par
    /// famille (« Famille N » et « À part ») — pas à « Point de départ »/
    /// « Les plus proches », qui n'en sont pas un.
    private func sectionFamille(id: Int, titre: String, sousTitre: String,
                                palette: [TeinteDominante], oeuvres: [Oeuvre]) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { !famillesFermees.contains(id) },
            set: { ouvert in
                if ouvert { famillesFermees.remove(id) } else { famillesFermees.insert(id) }
            })) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)],
                      spacing: 16) {
                ForEach(oeuvres) { o in carte(o) }
            }
            .padding(.top, 8)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titre).font(.headline)
                    Text(sousTitre).font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
                if !palette.isEmpty { rubanPalette(palette) }
            }
        }
    }

    private func rubanPalette(_ palette: [TeinteDominante]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(palette.enumerated()), id: \.offset) { _, teinte in
                Color(red: Double(teinte.r), green: Double(teinte.v),
                      blue: Double(teinte.b))
                    .frame(width: max(8, CGFloat(teinte.poids) * 70))
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.filetVignette, lineWidth: 1))
    }

    // MARK: Une vignette

    /// **Plus de visionneuse, plus de menu contextuel.** Après plusieurs
    /// essais infructueux pour fiabiliser la poussée d'« Œuvres proches »
    /// depuis un `.contextMenu` (délai avant mutation d'état,
    /// `NavigationStack` propre, `.navigationDestination(item:)` puis
    /// `(isPresented:)`…) — sans pouvoir vérifier sur un appareil réel —, la
    /// fonction visionneuse est retirée des deux vues Affinités et le tap
    /// simple sur une vignette ouvre directement « Œuvres proches » : plus
    /// aucun geste à distinguer, plus aucune animation de menu à attendre.
    private func carte(_ o: Oeuvre) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Color.gray.opacity(0.12)
                VignetteCacheeFlexible(nom: o.photoNom, coteSource: 320,
                                       preserverRatio: true)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                // Intitulé puis valeur — même présentation que la vignette
                // de Réserve du Catalogue (`VueGalerie.carte`) : le libellé
                // du champ d'abord, en gris, sa valeur ensuite. Pas le
                // genre, qui n'a rien à faire sous une vignette de
                // rapprochement par style et couleurs.
                Text(rangementVignette(o).intitule)
                    .font(.subheadline)
                    .foregroundStyle(Color.texteLegende.opacity(0.6))
                    .lineLimit(1)
                Text(rangementVignette(o).valeur)
                    .font(.subheadline)
                    .foregroundStyle(Color.texteLegende)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.fondLegende)
        }
        // Mêmes valeurs que `VueGalerie.carte` (Catalogue) : coin arrondi,
        // marge interne et ombre identiques.
        .background(Color.fondLegende)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.filetVignette, lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { procheDe = o }
    }

    // MARK: Réglages

    /// Trois blocs DISTINCTS, chacun son propre en-tête (hors carte) et sa
    /// propre cellule (carte `fondLegende`) — plus un seul grand bloc
    /// englobant les trois réglages.
    private var reglages: some View {
        // Cette vue (contenuDefilant) est désormais la racine « Affinités »
        // uniquement — « Œuvres proches » est un écran enfant séparé
        // (`vueOeuvresProches`) — donc plus besoin de masquer Familles/Genre
        // ici : on n'y arrive jamais avec `procheDe` non nul.
        VStack(alignment: .leading, spacing: 16) {
            blocReglage(titre: "Correspondances") {
                curseur(finGauche: "Couleurs", finDroite: "Style",
                        valeur: $poidsCouleur, plage: 0...1)
            }
            blocReglage(titre: "Familles") {
                curseur(finGauche: "Larges", finDroite: "Serrées",
                        valeur: Binding(get: { 0.55 - seuil }, set: { seuil = 0.55 - $0 }),
                        plage: 0...0.42)
            }
            // Pas d'en-tête ici : contrairement aux deux curseurs, le
            // libellé du bascule dit déjà lui-même ce qu'il règle.
            Toggle("Genre", isOn: $memeGenre)
                .font(.subheadline)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.fondLegende))
        }
    }

    /// Un bloc de réglage : en-tête simple au-dessus, cellule `fondLegende`
    /// en dessous — même patron que les en-têtes de sous-groupe de la
    /// sidebar (« Genres », « Modes de vente »), pas un `Text` quelconque.
    private func blocReglage<Contenu: View>(titre: String,
                                            @ViewBuilder contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // .footnote (13) -> .subheadline (15) -> .body (17) : deux
            // paliers de +2 pt au barème iOS, en passant par le style
            // sémantique suivant à chaque fois plutôt qu'une taille figée,
            // pour rester compatible Dynamic Type. Sans graisse imposée.
            Text(titre).font(.body).foregroundStyle(.secondary)
            contenu()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.fondLegende))
        }
    }

    /// Taille de texte alignée sur celle des vignettes de Catalogue
    /// (`.subheadline`, voir `VueGalerie.policeLegende` sur iOS). Le titre du
    /// réglage n'est plus ICI — c'est désormais l'en-tête de `blocReglage` —
    /// seul le curseur et ses deux extrémités restent, chacun sur sa ligne.
    private func curseur(finGauche: String, finDroite: String,
                         valeur: Binding<Double>, plage: ClosedRange<Double>)
        -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Slider(value: valeur, in: plage)
            // En noir, comme le libellé de la bascule « Genre » — pas en
            // gris comme l'en-tête du bloc.
            HStack {
                Text(finGauche).font(.subheadline)
                Spacer()
                Text(finDroite).font(.subheadline)
            }
        }
    }

    // MARK: Bandeaux d'information et état vide

    private func bandeauAAnalyser(_ b: AnalyseAffinites.Bilan) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(accent)
            Text("\(b.aCalculer) œuvre(s) sur \(b.avecPhoto) ne sont pas encore "
               + "analysées.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Analyser") { lancerAnalyse(toutRecalculer: false) }
                .font(.footnote)
                .disabled(analyseEnCours)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.fondLegende))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.5), lineWidth: 1))
    }

    /// Écran de progression, plein écran, pendant qu'une analyse tourne.
    /// Lit `ProgressionImport.partagee` directement — un `@Observable`
    /// partagé avec l'import de photos — donc se met à jour photo par photo
    /// SANS jamais redémarrer `preparerLot()` : rien ici ne pilote
    /// `.task(id:)`, cette vue ne fait qu'AFFICHER l'avancement.
    private var progressionEnCours: some View {
        let suivi = ProgressionImport.partagee
        return VStack(spacing: 14) {
            ProgressView(value: suivi.total > 0 ? Double(suivi.traites) / Double(suivi.total) : 0)
                .frame(maxWidth: 240)
            Text("\(suivi.libelle) \(suivi.traites) / \(suivi.total)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func etatVide(symbole: String, titre: String, detail: String,
                          bouton: String? = nil) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbole)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(titre).font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            if let bouton {
                Button(bouton) { lancerAnalyse(toutRecalculer: false) }
                    .disabled(analyseEnCours)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Barre d'outils

    @ToolbarContentBuilder
    private var contenuBarreOutils: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Analyser les œuvres manquantes") {
                    lancerAnalyse(toutRecalculer: false)
                }
                Divider()
                Button("Tout recalculer…") { confirmerToutRecalculer = true }
            } label: {
                Image(systemName: "wand.and.rays")
            }
            .disabled(analyseEnCours)
        }
    }

    // MARK: Préparation du lot — identique à la version Mac

    private var cleLot: String {
        let noms = AnalyseAffinites.lotReserve(toutes).map(\.photoNom).sorted()
        return "\(noms.count)|\(versionBanque)|" + noms.joined().hashValue.description
    }

    @MainActor
    private func preparerLot() async {
        // Déjà traité (retour d'« Œuvres proches » par le bouton natif, qui
        // fait réapparaître cette vue et relance `.task(id:)` sans que
        // `cleLot` ait changé) : rien à refaire.
        guard dernierCleLotTraite != cleLot else { return }
        defer { chargementInitial = false }
        // Laisse d'abord le fil principal terminer l'affichage de l'écran
        // (la bascule de barre d'outils sidebar -> Affinités, notamment) :
        // sans ce point de reprise, le chargement du disque qui suit
        // s'exécute dans la MÊME passe que la transition d'entrée et peut la
        // faire traîner — les boutons Importer/Prix de la sidebar restant
        // visibles un instant de trop pendant qu'elle patine.
        await Task.yield()
        let banque = BanqueSignatures.partagee
        banque.charger()

        let complet = AnalyseAffinites.lotReserve(toutes)
        bilan = AnalyseAffinites.bilan(oeuvres: complet)

        var retenues: [Oeuvre] = []
        var sigs: [SignatureOeuvre] = []
        var noms: [String] = []
        for o in complet {
            guard let s = banque.signature(pour: o.photoNom) else { continue }
            retenues.append(o)
            sigs.append(s)
            noms.append(o.photoNom)
        }

        lot = retenues
        signatures = sigs
        genres = retenues.map { Set(themesDeOeuvre($0).map { $0.lowercased() }) }
        matrices = nil
        procheDe = nil
        dernierCleLotTraite = cleLot

        guard sigs.count > 1 else { return }
        preparation = true
        matrices = await Task.detached(priority: .userInitiated) {
            MatricesAffinites.preparer(noms: noms, signatures: sigs)
        }.value
        preparation = false
    }

    // MARK: Actions

    private func lancerAnalyse(toutRecalculer: Bool) {
        guard !analyseEnCours else { return }
        analyseEnCours = true
        Task {
            let texte = await AnalyseAffinites.executerEtDecrire(
                toutes: toutes, toutRecalculer: toutRecalculer)
            analyseEnCours = false
            messageAnalyse = texte
            await preparerLot()
        }
    }

}
#endif
