import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Catégories affichées dans la barre latérale (sidebar).
/// L'ordre est volontaire : Inventaire en premier, Synthèse en dernier.
enum Categorie: Hashable, CaseIterable, Identifiable {
    case oeuvres          // vue compilée (agrège les 4 feuilles)
    case tableauxVendus
    case dessinsVendus
    case tapisVendus
    case oeuvresDonnees
    case ventesRealisees  // ventes en exposition ou aux enchères (filtre sur modeVente)
    case synthese         // tableau de bord, en dernier

    var id: Self { self }

    var titre: String {
        switch self {
        case .oeuvres:          return "Inventaire"
        case .tableauxVendus:   return "Tableaux"
        case .dessinsVendus:    return "Dessins"
        case .tapisVendus:      return "Tapis"
        case .oeuvresDonnees:   return "Dons"
        case .ventesRealisees:  return "Ventes"
        case .synthese:         return "Synthèse"
        }
    }

    var symbole: String {
        switch self {
        case .oeuvres:          return "square.grid.2x2"
        case .tableauxVendus:   return "paintpalette"
        case .dessinsVendus:    return "pencil.and.outline"
        case .tapisVendus:      return "square.grid.3x3.square"
        case .oeuvresDonnees:   return "gift"
        case .ventesRealisees:  return "person.crop.circle.fill"
        case .synthese:         return "chart.bar.doc.horizontal"
        }
    }

    /// La feuille correspondante (nil pour les vues agrégées).
    var feuille: Feuille? {
        switch self {
        case .oeuvres:          return nil
        case .tableauxVendus:   return .tableauxVendus
        case .dessinsVendus:    return .dessinsVendus
        case .tapisVendus:      return .tapisVendus
        case .oeuvresDonnees:   return .oeuvresDonnees
        case .ventesRealisees:  return nil
        case .synthese:         return nil
        }
    }

    /// Filtre sur le mode de vente (vide = aucun filtre supplémentaire).
    var modesVente: [String] {
        switch self {
        case .ventesRealisees: return ["Exposition", "Vente aux enchères"]
        default:               return []
        }
    }

    /// Valeurs possibles du champ Vendeur pour le filtre rapide (vide = menu de tri standard).
    var filtresVendeur: [String] {
        switch self {
        case .ventesRealisees: return ["Artenchères", "Drôme Enchères", "RempART"]
        default:               return []
        }
    }

    // Toutes les catégories macOS sont éditables (y compris « Œuvres » :
    // Ajouter/Modifier/Supprimer y sont possibles sur chaque entrée, seul le
    // bouton « Ajouter » reste absent faute de feuille cible unique).
    var lectureSeule: Bool { false }

    /// Vrai pour la vue tableau de bord (affichage spécifique).
    var estSynthese: Bool { self == .synthese }

    /// Catégories du bloc principal (tout sauf Synthèse et Ventes réalisées,
    /// qui sont placés dans leurs propres sections sur macOS).
    static var categoriesData: [Categorie] {
        allCases.filter { $0 != .synthese && $0 != .ventesRealisees }
    }
}

