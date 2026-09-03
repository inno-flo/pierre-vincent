#if os(macOS)
import SwiftUI
import SwiftData

/// Rubrique « Affinités CLIP » : le même lot d'œuvres que « Affinités »,
/// regroupé par la distance **CLIP** (MobileCLIP-S0, Apple, Core ML) au lieu
/// du moteur maison (couleur + matière + Vision).
///
/// **Volontairement une COPIE proche de `VueAffinites`, et non une vue
/// paramétrée par le moteur.** Les deux se lisent l'une à côté de l'autre —
/// littéralement, en changeant de rubrique — et une vue commune aurait
/// demandé un empilement de conditions pour des différences réelles : ici,
/// un seul curseur (pas de Couleur/Style, CLIP n'a qu'une distance) et un
/// indicateur de cohésion par famille, absent de l'autre vue. Le risque de
/// divergence entre les deux copies est accepté : c'est un banc d'essai, pas
/// une fonctionnalité appelée à vivre indéfiniment sous cette forme.
struct VueAffinitesCLIP: View {
    @AppStorage(TestFondPage.cle) private var testFondPage = "creme"
    @Environment(\.accentRubrique) private var accent

    let toutes: [Oeuvre]

    /// Distance maximale pour relier deux œuvres. Échelle DIFFÉRENTE de celle
    /// d'« Affinités » : les distances cosinus de CLIP restent, en pratique,
    /// resserrées sur une plage plus étroite que notre propre mesure — les
    /// deux curseurs ne se calibrent pas pareil, et c'est attendu.
    @AppStorage("affinitesClipSeuil") private var seuil = 0.14
    @AppStorage("affinitesClipMemeGenre") private var memeGenre = false

    @State private var lot: [Oeuvre] = []
    @State private var signatures: [SignatureCLIP] = []
    @State private var genres: [Set<String>] = []
    @State private var matrice: MatriceCLIP?
    @State private var preparation = false
    @State private var bilan: AnalyseAffinitesCLIP.Bilan?
    @State private var modeleDisponible = true

    @State private var selection: Set<UUID> = []
    @State private var procheDe: Oeuvre?
    @State private var indexVisionneuse: Int?

    @State private var analyseEnCours = false
    @State private var messageAnalyse: String?
    @State private var confirmerToutRecalculer = false

    @AppStorage(AnalyseAffinitesCLIP.cleVersionBanque) private var versionBanque = 0

    private let nbProches = 24

