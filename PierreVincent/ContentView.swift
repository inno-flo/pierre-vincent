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
    case reserveInventaire // Réserve : toutes les œuvres encore détenues
    case reserveDessins   // Réserve : dessins encore disponibles
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
        case .reserveInventaire: return "Inventaire"
        case .reserveDessins:   return "Dessins"
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
        case .reserveInventaire: return "square.grid.2x2"
        case .reserveDessins:   return "pencil.and.outline"
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
        // Vue agrégée, comme l'Inventaire de Ventes et dons : toutes feuilles.
        case .reserveInventaire: return nil
        // Même feuille que « Dessins » de Ventes et dons : les deux rubriques
        // parlent des mêmes œuvres, seul le statut les sépare.
        case .reserveDessins:   return .dessinsVendus
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

    /// Statuts recensés par la rubrique.
    ///
    /// Par défaut, ceux de « Ventes et dons » — les œuvres sorties du fonds.
    /// Les rubriques de la **Réserve** recensent au contraire les œuvres
    /// encore détenues.
    var statuts: [String] {
        switch self {
        case .reserveInventaire, .reserveDessins:
            return ["Disponible", "À garder"]
        default:
            return Array(statutsVentesEtDons)
        }
    }

    /// Filtre sur le champ Type (vide = aucun filtre).
    /// Comparaison insensible à la casse et aux espaces de bord.
    var types: [String] {
        switch self {
        case .reserveDessins: return ["Dessin"]
        default:              return []
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
    // Repères des reprises de données ponctuelles sur le champ Statut.
    // `statutVenduRempli` : première passe, ventes uniquement (déjà exécutée).
    // `statutParDefautRempli` : seconde passe, qui ajoute « Donné » aux dons.
    @AppStorage("statutVenduRempli") private var statutVenduRempli = false
    @AppStorage("statutParDefautRempli") private var statutParDefautRempli = false
    // `modeVenteDonRempli` : troisième passe, Mode de vente « Don » sur les dons.
    @AppStorage("modeVenteDonRempli") private var modeVenteDonRempli = false
    // `champsVidesRemplis` : quatrième passe, « Inconnu » partout où c'est vide.
    @AppStorage("champsVidesRemplis") private var champsVidesRemplis = false
    // TEMPORAIRE — nuance du fond de sélection de la sidebar : marron clair
    // (par défaut) ou 50 % plus foncé. Piloté par le bouton en pied de sidebar.
    @AppStorage("selectionFoncee") private var selectionFoncee = false
    // Ouverture/fermeture des blocs de la sidebar, mémorisée entre les sessions
    // (comportement des sidebars système).
    @AppStorage("blocVentesOuvert") private var blocVentesOuvert = true
    @AppStorage("blocStockOuvert") private var blocStockOuvert = true
    @AppStorage("sousBlocCategoriesOuvert") private var sousBlocCategoriesOuvert = true
    @AppStorage("sousBlocExpositionsOuvert") private var sousBlocExpositionsOuvert = true
    @AppStorage("sousBlocReserveCategoriesOuvert") private var sousBlocReserveCategoriesOuvert = true
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
                    #if os(macOS)
                    // `Section(isExpanded:)` : mécanisme standard des sidebars
                    // macOS (le triangle d'affichage de Finder ou Mail).
                    Section(isExpanded: $blocVentesOuvert) {
                        contenuVentesEtDons
                    } header: {
                        Text("Ventes et dons").font(policeGrandIntitule).fontWeight(.bold)
                    }
                    Section(isExpanded: $blocStockOuvert) {
                        contenuStock
                    } header: {
                        Text("Réserve").font(policeGrandIntitule).fontWeight(.bold)
                    }
                    #else
                    // Sur iOS, `Section(isExpanded:)` n'est honoré qu'avec
                    // `listStyle(.sidebar)` : en `.insetGrouped`, le paramètre
                    // est ignoré et la section n'est pas repliable. On passe
                    // donc par un `DisclosureGroup`, qui l'est toujours.
                    Section {
                        DisclosureGroup(isExpanded: $blocVentesOuvert) {
                            contenuVentesEtDons
                        } label: {
                            Text("Ventes et dons").font(policeGrandIntitule).fontWeight(.bold)
                        }
                    }
                    Section {
                        DisclosureGroup(isExpanded: $blocStockOuvert) {
                            contenuStock
                        } label: {
                            Text("Réserve").font(policeGrandIntitule).fontWeight(.bold)
                        }
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

                // --- Zone du bas de la sidebar ---
                // Accueille des boutons temporaires de test. A successivement
                // porté les pastilles de choix de thème, puis le bouton « G ».
                Divider()
                barreOutilsBas
            }
            #if os(iOS)
            // Fond de toute la colonne.
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
                               statuts: cat.statuts,
                               types: cat.types,
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
                               filtresVendeur: cat.filtresVendeur,
                               statuts: cat.statuts,
                               types: cat.types)
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

            // Reprise ponctuelle : renseigne le Statut par défaut — « Donné »
            // pour les dons, « Vendu » pour les autres — sur les œuvres dont il
            // est encore vide. Ne s'exécute qu'une fois et n'écrase aucune
            // saisie. Repère distinct de `statutVenduRempli` : cette première
            // reprise a déjà tourné, il faut donc un nouveau déclencheur pour
            // rattraper les dons.
            if !statutParDefautRempli {
                RepriseDonnees.remplirStatutParDefaut(context: context)
                statutParDefautRempli = true
            }

            // Reprise ponctuelle : Mode de vente « Don » sur les dons dont ce
            // champ est vide. Repère distinct, les précédents ayant déjà tourné.
            if !modeVenteDonRempli {
                RepriseDonnees.remplirModeVenteDon(context: context)
                modeVenteDonRempli = true
            }

            // Reprise ponctuelle : « Inconnu » dans tous les champs texte
            // encore vides. À faire APRÈS les reprises de statut ci-dessus,
            // qui ne remplissent que les champs vides — sinon elles ne
            // trouveraient plus rien à remplir.
            if !champsVidesRemplis {
                RepriseDonnees.remplirChampsVides(context: context)
                champsVidesRemplis = true
            }
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

    /// Raccourci : l'œuvre relève-t-elle de cette rubrique (statut + type) ?
    private func correspond(_ o: Oeuvre, a cat: Categorie) -> Bool {
        PierreVincent.correspond(o, statuts: cat.statuts, types: cat.types)
    }

    // MARK: Compteurs pour les pastilles de sous-rubriques (macOS)

    /// Nombre d'œuvres pour une sous-rubrique de la sidebar (nil = pas de pastille).
    private func compteurPourCategorie(_ cat: Categorie) -> Int? {
        // Même filtre que les vues, sinon les pastilles annonceraient des
        // nombres que l'utilisateur ne retrouverait pas à l'écran.
        let recensees = toutes.filter(estVenduOuDonne)
        switch cat {
        case .oeuvres:
            return recensees.count
        case .tableauxVendus:
            return recensees.filter { $0.feuille == .tableauxVendus }.count
        case .dessinsVendus:
            return recensees.filter { $0.feuille == .dessinsVendus }.count
        case .tapisVendus:
            return recensees.filter { $0.feuille == .tapisVendus }.count
        case .oeuvresDonnees:
            return recensees.filter { $0.feuille == .oeuvresDonnees }.count
        case .ventesRealisees:
            return recensees.filter {
                Categorie.ventesRealisees.modesVente.contains($0.modeVente)
            }.count
        case .reserveInventaire, .reserveDessins:
            // Rubriques de la Réserve : leurs propres statuts, pas `recensees`.
            return toutes.filter { correspond($0, a: cat) }.count
        default:
            return nil
        }
    }

    // MARK: Barre de sélection du thème (bas de la sidebar)

    // MARK: Zone du bas de la sidebar

    /// Conteneur de boutons temporaires, en pied de barre latérale.
    private var barreOutilsBas: some View {
        HStack(spacing: 10) {
            boutonNuanceSelection
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    /// TEMPORAIRE — bascule la nuance du fond de sélection de la sidebar entre
    /// le marron clair actuel et une version 50 % plus foncée, pour comparer
    /// les deux à l'œil. La pastille montre la nuance qui s'appliquera si on
    /// clique (donc l'autre que celle en cours).
    private var boutonNuanceSelection: some View {
        Button {
            selectionFoncee.toggle()
        } label: {
            Circle()
                .fill(Color.nuanceSelectionSidebar(foncee: !selectionFoncee))
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.gray.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(selectionFoncee
              ? "Revenir au marron clair"
              : "Passer au marron foncé")
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

    // MARK: Contenu des deux grands blocs de la sidebar
    //
    // Trois niveaux de hiérarchie, marqués par la taille ET la graisse :
    //   1. grand intitulé   .title3 + gras   (Ventes et dons, Stock)
    //   2. sous-groupe      corps + semi-gras (Catégories, Expositions…)
    //   3. libellé          corps normal      (Tableaux, Dessins…)

    /// Police des deux grands intitulés (« Ventes et dons », « Stock »).
    /// `.title3` = 15 pt sur macOS, 20 pt sur iOS : plus gros que les libellés
    /// de rubrique (13 / 17 pt) dans les deux cas, ce qui marque la hiérarchie
    /// sans sortir du barème système.
    private var policeGrandIntitule: Font { .title3 }

    @ViewBuilder
    private var contenuVentesEtDons: some View {
        lien(.oeuvres)
        lien(.synthese)
        // Sous-groupes repliables. `DisclosureGroup` et non `Section` : une
        // `List` n'accepte pas de Section imbriquée dans une Section.
        DisclosureGroup(isExpanded: $sousBlocCategoriesOuvert) {
            lien(.tableauxVendus)
            lien(.dessinsVendus)
            lien(.tapisVendus)
            lien(.oeuvresDonnees)
        } label: {
            Text("Catégories").fontWeight(.semibold)
        }
        DisclosureGroup(isExpanded: $sousBlocExpositionsOuvert) {
            lien(.ventesRealisees)
        } label: {
            Text("Expositions et enchères").fontWeight(.semibold)
        }
    }

    /// Contenu du bloc « Réserve » : les œuvres encore détenues.
    @ViewBuilder
    private var contenuStock: some View {
        lien(.reserveInventaire)
        // Même structure que « Ventes et dons » : un sous-groupe repliable
        // pour les catégories d'œuvres.
        DisclosureGroup(isExpanded: $sousBlocReserveCategoriesOuvert) {
            lien(.reserveDessins)
        } label: {
            Text("Catégories").fontWeight(.semibold)
        }
    }

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