/// Vue principale : barre latérale (catégories) + zone de contenu (canvas),
/// selon le principe des Split Views de macOS.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query private var toutes: [Oeuvre]

    // Catégorie sélectionnée au lancement :
    // - iPhone : aucune (nil) pour afficher d'abord la barre latérale ;
    // - Mac : « Œuvres » pré-sélectionnée (les deux colonnes sont visibles).
    #if os(macOS)
    @State private var categorie: Categorie? = .oeuvres
    #else
    @State private var categorie: Categorie? = nil
    #endif
    // Nombre d'entrées sélectionnées dans la vue courante (remonté par VueFeuille),
    // pour l'afficher dans le bandeau bas de la sidebar.
    @State private var nbSelection: Int = 0
    // Masquage des prix (partagé iOS + Mac).
    @AppStorage("prixMasques") private var prixMasques = false
    // Intitulés de section en gras (partagé iOS + Mac).
    @AppStorage("intitulesEnGras") private var intitulesEnGras = false
    #if os(iOS)
    // Import de la base sur iPhone (depuis un fichier .pvbase via Fichiers).
    @State private var importerBaseOuvert = false
    @State private var messageImportBase: String?
    // Section qui vient d'être choisie : reste teintée un court instant
    // après la sélection (pour accompagner la transition), puis s'éteint
    // TOUTE SEULE — sans dépendre du retour à cette vue, qui n'est pas
    // fiable à observer avec NavigationSplitView (onDisappear ne se
    // déclenche pas systématiquement sur sa colonne « detail »).
    // Piloté uniquement par le changement officiel de `categorie` (aucun
    // geste personnalisé sur les lignes : un DragGesture, même en
    // simultaneousGesture, entre par moments en concurrence avec le tap
    // natif du NavigationLink et empêche la navigation par intermittence.
    @State private var categorieRecemmentChoisie: Categorie?
    @State private var tacheExtinctionSurbrillance: Task<Void, Never>?
    #endif

    var body: some View {
        NavigationSplitView {
            // --- Barre latérale ---
            VStack(spacing: 0) {
                List(selection: $categorie) {
                    #if os(iOS)
                    // Sur iPhone : trois blocs (sections) distincts.
                    Section {
                        lien(.oeuvres)
                        lien(.synthese)
                    }
                    Section(header: Text("Ventes et dons")
                        .font(.system(size: 18, weight: intitulesEnGras ? .bold : .regular))
                        .padding(.bottom, 5)) {
                        lien(.tableauxVendus)
                        lien(.dessinsVendus)
                        lien(.tapisVendus)
                        lien(.oeuvresDonnees)
                    }
                    Section(header: Text("Expositions et enchères")
                        .font(.system(size: 18, weight: intitulesEnGras ? .bold : .regular))
                        .padding(.bottom, 5)) {
                        lien(.ventesRealisees)
                    }
                    #else
                    // Sur Mac : même organisation que la sidebar iOS.
                    Section {
                        lien(.oeuvres)
                            .listRowSeparator(.hidden)
                        lien(.synthese)
                            .listRowSeparator(.hidden)
                    }
                    Section(header: Text("Ventes et dons")
                        // Aucune police imposée : `listStyle(.sidebar)` fournit
                        // lui-même l'apparence standard des en-têtes de section
                        // sur macOS (petit corps, gris) — c'est la convention
                        // Apple. Forcer une taille (14 pt auparavant) l'écrasait
                        // et donnait des intitulés bien trop gros.
                        // Seule la graisse reste pilotable par le bouton « G ».
                        .fontWeight(intitulesEnGras ? .bold : nil)
                        // Gris, comme les en-têtes de Mail. Nécessaire car le
                        // .foregroundStyle(Color.textePrincipal) posé sur toute
                        // la hiérarchie de ContentView écrase sinon le gris
                        // fourni par défaut avec listStyle(.sidebar).
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 5)) {
                        lien(.tableauxVendus)
                            .listRowSeparator(.hidden)
                        lien(.dessinsVendus)
                            .listRowSeparator(.hidden)
                        lien(.tapisVendus)
                            .listRowSeparator(.hidden)
                        lien(.oeuvresDonnees)
                            .listRowSeparator(.hidden)
                    }
                    Section(header: Text("Expositions et enchères")
                        // Aucune police imposée : `listStyle(.sidebar)` fournit
                        // lui-même l'apparence standard des en-têtes de section
                        // sur macOS (petit corps, gris) — c'est la convention
                        // Apple. Forcer une taille (14 pt auparavant) l'écrasait
                        // et donnait des intitulés bien trop gros.
                        // Seule la graisse reste pilotable par le bouton « G ».
                        .fontWeight(intitulesEnGras ? .bold : nil)
                        // Gris, comme les en-têtes de Mail. Nécessaire car le
                        // .foregroundStyle(Color.textePrincipal) posé sur toute
                        // la hiérarchie de ContentView écrase sinon le gris
                        // fourni par défaut avec listStyle(.sidebar).
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 5)) {
                        lien(.ventesRealisees)
                            .listRowSeparator(.hidden)
                    }
                    #endif
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.cremeFond)
                // Déclenché uniquement par la sélection officielle
                // (fiable), jamais par un geste personnalisé sur les
                // lignes : voir la remarque sur categorieRecemmentChoisie.
                .onChange(of: categorie) { _, nouvelle in
                    guard let nouvelle else { return }
                    categorieRecemmentChoisie = nouvelle
                    // Réarme le minuteur d'extinction à chaque sélection.
                    tacheExtinctionSurbrillance?.cancel()
                    tacheExtinctionSurbrillance = Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)   // 0,4 s
                        if !Task.isCancelled { categorieRecemmentChoisie = nil }
                    }
                }
                #else
                .listStyle(.sidebar)
                // Couleur de sélection des rubriques : marron au lieu du bleu.
                // `.tint()` n'a AUCUN effet sur la surbrillance d'une List en
                // style sidebar (essayé, sans résultat) : on désactive la
                // surbrillance système sur le NSOutlineView et on peint le fond
                // nous-mêmes via .listRowBackground dans lien().
                .background(DesactiveSurbrillanceSidebar())
                // ↑↓ : ni onKeyPress (SwiftUI capte avant AppKit sans traiter),
                // ni repli sur le natif (le premier répondant ne suit pas les
                // clics de façon fiable ici). On passe par un capteur NSEvent
                // au niveau fenêtre, actif seulement quand la zone clavier est
                // la sidebar — voir ZoneClavier dans CaptureEspace.swift.
                .background(
                    CaptureFleches(zone: ZoneClavier.sidebar) { delta in
                        naviguerSidebar(delta: delta)
                    }
                )
                // Choisir une rubrique rend la main au clavier à la sidebar.
                .onChange(of: categorie) { _, nouvelle in
                    if nouvelle != nil { ZoneClavier.definir(ZoneClavier.sidebar) }
                }
                // ←→ ne sont pas consommées par NSOutlineView.
                .onKeyPress(.rightArrow) {
                    // Déplace le focus vers la zone de contenu (colonne détail).
                    NSApp.keyWindow?.selectNextKeyView(nil)
                    return .handled
                }
                #endif

                // Un simple filet, puis les pastilles de choix de thème.
                Divider()
                barreThemes
            }
            #if os(iOS)
            // Fond de toute la colonne (y compris bas et barre de thèmes).
            .background(Color.cremeFond)
            #endif
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
            #if os(iOS)
            // Pas d'intitulé pour la vue principale (liste des catégories) sur
            // iPhone : le mode grand format est conservé (chaîne vide) pour
            // garder le même espace de mise en page que les autres vues.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.large)
            // Bouton d'import de la base (fichier .pvbase reçu du Mac).
            .toolbar {
                // Import en premier, puis œil (masquage des prix).
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        importerBaseOuvert = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        prixMasques.toggle()
                    } label: {
                        Image(systemName: prixMasques ? "eye.slash" : "eye")
                    }
                }
            }
            // Sélecteur de fichier via l'app Fichiers (iCloud Drive inclus).
            .fileImporter(
                isPresented: $importerBaseOuvert,
                allowedContentTypes: [UTType.data],
                allowsMultipleSelection: false
            ) { resultat in
                gererImportBase(resultat)
            }
            .alert("Import de la base", isPresented: Binding(
                get: { messageImportBase != nil },
                set: { if !$0 { messageImportBase = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(messageImportBase ?? "") }
            #endif
        } detail: {
            // --- Zone de contenu (canvas) ---
            if let cat = categorie {
                if cat.estSynthese {
                    VueSynthese(toutes: toutes)
                } else {
                    #if os(macOS)
                    // Interface Mac complète (édition, exports, etc.).
                    VueFeuille(feuille: cat.feuille,
                               lectureSeule: cat.lectureSeule,
                               titre: cat.titre,
                               modesVente: cat.modesVente,
                               nbSelection: $nbSelection)
                    .id(cat)
                    #else
                    // Interface iPhone/iPad de consultation (lecture seule).
                    // La vue « Œuvres » a une présentation structurée
                    // (récapitulatif + sections Ventes et Dons).
                    if cat == .oeuvres {
                        VueOeuvresStructuree()
                            .id(cat)
                    } else if cat == .ventesRealisees {
                        VueOeuvresStructuree(modesVente: cat.modesVente,
                                             filtresVendeur: cat.filtresVendeur)
                            .id(cat)
                    } else if cat == .oeuvresDonnees {
                        VueDonsStructuree()
                            .id(cat)
                    } else {
                        VueiOS(feuille: cat.feuille, titre: cat.titre,
                               modesVente: cat.modesVente,
                               filtresVendeur: cat.filtresVendeur)
                            .id(cat)
                    }
                    #endif
                }
            } else {
                Text("Choisissez une catégorie")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            // Nettoyage des photos orphelines au démarrage : on retire du dossier
            // Photos les fichiers qui ne sont plus liés à aucune entrée (restes
            // de suppressions passées). Sans risque ici car l'historique
            // d'annulation est vide au lancement.
            let nomsUtilises = Set(toutes.map { $0.photoNom }.filter { !$0.isEmpty })
            PhotoStore.nettoyerPhotosOrphelines(nomsUtilises: nomsUtilises)

            // Données de TEST (développement) : remplit la base si elle est
            // vide, pour visualiser l'interface. Ne s'active jamais si des
            // données existent déjà, donc sans risque pour de vraies données.
            DonneesTest.genererSiVide(context: context)
        }
        #if os(iOS)
        .detecteSecoussePourPrix()
        #endif
        // Couleur de texte par défaut suivant le thème.
        .foregroundStyle(Color.textePrincipal)
        #if os(iOS)
        // Garde la barre de navigation transparente pour laisser voir le fond
        // coloré du thème derrière ; les titres suivent la couleur système.
        .apparenceTitresNavigation()
        #endif
        // NB : plus de `.id(themeApp)` ici. Ce modificateur ne servait qu'à
        // recréer toute la hiérarchie au changement de thème pour relire les
        // couleurs. Le thème ne changeant plus à l'exécution (sélecteur
        // supprimé), il était inutile — et il remettait à zéro l'état de
        // focus clavier au passage (@FocusState), ce qui faisait repasser la
        // sélection de la liste en bleu et perturbait la navigation ↑↓.
    }

    #if os(macOS)
    // MARK: Navigation clavier de la sidebar (macOS)

    /// Ordre d'affichage des rubriques, pour la navigation ↑↓.
    private var categoriesSidebar: [Categorie] {
        [.oeuvres, .synthese,
         .tableauxVendus, .dessinsVendus, .tapisVendus, .oeuvresDonnees,
         .ventesRealisees]
    }

    /// Déplace la rubrique sélectionnée de `delta` (−1 = ↑, +1 = ↓).
    private func naviguerSidebar(delta: Int) {
        guard let courante = categorie,
              let idx = categoriesSidebar.firstIndex(of: courante) else {
            categorie = delta > 0 ? categoriesSidebar.first : categoriesSidebar.last
            return
        }
        let nouveau = idx + delta
        guard nouveau >= 0, nouveau < categoriesSidebar.count else { return }
        categorie = categoriesSidebar[nouveau]
    }
    #endif

    // MARK: Compteurs pour les pastilles de sous-rubriques (macOS)

    /// Nombre d'œuvres pour une sous-rubrique de la sidebar (nil = pas de pastille).
    private func compteurPourCategorie(_ cat: Categorie) -> Int? {
        switch cat {
        case .oeuvres:
            return toutes.count
        case .tableauxVendus:
            return toutes.filter { $0.feuille == .tableauxVendus }.count
        case .dessinsVendus:
            return toutes.filter { $0.feuille == .dessinsVendus }.count
        case .tapisVendus:
            return toutes.filter { $0.feuille == .tapisVendus }.count
        case .oeuvresDonnees:
            return toutes.filter { $0.feuille == .oeuvresDonnees }.count
        case .ventesRealisees:
            return toutes.filter {
                Categorie.ventesRealisees.modesVente.contains($0.modeVente)
            }.count
        default:
            return nil
        }
    }

    // MARK: Barre de sélection du thème (bas de la sidebar)

    /// Bas de la barre latérale. Le sélecteur de thème (pastilles crème et
    /// gris) a été supprimé : l'app a un seul thème, crème. Il ne reste que
    /// le bouton « G » (intitulés de section en gras).
    private var barreThemes: some View {
        HStack(spacing: 10) {
            boutonGras
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var boutonGras: some View {
        Button {
            intitulesEnGras.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle().strokeBorder(
                            intitulesEnGras ? Color.orangeInternational : Color.gray.opacity(0.4),
                            lineWidth: intitulesEnGras ? 2.5 : 1)
                    )
                Text("G")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(intitulesEnGras ? Color.orangeInternational : Color.gray.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Lien de catégorie (barre latérale)

    #if os(iOS)
    /// Lit le fichier .pvbase sélectionné et remplace la base locale.
    private func gererImportBase(_ resultat: Result<[URL], Error>) {
        switch resultat {
        case .failure(let e):
            messageImportBase = "Échec : \(e.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            // Accès sécurisé au fichier (hors du bac à sable de l'app).
            let acces = url.startAccessingSecurityScopedResource()
            defer { if acces { url.stopAccessingSecurityScopedResource() } }
            do {
                let donnees = try Data(contentsOf: url)
                let r = EchangeBase.importerEnRemplacant(donnees: donnees, context: context)
                if let err = r.erreur {
                    messageImportBase = "Échec : \(err)"
                } else {
                    messageImportBase = "\(r.importees) œuvre(s) importée(s)."
                }
            } catch {
                messageImportBase = "Impossible de lire le fichier : \(error.localizedDescription)"
            }
        }
    }
    #endif

    /// Un lien de navigation vers une catégorie, avec son icône.
    /// Sur Mac, l'icône passe en blanc quand la catégorie est sélectionnée ;
    /// ailleurs (et sur iPhone), elle reste orange.
    private func lien(_ cat: Categorie) -> some View {
        NavigationLink(value: cat) {
            #if os(macOS)
            // Sur Mac : HStack personnalisé pour pouvoir placer la pastille à droite.
            HStack(spacing: 6) {
                Image(systemName: cat.symbole)
                    .foregroundStyle(categorie == cat
                                     ? Color.texteSelectionSidebarMac
                                     : Color.orangeInternational)
                // Rubrique sélectionnée : libellé gras sur le fond marron —
                // noir en mode clair, blanc en mode sombre (le marron y est
                // assombri). Voir Color.texteSelectionSidebarMac.
                // 13 pt = NSFont.systemFontSize, la taille standard d'un
                // libellé de sidebar sur macOS (les en-têtes de section, eux,
                // sont à 11 pt : ils doivent rester PLUS PETITS que les
                // libellés qu'ils regroupent).
                Text(cat.titre)
                    .font(.system(size: 13))
                    .fontWeight(categorie == cat ? .bold : .regular)
                    .foregroundStyle(categorie == cat
                                     ? Color.texteSelectionSidebarMac
                                     : Color.textePrincipal)
                if let n = compteurPourCategorie(cat) {
                    Spacer()
                    Text("\(n)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orangeInternational, in: Capsule())
                }
            }
            #else
            Label {
                Text(cat.titre)
            } icon: {
                Image(systemName: cat.symbole)
                    .foregroundStyle(Color.orangeInternational)
            }
            #endif
        }
        #if os(iOS)
        // Fond de cellule suivant le thème (blanc en clair, gris en sombre),
        // avec une teinte plus soutenue juste après la sélection (voir
        // categorieRecemmentChoisie, piloté par .onChange(of: categorie)
        // sur la liste). Aucun geste personnalisé ici : c'était la source
        // d'un bug de navigation aléatoire (tap sans effet), même avec
        // simultaneousGesture.
        .listRowBackground(
            categorieRecemmentChoisie == cat
                ? Color.fondCelluleSidebarSelectionnee : Color.fondCelluleSidebar)
        .animation(nil, value: categorieRecemmentChoisie)
        #else
        // Surbrillance de la rubrique sélectionnée, peinte par nous : la
        // surbrillance système (bleue) est désactivée sur le NSOutlineView,
        // voir DesactiveSurbrillanceSidebar.
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(categorie == cat ? Color.fondSelectionSidebarMac : Color.clear)
                .padding(.horizontal, 4)
        )
        #endif
    }

    // MARK: Total en bas de la sidebar

    /// Nombre d'entrées et total en euros de la catégorie sélectionnée.
    @ViewBuilder
    private var bandeauTotal: some View {
        let cat = categorie ?? .oeuvres
        if cat.estSynthese {
            // Pas de total pertinent pour le tableau de bord : rien à afficher.
            EmptyView()
        } else {
            // Nombre total d'œuvres vendues : tableaux + dessins + tapis.
            let nbVendues = toutes.filter {
                $0.feuille == .tableauxVendus
                || $0.feuille == .dessinsVendus
                || $0.feuille == .tapisVendus
            }.count

            // Nombre d'œuvres données.
            let nbDonnees = toutes.filter { $0.feuille == .oeuvresDonnees }.count

            HStack(alignment: .top, spacing: 28) {
                // Groupe 1 : œuvres vendues.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Œuvres vendues")
                        .font(.system(size: 14, weight: .bold))
                    Text("\(nbVendues)")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(red: 1.0, green: 0.31, blue: 0.0))
                }

                // Groupe 2 : œuvres données (même style et couleur).
                VStack(alignment: .leading, spacing: 4) {
                    Text("Œuvres données")
                        .font(.system(size: 14, weight: .bold))
                    Text("\(nbDonnees)")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(red: 1.0, green: 0.31, blue: 0.0))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Décalage à gauche pour aligner le texte avec les icônes des blocs.
            // La position des icônes diffère entre Mac et iPhone.
            #if os(macOS)
            .padding(.leading, 20).padding(.trailing, 12).padding(.vertical, 10)
            #else
            .padding(.leading, 40).padding(.trailing, 12).padding(.vertical, 10)
            #endif
        }
    }
}

#if os(iOS)
import UIKit

/// Modificateur qui garde la barre de navigation iOS transparente (pour laisser
/// voir le fond coloré du thème) tout en laissant les titres suivre la couleur
/// système (noir en mode Clair, blanc en mode Sombre — automatique).
private struct ApparenceTitresNavigation: ViewModifier {
    func body(content: Content) -> some View {
        content.onAppear { appliquer() }
    }

    private func appliquer() {
        let apparence = UINavigationBarAppearance()
        // Fond transparent : on laisse voir le fond coloré de l'app derrière.
        apparence.configureWithTransparentBackground()
        // Titres en couleur système (label = noir en Clair, blanc en Sombre).
        apparence.titleTextAttributes = [.foregroundColor: UIColor.label]
        apparence.largeTitleTextAttributes = [.foregroundColor: UIColor.label]

        // On applique aux trois états de la barre pour couvrir tous les cas.
        UINavigationBar.appearance().standardAppearance = apparence
        UINavigationBar.appearance().scrollEdgeAppearance = apparence
        UINavigationBar.appearance().compactAppearance = apparence
    }
}

extension View {
    /// Garde la barre de navigation transparente, titres en couleur système.
    func apparenceTitresNavigation() -> some View {
        modifier(ApparenceTitresNavigation())
    }
}
#endif

#if os(macOS)
/// Désactive la surbrillance de sélection **système** (le bleu) sur le
/// `NSOutlineView` de la sidebar, pour que la teinte marron peinte par
/// `.listRowBackground` soit seule visible.
///
/// Nécessaire parce que `.tint()` sur une `List` en style sidebar n'a aucun
/// effet sur cette surbrillance (essayé, sans résultat).
struct DesactiveSurbrillanceSidebar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Différé : au moment de la mise à jour SwiftUI, la vue n'est pas
        // forcément encore rattachée à sa fenêtre.
        DispatchQueue.main.async {
            guard let racine = nsView.window?.contentView,
                  let outline = Self.outlineView(dans: racine) else { return }
            if outline.selectionHighlightStyle != .none {
                outline.selectionHighlightStyle = .none
            }
        }
    }

    /// Cherche en profondeur le `NSOutlineView` de la sidebar. Le `Table` du
    /// panneau de contenu est une `NSTableView` simple : aucun risque de
    /// confusion, `NSOutlineView` étant plus spécifique.
    private static func outlineView(dans vue: NSView) -> NSOutlineView? {
        if let o = vue as? NSOutlineView { return o }
        for sous in vue.subviews {
            if let o = outlineView(dans: sous) { return o }
        }
        return nil
    }
}
#endif
