#if os(iOS)
import SwiftUI
import SwiftData

/// Pendant iPhone de `VueAffinitesCLIP` (macOS) — mêmes raisons d'un fichier
/// séparé que `VueAffinitesiOS`/`VueAffinites` : voir l'en-tête de ce dernier,
/// y compris le choix `ScrollView` + `VStack` plutôt que `List` (revert d'un
/// essai `List(.insetGrouped)` qui fusionnait l'aperçu de plusieurs
/// vignettes lors d'un appui prolongé).
struct VueAffinitesCLIPiOS: View {
    @Environment(\.accentRubrique) private var accent

    let toutes: [Oeuvre]

    @AppStorage("affinitesClipSeuil") private var seuil = 0.14
    @AppStorage("affinitesClipMemeGenre") private var memeGenre = false
    @AppStorage(AnalyseAffinitesCLIP.cleVersionBanque) private var versionBanque = 0

    @State private var lot: [Oeuvre] = []
    @State private var signatures: [SignatureCLIP] = []
    @State private var genres: [Set<String>] = []
    @State private var matrice: MatriceCLIP?
    @State private var preparation = false
    @State private var bilan: AnalyseAffinitesCLIP.Bilan?
    @State private var modeleDisponible = true
    /// `lot` vaut `[]` avant même que `preparerLot()` ait tourné une seule
    /// fois — sans ce drapeau, l'état « Aucune œuvre à rapprocher » (pensé
    /// pour une Réserve réellement vide) s'affichait un bref instant à
    /// CHAQUE ouverture de la vue, le temps que le lot se charge.
    @State private var chargementInitial = true

    /// `cleLot` déjà traité — voir `VueAffinitesiOS.dernierCleLotTraite`.
    @State private var dernierCleLotTraite: String?
    @State private var procheDe: Oeuvre?
    /// Présentation d'« Œuvres proches (CLIP) ».
    private var procheDePresente: Binding<Bool> {
        Binding(get: { procheDe != nil },
                set: { if !$0 { procheDe = nil } })
    }
    @State private var boutonHautVisible = false
    private let ancreHaut = "ancre-haut-affinites-clip"

    @State private var analyseEnCours = false
    @State private var messageAnalyse: String?
    @State private var confirmerToutRecalculer = false
    /// Familles repliées par leur `id` (`GroupeAffiniteCLIP.id`, ou `-1`
    /// pour « À part ») — repliées à la demande, ouvertes par défaut.
    @State private var famillesFermees: Set<Int> = []

    private let nbProches = 24