    var body: some View {
        contenu
            .background(Color.cremeFond)
            .safeAreaInset(edge: .top, spacing: 0) { bandeauReglages }
            .toolbar { contenuBarreOutils }
            .navigationTitle(titreCourant)
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
                   + "Celles de la rubrique « Affinités » ne sont pas concernées, "
                   + "les deux moteurs sont rangés séparément.")
            }
            .overlay { visionneuse }
    }

    @ViewBuilder
    private var contenu: some View {
        if !modeleDisponible {
            etatVide(symbole: "exclamationmark.triangle",
                     titre: "Modèle CLIP non installé",
                     detail: "Voir PierreVincent/ModeleCLIP/README.md pour le "
                           + "télécharger — un script fait tout en une commande.")
        } else if lot.isEmpty {
            etatVide(symbole: "photo.artframe",
                     titre: "Aucune œuvre à rapprocher",
                     detail: "La Réserve ne contient aucune œuvre avec photo.")
        } else if signatures.isEmpty && !preparation {
            etatVide(symbole: "wand.and.rays",
                     titre: "Rien n'est encore analysé",
                     detail: "L'analyse CLIP lit chaque photo une fois. Elle ne se "
                           + "refait pas au lancement, et est indépendante de "
                           + "celle d'« Affinités ».",
                     bouton: "Analyser les \(lot.count) œuvres (CLIP)")
        } else if preparation {
            VStack(spacing: 10) {
                ProgressView()
                Text("Comparaison des \(signatures.count) œuvres…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView { corpsDefilant.padding(16) }
        }
    }

    @ViewBuilder
    private var corpsDefilant: some View {
        LazyVStack(alignment: .leading, spacing: 28) {
            if let b = bilan, b.aCalculer > 0 {
                bandeauAAnalyser(b)
            }
            if let source = procheDe {
                sectionProches(de: source)
            } else {
                sectionsFamilles
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
                Text("Aucune famille à ce réglage. Élargissez le curseur "
                   + "« taille des familles ».")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            }
            ForEach(Array(r.groupes.enumerated()), id: \.element.id) { rang, groupe in
                section(titre: "Famille \(rang + 1)",
                        sousTitre: "\(groupe.oeuvres.count) œuvres · cohésion "
                                 + String(format: "%.3f", groupe.cohesion),
                        oeuvres: groupe.oeuvres)
            }
            if !r.isolees.isEmpty {
                section(titre: "À part",
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
        VStack(alignment: .leading, spacing: 14) {
            Button {
                procheDe = nil
            } label: {
                Label("Revenir aux familles", systemImage: "chevron.left")
                    .font(.system(size: 13))
            }
            .buttonStyle(.link)

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
    }

    // MARK: Une section (en-tête + grille)

    private func section(titre: String, sousTitre: String?, oeuvres: [Oeuvre]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(titre)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textePrincipal)
                if let sousTitre {
                    Text(sousTitre)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 170),
                                         spacing: 12)],
                      spacing: 12) {
                ForEach(oeuvres) { o in carte(o) }
            }
        }
    }

    // MARK: Une vignette — identique à celle d'« Affinités »

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

            VStack(alignment: .leading, spacing: 3) {
                Text(afficher(o.theme))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.texteLegende)
                    .lineLimit(1)
                Text(rangementVignette(o).valeur)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.texteLegende.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.fondLegende)
        }
        .overlay(RoundedRectangle(cornerRadius: 4)
            .stroke(selection.contains(o.id) ? accent : Color.filetVignette,
                    lineWidth: selection.contains(o.id) ? 3 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { ouvrirVisionneuse(sur: o) }
        .onTapGesture { selection = [o.id] }
        .contextMenu {
            Button("Œuvres proches (CLIP)…") {
                selection = [o.id]
                procheDe = o
            }
            Button("Ouvrir en grand") { ouvrirVisionneuse(sur: o) }
        }
    }

    // MARK: Bandeau de réglages — un seul curseur : pas de Couleur/Style ici

    private var bandeauReglages: some View {
        HStack(spacing: 20) {
            curseur(titre: "Familles", finGauche: "larges", finDroite: "serrées",
                    valeur: Binding(get: { 0.4 - seuil }, set: { seuil = 0.4 - $0 }),
                    plage: 0...0.35)
            Toggle("Même genre", isOn: $memeGenre)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            Spacer()
            Text("Moteur : MobileCLIP-S0 (Apple, Core ML)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func curseur(titre: String, finGauche: String, finDroite: String,
                         valeur: Binding<Double>, plage: ClosedRange<Double>)
        -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(titre)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Slider(value: valeur, in: plage) {
                EmptyView()
            } minimumValueLabel: {
                Text(finGauche).font(.system(size: 10)).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(finDroite).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .controlSize(.small)
            .frame(width: 230)
        }
    }

    // MARK: Bandeaux d'information et état vide

    private func bandeauAAnalyser(_ b: AnalyseAffinitesCLIP.Bilan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(accent)
            Text("\(b.aCalculer) œuvre(s) sur \(b.avecPhoto) ne sont pas encore "
               + "analysées (CLIP).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("Analyser") { lancerAnalyse(toutRecalculer: false) }
                .controlSize(.small)
                .disabled(analyseEnCours)
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.fondLegende))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(accent.opacity(0.5), lineWidth: 1))
    }

    private func etatVide(symbole: String, titre: String, detail: String,
                          bouton: String? = nil) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbole)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(titre).font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            if let bouton {
                Button(bouton) { lancerAnalyse(toutRecalculer: false) }
                    .disabled(analyseEnCours)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Barre d'outils

    @ToolbarContentBuilder
    private var contenuBarreOutils: some ToolbarContent {
        ToolbarSpacer(.flexible)
        ToolbarItem {
            Menu {
                Button("Analyser les œuvres manquantes") {
                    lancerAnalyse(toutRecalculer: false)
                }
                Divider()
                Button("Tout recalculer…") { confirmerToutRecalculer = true }
            } label: {
                Image(systemName: "wand.and.rays")
            }
            .help("Analyser les photos de la Réserve (CLIP)")
            .disabled(analyseEnCours)
        }
    }

    // MARK: Préparation du lot

    private var cleLot: String {
        let noms = AnalyseAffinites.lotReserve(toutes).map(\.photoNom).sorted()
        return "\(noms.count)|\(versionBanque)|" + noms.joined().hashValue.description
    }

    @MainActor
    private func preparerLot() async {
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
        selection = [o.id]
        indexVisionneuse = lot.firstIndex { $0.id == o.id }
    }

    @ViewBuilder
    private var visionneuse: some View {
        if let i = indexVisionneuse, !lot.isEmpty {
            VisionneusePanneau(
                oeuvres: lot,
                index: Binding(
                    get: { min(i, lot.count - 1) },
                    set: { nouveau in
                        indexVisionneuse = nouveau
                        selection = [lot[nouveau].id]
                    }),
                onFermer: { indexVisionneuse = nil })
        }
    }

    private var titreCourant: String {
        procheDe == nil ? "Affinités CLIP" : "Œuvres proches (CLIP)"
    }
}
#endif
