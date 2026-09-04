#if os(iOS)
import SwiftUI
import SwiftData

/// Pendant iPhone de `VueAffinitesCLIP` (macOS) — mêmes raisons d'un fichier
/// séparé que `VueAffinitesiOS`/`VueAffinites` : voir l'en-tête de ce dernier.
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

    @State private var procheDe: Oeuvre?
    @State private var indexVisionneuse: Int?
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
        .navigationTitle(titreCourant)
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
        .overlay { visionneuse }
    }

    // MARK: Contenu défilant

    /// **Un vrai `List(.insetGrouped)`** — voir `VueAffinitesiOS.contenuDefilant`,
    /// même migration et mêmes raisons : l'en-tête « Familles » devient un
    /// vrai `Section(titre)`, le même composant système que les en-têtes de
    /// bloc de la sidebar.
    private var contenuDefilant: some View {
        ScrollViewReader { proxy in
            List {
                // Aucun réglage n'a de sens pour « Oeuvres proches (CLIP) » :
                // CLIP n'a qu'une seule distance, sans curseur à ajuster une
                // fois qu'on regarde les œuvres proches d'une seule œuvre.
                //
                // L'ancre est l'IDENTITÉ de la `Section` elle-même quand
                // elle existe (voir `VueAffinitesiOS.contenuDefilant` : ni
                // ligne à part avant elle, ni première ligne dedans, les
                // deux cassant le rendu) ; sinon une simple ligne, rien
                // d'autre ne suit immédiatement avec une frontière de
                // section.
                if procheDe == nil {
                    Section("Familles") {
                        curseur(finGauche: "Larges", finDroite: "Serrées",
                                valeur: Binding(get: { 0.4 - seuil }, set: { seuil = 0.4 - $0 }),
                                plage: 0...0.35)
                    }
                    .id(ancreHaut)
                    Section {
                        Toggle("Genre", isOn: $memeGenre)
                    }
                    Text("Moteur : MobileCLIP-S0 (Apple, Core ML)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    Color.clear.frame(height: 0)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .id(ancreHaut)
                }

                if let b = bilan, b.aCalculer > 0 { bandeauAAnalyser(b) }

                if let source = procheDe {
                    sectionProches(de: source)
                } else {
                    sectionsFamilles
                }
            }
            .listStyle(.insetGrouped)
            // Voir `VueAffinitesiOS.contenuDefilant` : réduit l'écart par
            // défaut sous le titre pour retrouver celui du Catalogue.
            .contentMargins(.top, 8, for: .scrollContent)
            // Voir `VueAffinitesiOS.contenuDefilant` : sans ceci, la ligne-
            // ancre (hauteur 0 demandée) serait quand même portée à la
            // hauteur minimale système d'une ligne de `List` (~44 pt).
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .background(Color.cremeFond)
            .retourEnHaut(visible: $boutonHautVisible) {
                withAnimation { proxy.scrollTo(ancreHaut, anchor: .top) }
            }
        }
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
                    .ligneTransparente()
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
        Button {
            procheDe = nil
        } label: {
            Label("Revenir aux familles", systemImage: "arrow.left.circle.fill")
                .font(.subheadline)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 20, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)

        if let index, let matrice {
            let proches = RegroupementCLIP.proches(de: index, parmi: lot,
                                                   matrice: matrice,
                                                   combien: nbProches)
            section(titre: "Point de départ", sousTitre: nil, oeuvres: [source])
            section(titre: "Les plus proches (CLIP)",
                    sousTitre: "\(proches.count) œuvres, de la plus "
                             + "ressemblante à la moins",
                    oeuvres: proches.map(\.oeuvre))
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
        .ligneTransparente()
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
        .ligneTransparente()
    }

    // MARK: Une vignette — même choix que la version « Affinités » : tap
    // simple pour ouvrir, appui prolongé pour « Œuvres proches ».

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
                // Seul l'emplacement de stockage — pas le genre, qui n'a
                // rien à faire sous une vignette de rapprochement par style
                // et couleurs. Police alignée sur la légende du Catalogue.
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
        .onTapGesture { ouvrirVisionneuse(sur: o) }
        .contextMenu {
            Button("Voir les œuvres proches (CLIP)") { procheDe = o }
        }
    }

    // MARK: Réglages — un seul curseur : CLIP n'a qu'une distance

    /// Le curseur seul — posé DIRECTEMENT comme contenu d'un `Section` de
    /// `List` (voir `contenuDefilant`) : l'en-tête n'est plus ici, c'est
    /// désormais le titre natif du `Section`, exactement le même composant
    /// système que les en-têtes de bloc de la sidebar.
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
        .ligneTransparente()
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
        defer { chargementInitial = false }
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
        procheDe == nil ? "Affinités CLIP" : "Œuvres proches (CLIP)"
    }
}

/// `private` (donc propre à ce fichier) — voir `VueAffinitesiOS.swift`,
/// même duplication assumée, pour éviter une collision avec la copie de
/// l'autre fichier.
private extension View {
    /// Ligne de `List` sans carte ni séparateur — pour tout ce qui doit
    /// rester posé directement sur le fond crème, comme avant la migration
    /// vers `List` (seuls les réglages ont une vraie carte système).
    func ligneTransparente() -> some View {
        listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
#endif