    var body: some View {
        Group {
            // Priorité absolue — voir `VueAffinitesiOS`, même règle : tant
            // qu'une analyse tourne, l'écran ne montre QUE sa progression.
            if ProgressionImport.partagee.enCours {
                progressionEnCours
            } else if chargementInitial {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !modeleDisponible {
                etatVide(symbole: "exclamationmark.triangle",
                         titre: "Modèle CLIP non installé",
                         detail: "Voir PierreVincent/ModeleCLIP/README.md pour le "
                               + "télécharger.")
            } else if lot.isEmpty {
                etatVide(symbole: "photo.artframe",
                         titre: "Aucune œuvre à rapprocher",
                         detail: "La Réserve ne contient aucune œuvre avec photo.")
            } else if signatures.isEmpty && !preparation {
                etatVide(symbole: "wand.and.rays",
                         titre: "Rien n'est encore analysé",
                         detail: "L'analyse CLIP lit chaque photo une fois. Elle "
                               + "est indépendante de celle d'« Affinités ».",
                         bouton: "Analyser les \(lot.count) œuvres (CLIP)")
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
        .navigationTitle("Affinités CLIP")
        .toolbar { contenuBarreOutils }
        .task(id: cleLot) { await preparerLot() }
        .alert("Analyse des affinités (CLIP)", isPresented: Binding(
            get: { messageAnalyse != nil },
            set: { if !$0 { messageAnalyse = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(messageAnalyse ?? "") }
        .alert("Tout recalculer ?", isPresented: $confirmerToutRecalculer) {
            Button("Annuler", role: .cancel) {}
            Button("Tout recalculer") { lancerAnalyse(toutRecalculer: true) }
        } message: {
            Text("Les signatures CLIP déjà calculées seront effacées et refaites. "
               + "Celles d'« Affinités » ne sont pas concernées.")
        }
        // « Œuvres proches (CLIP) » est un ENFANT poussé de cette vue —
        // `isPresented:` + `Binding<Bool>`, pas `.navigationDestination(item:)`
        // — voir `VueAffinitesiOS.body` pour le pourquoi.
        .navigationDestination(isPresented: procheDePresente) {
            if let source = procheDe { vueOeuvresProches(de: source) }
        }
    }

    // MARK: Contenu défilant

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

    // MARK: « Œuvres proches (CLIP) » — écran enfant, poussé par `.navigationDestination`

    /// Aucun réglage : CLIP n'a qu'une seule distance, sans curseur à
    /// ajuster une fois qu'on regarde les œuvres proches d'une seule
    /// œuvre. Le retour se fait par le bouton natif de navigation.
    private func vueOeuvresProches(de source: Oeuvre) -> some View {
        ScrollView {
            sectionProches(de: source)
                .padding(16)
        }
        .background(Color.cremeFond)
        .navigationTitle("Œuvres proches (CLIP)")
    }

    // MARK: Les familles

    private var resultat: RegroupementCLIP.Resultat? {
        guard let matrice, !signatures.isEmpty else { return nil }
        return RegroupementCLIP.grouper(oeuvres: lot, matrice: matrice,
                                        seuil: Float(seuil), genres: genres,
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
                        sousTitre: "\(groupe.oeuvres.count) œuvres · cohésion "
                                 + String(format: "%.3f", groupe.cohesion),
                        oeuvres: groupe.oeuvres)
            }
            if !r.isolees.isEmpty {
                sectionFamille(id: -1, titre: "À part",
                        sousTitre: "\(r.isolees.count) œuvres qui ne rejoignent "
                                 + "aucune famille à ce réglage",
                        oeuvres: r.isolees)
            }
        }
    }

    // MARK: Les œuvres proches d'une œuvre

    @ViewBuilder
    private func sectionProches(de source: Oeuvre) -> some View {
        let index = lot.firstIndex { $0.id == source.id }
        if let index, let matrice {
            let proches = RegroupementCLIP.proches(de: index, parmi: lot,
                                                   matrice: matrice,
                                                   combien: nbProches)
            VStack(alignment: .leading, spacing: 14) {
                section(titre: "Référence", sousTitre: nil, oeuvres: [source])
                section(titre: "Les plus proches (CLIP)",
                        sousTitre: "\(proches.count) œuvres, de la plus "
                                 + "ressemblante à la moins",
                        oeuvres: proches.map(\.oeuvre))
            }
        }
    }

    // MARK: Une section (en-tête + grille)

    private func section(titre: String, sousTitre: String?, oeuvres: [Oeuvre]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titre).font(.headline)
            if let sousTitre {
                Text(sousTitre)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
                                oeuvres: [Oeuvre]) -> some View {
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
            VStack(alignment: .leading, spacing: 2) {
                Text(titre).font(.headline)
                Text(sousTitre).font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Une vignette — voir `VueAffinitesiOS.carte` : plus de
    // visionneuse ni de menu contextuel, le tap simple ouvre directement
    // « Œuvres proches (CLIP) ».

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
        // Mêmes valeurs que `VueGalerie.carte` (Catalogue) — voir
        // `VueAffinitesiOS.carte`.
        .background(Color.fondLegende)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.filetVignette, lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { procheDe = o }
    }

    // MARK: Réglages — un seul curseur : CLIP n'a qu'une distance

    /// Deux blocs DISTINCTS (Familles, Genre), même patron que la version
    /// « Affinités » — voir `VueAffinitesiOS.reglages`. Pas de bloc
    /// « Correspondances » ici : CLIP n'a qu'une seule distance.
    private var reglages: some View {
        VStack(alignment: .leading, spacing: 16) {
            blocReglage(titre: "Familles") {
                curseur(finGauche: "Larges", finDroite: "Serrées",
                        valeur: Binding(get: { 0.4 - seuil }, set: { seuil = 0.4 - $0 }),
                        plage: 0...0.35)
            }
            // Pas d'en-tête ici : contrairement au curseur, le libellé du
            // bascule dit déjà lui-même ce qu'il règle.
            Toggle("Genre", isOn: $memeGenre)
                .font(.subheadline)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.fondLegende))
            Text("Moteur : MobileCLIP-S0 (Apple, Core ML)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Un bloc de réglage : en-tête simple au-dessus, cellule `fondLegende`
    /// en dessous — voir `VueAffinitesiOS.blocReglage`.
    private func blocReglage<Contenu: View>(titre: String,
                                            @ViewBuilder contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // .footnote -> .subheadline -> .body, sans graisse imposée —
            // voir `VueAffinitesiOS.blocReglage`.
            Text(titre).font(.body).foregroundStyle(.secondary)
            contenu()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.fondLegende))
        }
    }

    /// Taille de texte alignée sur celle des vignettes de Catalogue
    /// (`.subheadline`, voir `VueGalerie.policeLegende` sur iOS). Le titre du
    /// réglage n'est plus ICI — c'est désormais l'en-tête de `blocReglage`.
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

    private func bandeauAAnalyser(_ b: AnalyseAffinitesCLIP.Bilan) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(accent)
            Text("\(b.aCalculer) œuvre(s) sur \(b.avecPhoto) ne sont pas encore "
               + "analysées (CLIP).")
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

    /// Écran de progression, plein écran — voir `VueAffinitesiOS`, même
    /// mécanisme et même `ProgressionImport` partagé (distingué à l'écran
    /// par son seul `libelle`, « Analyse CLIP » ici).
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
        // Déjà traité — voir `VueAffinitesiOS.preparerLot` : sans ce
        // garde-fou, revenir d'« Œuvres proches (CLIP) » par le bouton natif
        // relance `.task(id:)` (la vue réapparaît) même si `cleLot` n'a pas
        // changé, et tout est refait depuis zéro.
        guard dernierCleLotTraite != cleLot else { return }
        defer { chargementInitial = false }
        // Voir `VueAffinitesiOS.preparerLot` : laisse d'abord le fil
        // principal terminer la transition d'entrée (bascule de barre
        // d'outils sidebar -> Affinités CLIP) avant le travail qui suit.
        await Task.yield()
        modeleDisponible = await MoteurCLIP.shared.disponible()
        guard modeleDisponible else { return }

        let banque = BanqueSignaturesCLIP.partagee
        banque.charger()

        let complet = AnalyseAffinites.lotReserve(toutes)
        bilan = AnalyseAffinitesCLIP.bilan(oeuvres: complet)

        var retenues: [Oeuvre] = []
        var sigs: [SignatureCLIP] = []
        for o in complet {
            guard let s = banque.signatures[o.photoNom] else { continue }
            retenues.append(o)
            sigs.append(s)
        }

        lot = retenues
        signatures = sigs
        genres = retenues.map { Set(themesDeOeuvre($0).map { $0.lowercased() }) }
        matrice = nil
        procheDe = nil
        dernierCleLotTraite = cleLot

        guard sigs.count > 1 else { return }
        preparation = true
        matrice = await Task.detached(priority: .userInitiated) {
            MatriceCLIP.preparer(signatures: sigs)
        }.value
        preparation = false
    }

    // MARK: Actions

    private func lancerAnalyse(toutRecalculer: Bool) {
        guard !analyseEnCours else { return }
        analyseEnCours = true
        Task {
            let texte = await AnalyseAffinitesCLIP.executerEtDecrire(
                toutes: toutes, toutRecalculer: toutRecalculer)
            analyseEnCours = false
            messageAnalyse = texte
            await preparerLot()
        }
    }

}
#endif
