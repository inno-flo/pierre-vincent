#if os(iOS)
import SwiftUI
import SwiftData
import UIKit

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

    /// **Un vrai `List(.insetGrouped)`**, et non plus un `ScrollView` +
    /// `VStack` maison : les en-têtes « Correspondances »/« Familles »
    /// deviennent alors de vrais `Section(titre)` de `List` — le MÊME
    /// composant système que les grands en-têtes de bloc de la sidebar
    /// (« Réserve », « Labo »), plutôt qu'une police approchée à la main.
    /// Plus aucun écart possible entre les deux, par construction.
    ///
    /// Les familles et « Œuvres proches » restent, elles, de simples LIGNES
    /// transparentes (`.listRowBackground(Color.clear)`,
    /// `.listRowSeparator(.hidden)`) — comme avant, elles ne sont pas
    /// présentées en carte, seuls les réglages le sont.
    private var contenuDefilant: some View {
        ScrollViewReader { proxy in
            List {
                // L'ancre est l'IDENTITÉ de la `Section` elle-même, pas
                // celle d'une ligne à part : postée comme ligne AVANT la
                // première `Section`, `List` la traitait comme sa propre
                // section vide (espace inter-sections en plus du grand
                // espace sous le titre — vide anormal) ; postée comme
                // PREMIÈRE ligne DANS la `Section`, elle cassait le rendu de
                // sa carte (coin supérieur tronqué, capture du 4 sept. 2026).
                Section("Correspondances") {
                    curseur(finGauche: "Couleurs", finDroite: "Style",
                            valeur: $poidsCouleur, plage: 0...1)
                }
                .id(ancreHaut)
                // « Familles » et « Genre » n'ont de sens que pour le
                // classement par famille — sans objet une fois qu'on
                // regarde les œuvres proches d'une seule œuvre.
                if procheDe == nil {
                    Section("Familles") {
                        curseur(finGauche: "Larges", finDroite: "Serrées",
                                valeur: Binding(get: { 0.55 - seuil }, set: { seuil = 0.55 - $0 }),
                                plage: 0...0.42)
                    }
                    // Pas d'en-tête : le libellé de la bascule dit déjà ce
                    // qu'elle règle.
                    Section {
                        Toggle("Genre", isOn: $memeGenre)
                    }
                }

                if let b = bilan, b.aCalculer > 0 { bandeauAAnalyser(b) }

                if let source = procheDe {
                    sectionProches(de: source)
                } else {
                    sectionsFamilles
                }
            }
            .listStyle(.insetGrouped)
            // Un `List(.insetGrouped)` réserve par défaut un grand espace
            // sous le titre avant sa première `Section` (~35 pt). Réduit à
            // 8 pt pour retrouver l'écart du Catalogue de « Ventes et dons »
            // (`BandeauTypes.padding(.top, 8)`), pris comme référence.
            .contentMargins(.top, 8, for: .scrollContent)
            // Sans ceci, la ligne-ancre (hauteur 0 demandée) serait quand
            // même portée à la hauteur minimale système d'une ligne de
            // `List` (~44 pt), ajoutant un vide invisible au-dessus du
            // premier curseur.
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .background(Color.cremeFond)
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
                    .ligneTransparente()
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
        Button {
            procheDe = nil
        } label: {
            Label("Revenir aux familles", systemImage: "arrow.left.circle.fill")
                .font(.subheadline)
        }
        // Espace supplémentaire en bas de ligne : plus d'écart avant
        // « Point de départ » que le simple padding par défaut d'une ligne.
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 20, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)

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
        .ligneTransparente()
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
        .ligneTransparente()
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
    /// favoris depuis l'aperçu ; sans intérêt ici.
    ///
    /// **L'appui prolongé n'utilise PLUS `.contextMenu`.** Chaque famille
    /// loge sa grille de vignettes dans une SEULE ligne de `List` (voir
    /// `sectionFamille`/`section`) : un `.contextMenu` par vignette, une
    /// fois nichées ainsi, se voit attribuer par UIKit l'aperçu de TOUTE la
    /// ligne — toutes les vignettes de la famille apparaissaient alors
    /// fusionnées en une seule image au moment de l'appui (constaté à
    /// l'écran). Remplacé par un `.onLongPressGesture` direct : sans menu ni
    /// aperçu système, rien à mal attribuer.
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
        // Mêmes valeurs que `VueGalerie.carte` (Catalogue) : coin arrondi,
        // marge interne et ombre identiques — seul le contenu de la légende
        // diffère (une ligne ici, deux dans le Catalogue).
        .background(Color.fondLegende)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.filetVignette, lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { ouvrirVisionneuse(sur: o) }
        .onLongPressGesture {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            procheDe = o
        }
    }

    // MARK: Réglages

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
        .ligneTransparente()
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

/// `private` (donc propre à ce fichier) — même duplication assumée que
/// `curseur`/`section` entre les deux vues Affinités, voir l'en-tête du
/// fichier : deux copies indépendantes plutôt qu'un `extension View`
/// interne qui entrerait en collision avec celle du fichier CLIP.
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
