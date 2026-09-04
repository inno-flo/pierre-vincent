#if os(macOS)
import SwiftUI
import SwiftData

/// Rubrique « Affinités » : les œuvres de la Réserve rapprochées par leur
/// STYLE et leurs COULEURS, indépendamment ou non de leur genre.
///
/// Deux présentations dans la même vue :
/// - **les familles**, constituées d'elles-mêmes par `Regroupement` ;
/// - **les œuvres proches** d'une œuvre choisie (menu contextuel), qui répond
///   à l'autre façon de poser la question : « qu'est-ce qui va avec
///   celle-ci ? ».
///
/// Tout le calcul lourd est fait ailleurs : `CalculSignature` (une fois par
/// photo, à l'analyse) et `MatricesAffinites` (une fois par lot). Cette vue ne
/// fait que recombiner des nombres déjà prêts, ce qui rend les deux curseurs
/// instantanés.
struct VueAffinites: View {
    /// ESSAI TEMPORAIRE (voir `TestFondPage`, `Couleurs.swift`) : observé pour
    /// que la vue se redessine quand le fond de page testé change.
    @AppStorage(TestFondPage.cle) private var testFondPage = "creme"
    @Environment(\.accentRubrique) private var accent

    /// Toutes les œuvres de la base : le lot est découpé ici même
    /// (`AnalyseAffinites.lotReserve`), pour qu'il soit EXACTEMENT celui que
    /// la commande d'analyse traite. Deux découpages séparés auraient fini par
    /// diverger, et la vue aurait annoncé des œuvres non analysées qui ne le
    /// seraient jamais.
    let toutes: [Oeuvre]

    // MARK: Réglages, conservés d'une session à l'autre

    /// 0 = rapprocher sur le seul style, 1 = sur la seule gamme de couleurs.
    @AppStorage("affinitesPoidsCouleur") private var poidsCouleur = 0.5
    /// Distance maximale pour relier deux œuvres. Plus il est bas, plus les
    /// familles sont petites et serrées.
    @AppStorage("affinitesSeuil") private var seuil = 0.32
    /// Faux = les familles peuvent traverser les genres (le cas par défaut,
    /// c'est là tout l'intérêt) ; vrai = chaque famille reste dans un genre.
    @AppStorage("affinitesMemeGenre") private var memeGenre = false

    // MARK: État de travail

    @State private var lot: [Oeuvre] = []
    @State private var signatures: [SignatureOeuvre] = []
    @State private var genres: [Set<String>] = []
    @State private var matrices: MatricesAffinites?
    @State private var preparation = false
    @State private var bilan: AnalyseAffinites.Bilan?

    @State private var selection: Set<UUID> = []
    /// Œuvre dont on regarde les proches ; `nil` = on est sur les familles.
    @State private var procheDe: Oeuvre?
    /// Position dans la visionneuse ; `nil` = fermée.
    @State private var indexVisionneuse: Int?

    @State private var analyseEnCours = false
    @State private var messageAnalyse: String?
    @State private var confirmerToutRecalculer = false
    /// Compteur incrémenté à chaque analyse (voir `AnalyseAffinites`). Il
    /// entre dans `cleLot`, ce qui reconstruit les distances quand l'analyse a
    /// été lancée depuis le menu Fichier, hors de cette vue.
    @AppStorage(AnalyseAffinites.cleVersionBanque) private var versionBanque = 0

    /// Nombre d'œuvres proposées en mode « œuvres proches ».
    private let nbProches = 24

    // MARK: Corps

