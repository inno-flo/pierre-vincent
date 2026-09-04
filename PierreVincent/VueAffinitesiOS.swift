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
/// - l'ouverture d'une œuvre passe par `VisionneuseOeuvres`, pas
///   `VisionneusePanneau`.
/// Un fichier commun aurait multiplié les branches `#if` sur des points où
/// les deux plateformes ne se contentent pas de varier en apparence.
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

    @State private var procheDe: Oeuvre?
    @State private var indexVisionneuse: Int?
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
        .navigationTitle(titreCourant)
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
        .overlay { visionneuse }
    }

    // MARK: Contenu défilant — réglages, bandeaux, familles

    private var contenuDefilant: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id(ancreHaut)
                VStack(alignment: .leading, spacing: 20) {
                    reglages
                    if let b = bilan, b.aCalculer > 0 { bandeauAAnalyser(b) }
                    if let source = procheDe {
                        sectionProches(de: source)
                    } else {
                        sectionsFamilles
                    }
                }
                .padding(16)
            }
            .retourEnHaut(visible: $boutonHautVisible) {
                withAnimation { proxy.scrollTo(ancreHaut, anchor: .top) }
            }
        }
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
        VStack(alignment: .leading, spacing: 14) {
            Button {
                procheDe = nil
            } label: {
                Label("Revenir aux familles", systemImage: "arrow.left.circle.fill")
                    .font(.subheadline)
            }
            .padding(.bottom, 10)

            if let index, let matrices {
                let proches = Regroupement.proches(de: index, parmi: lot,
                                                   matrices: matrices,
                                                   poidsCouleur: Float(poidsCouleur),
                                                   combien: nbProches)
                section(titre: "Point de départ",
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
                      spacing: 12) {
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
                      spacing: 12) {
                ForEach(oeuvres) { o in carte(o) }
            }
            .padding(.top, 8)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titre).font(.headline)
                    Text(sousTitre).font(.footnote).foregroundStyle(.secondary)
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

    /// **Ouverture par simple tap**, pas par le menu contextuel à aperçu
    /// (`InteractionApercu`) qu'utilisent les vignettes de Galerie ailleurs
    /// dans l'app. Ce mécanisme existe surtout pour offrir la bascule des
    /// favoris depuis l'aperçu ; sans intérêt ici. L'appui prolongé garde un
    /// rôle utile — « Voir les œuvres proches » — via un `.contextMenu`
    /// natif, plus simple qu'une vue UIKit dédiée.
    private func carte(_ o: Oeuvre) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Color.gray.opacity(0.12)
                VignetteCacheeFlexible(nom: o.photoNom, coteSource: 240,
                                       preserverRatio: true)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                // Même polices que la légende des vignettes de Catalogue
                // (`VueGalerie.carte`) : `.headline` sans sa graisse pour le
                // genre, `.subheadline` pour le rangement.
                Text(afficher(o.theme))
                    .font(.headline)
                    .fontWeight(.regular)
                    .foregroundStyle(Color.texteLegende)
                    .lineLimit(1)
                Text(rangementVignette(o).valeur)
                    .font(.subheadline)
                    .foregroundStyle(Color.texteLegende.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.fondLegende)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.filetVignette, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { ouvrirVisionneuse(sur: o) }
        .contextMenu {
            Button("Voir les œuvres proches") { procheDe = o }
        }
    }

    // MARK: Réglages

    private var reglages: some View {
        VStack(alignment: .leading, spacing: 14) {
            curseur(titre: "Correspondance", finGauche: "Couleur", finDroite: "Style",
                    valeur: $poidsCouleur, plage: 0...1)
            // « Familles » et « Même genre » n'ont de sens que pour le
            // classement par famille — sans objet une fois qu'on regarde
            // les œuvres proches d'une seule œuvre.
            if procheDe == nil {
                curseur(titre: "Familles", finGauche: "Larges", finDroite: "Serrées",
                        valeur: Binding(get: { 0.55 - seuil }, set: { seuil = 0.55 - $0 }),
                        plage: 0...0.42)
                Toggle("Même genre", isOn: $memeGenre)
                    .font(.subheadline)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.fondLegende))
    }

    /// Taille de texte alignée sur celle des vignettes de Catalogue
    /// (`.subheadline`, voir `VueGalerie.policeLegende` sur iOS).
    /// **Une ligne par élément** : le titre, puis le curseur seul (pleine
    /// largeur, sans les libellés d'extrémité collés dessus — trop à l'étroit
    /// une fois ce texte agrandi), puis les deux extrémités sur une troisième
    /// ligne, alignées à gauche et à droite.
    private func curseur(titre: String, finGauche: String, finDroite: String,
                         valeur: Binding<Double>, plage: ClosedRange<Double>)
        -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titre).font(.subheadline).foregroundStyle(.secondary)
            Slider(value: valeur, in: plage)
            HStack {
                Text(finGauche).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(finDroite).font(.subheadline).foregroundStyle(.secondary)
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

    private func ouvrirVisionneuse(sur o: Oeuvre) {
        indexVisionneuse = lot.firstIndex { $0.id == o.id }
    }

    @ViewBuilder
    private var visionneuse: some View {
        if let i = indexVisionneuse, !lot.isEmpty {
            VisionneuseOeuvres(
                oeuvres: lot,
                index: min(i, lot.count - 1),
                onNaviguer: { o in indexVisionneuse = lot.firstIndex { $0.id == o.id } },
                onFermer: { indexVisionneuse = nil })
        }
    }

    private var titreCourant: String {
        procheDe == nil ? "Affinités" : "Œuvres proches"
    }
}
#endif