    var body: some View {
        contenu
            .background(Color.cremeFond)
            .safeAreaInset(edge: .top, spacing: 0) { bandeauReglages }
            .toolbar { contenuBarreOutils }
            .navigationTitle(titreCourant)
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

    @ViewBuilder
    private var contenu: some View {
        if lot.isEmpty {
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

    /// Le regroupement courant. Recalculé à chaque changement de curseur —
    /// quelques millisecondes, les distances étant déjà préparées.
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
                Text("Aucune famille à ce réglage. Élargissez le curseur "
                   + "« taille des familles ».")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            }
            ForEach(Array(r.groupes.enumerated()), id: \.element.id) { rang, groupe in
                section(titre: "Famille \(rang + 1)",
                        sousTitre: "\(groupe.oeuvres.count) œuvres · \(groupe.caractere)",
                        palette: groupe.palette,
                        oeuvres: groupe.oeuvres)
            }
            if !r.isolees.isEmpty {
                section(titre: "À part",
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
                Label("Revenir aux familles", systemImage: "chevron.left")
                    .font(.system(size: 13))
            }
            .buttonStyle(.link)

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
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(titre)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textePrincipal)
                Text(sousTitre)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if !palette.isEmpty { rubanPalette(palette) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 170),
                                         spacing: 12)],
                      spacing: 12) {
                ForEach(oeuvres) { o in carte(o) }
            }
        }
    }

    /// Les teintes dominantes de la famille, en un ruban continu dont chaque
    /// segment est large en proportion de son poids dans l'image.
    private func rubanPalette(_ palette: [TeinteDominante]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(palette.enumerated()), id: \.offset) { _, teinte in
                Color(red: Double(teinte.r), green: Double(teinte.v),
                      blue: Double(teinte.b))
                    .frame(width: max(6, CGFloat(teinte.poids) * 90))
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.filetVignette, lineWidth: 1))
    }

    // MARK: Une vignette

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

            // Légende réduite au strict nécessaire : dans cette rubrique on
            // regarde les images, le texte ne doit pas leur disputer la place.
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
            Button("Œuvres proches") {
                selection = [o.id]
                procheDe = o
            }
            Button("Ouvrir en grand") { ouvrirVisionneuse(sur: o) }
        }
    }

    // MARK: Le bandeau de réglages

    /// Les deux curseurs et l'interrupteur de genre, en tête du panneau.
    ///
    /// `safeAreaInset` et non un `VStack` : le contenu doit continuer de
    /// défiler SOUS le bandeau et sous la barre d'outils, faute de quoi les
    /// deux perdent leur translucidité (même règle que `bandeauFiltres` dans
    /// `VueFeuille`).
    private var bandeauReglages: some View {
        HStack(spacing: 20) {
            curseur(titre: "Couleur", finGauche: "Couleur", finDroite: "Style",
                    valeur: $poidsCouleur, plage: 0...1)
            curseur(titre: "Familles", finGauche: "larges", finDroite: "serrées",
                    // Le curseur va dans le sens de la LECTURE : à droite, des
                    // familles serrées, donc un seuil BAS. D'où l'inversion.
                    valeur: Binding(get: { 0.55 - seuil },
                                    set: { seuil = 0.55 - $0 }),
                    plage: 0...0.42)
            Toggle("Même genre", isOn: $memeGenre)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .help("Coché, une famille ne réunit que des œuvres partageant "
                    + "un genre. Décoché, les familles traversent les genres — "
                    + "seuls le style et les couleurs comptent.")
            Spacer()
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

    private func bandeauAAnalyser(_ b: AnalyseAffinites.Bilan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(accent)
            Text("\(b.aCalculer) œuvre(s) sur \(b.avecPhoto) ne sont pas encore "
               + "analysées : elles n'apparaissent dans aucune famille.")
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
            .help("Analyser les photos de la Réserve")
            .disabled(analyseEnCours)
        }
    }

    // MARK: Préparation du lot

    /// Ce qui identifie le lot courant. Change dès qu'une œuvre entre ou sort
    /// de la Réserve, qu'une photo est remplacée, ou qu'une signature est
    /// calculée — c'est ce qui déclenche la reconstruction des distances.
    private var cleLot: String {
        let noms = AnalyseAffinites.lotReserve(toutes).map(\.photoNom).sorted()
        return "\(noms.count)|\(versionBanque)|" + noms.joined().hashValue.description
    }

    /// Rassemble les œuvres analysées, puis prépare les distances.
    ///
    /// **La préparation est détachée** : c'est la seule étape réellement
    /// coûteuse de la vue (des centaines de milliers de paires à comparer sur
    /// des vecteurs de 768 nombres). La laisser sur le fil principal figerait
    /// l'affichage à chaque ouverture de la rubrique.
    ///
    /// **Passe d'abord par `CacheMatricesAffinites`** : la base d'images ne
    /// change pas entre deux ouvertures de la rubrique, mais `matrices` est
    /// un simple `@State`, détruit avec la vue quand on la quitte — sans ce
    /// cache, revenir sur « Affinités » refaisait ce calcul depuis zéro à
    /// chaque fois, alors que rien n'avait changé. Voir la documentation du
    /// cache dans `Affinites.swift`.
    @MainActor
    private func preparerLot() async {
        let banque = BanqueSignatures.partagee
        banque.charger()

        let complet = AnalyseAffinites.lotReserve(toutes)
        bilan = AnalyseAffinites.bilan(oeuvres: complet)

        // Seules les œuvres DÉJÀ analysées entrent dans le regroupement. Les
        // autres sont annoncées par le bandeau, pas escamotées.
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
        procheDe = nil

        guard sigs.count > 1 else { matrices = nil; return }

        let cle = cleLot
        if let enCache = CacheMatricesAffinites.partagee.pour(cle) {
            matrices = enCache
            return
        }

        matrices = nil
        preparation = true
        let calculee = await Task.detached(priority: .userInitiated) {
            MatricesAffinites.preparer(noms: noms, signatures: sigs)
        }.value
        CacheMatricesAffinites.partagee.enregistrer(calculee, pour: cle)
        matrices = calculee
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
        procheDe == nil ? "Affinités" : "Œuvres proches"
    }
}
#endif
