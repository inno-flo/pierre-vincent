import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Catégories affichées dans la barre latérale (sidebar).
/// L'ordre est volontaire : Œuvres en premier, Œuvres données en dernier.
enum Categorie: Hashable, CaseIterable, Identifiable {
    case oeuvres          // vue compilée, lecture seule
    case tableauxVendus
    case dessinsVendus
    case tapisVendus
    case oeuvresDonnees
    case synthese         // tableau de bord, en dernier

    var id: Self { self }

    var titre: String {
        switch self {
        case .oeuvres:        return "Œuvres"
        case .tableauxVendus: return "Tableaux vendus"
        case .dessinsVendus:  return "Dessins vendus"
        case .tapisVendus:    return "Tapis vendus"
        case .oeuvresDonnees: return "Dons"
        case .synthese:       return "Synthèse"
        }
    }

    var symbole: String {
        switch self {
        case .oeuvres:        return "square.grid.2x2"
        case .tableauxVendus: return "paintpalette"
        case .dessinsVendus:  return "pencil.and.outline"
        case .tapisVendus:    return "square.grid.3x3.square"
        case .oeuvresDonnees: return "gift"
        case .synthese:       return "chart.bar.doc.horizontal"
        }
    }

    /// La feuille correspondante (nil pour « Œuvres » et « Synthèse »).
    var feuille: Feuille? {
        switch self {
        case .oeuvres:        return nil
        case .tableauxVendus: return .tableauxVendus
        case .dessinsVendus:  return .dessinsVendus
        case .tapisVendus:    return .tapisVendus
        case .oeuvresDonnees: return .oeuvresDonnees
        case .synthese:       return nil
        }
    }

    var lectureSeule: Bool { self == .oeuvres }

    /// Vrai pour la vue tableau de bord (affichage spécifique).
    var estSynthese: Bool { self == .synthese }

    /// Les catégories de données (tout sauf le tableau de bord Synthèse).
    static var categoriesData: [Categorie] {
        allCases.filter { $0 != .synthese }
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
    // Thème de couleurs (partagé iOS + Mac).
    @AppStorage("themeApp") private var themeApp = "creme"
    // Masquage des prix (partagé iOS + Mac).
    @AppStorage("prixMasques") private var prixMasques = false
    #if os(iOS)
    // Import de la base sur iPhone (depuis un fichier .pvbase via Fichiers).
    @State private var importerBaseOuvert = false
    @State private var messageImportBase: String?
    #endif

    var body: some View {
        NavigationSplitView {
            // --- Barre latérale ---
            VStack(spacing: 0) {
                List(selection: $categorie) {
                    #if os(iOS)
                    // Sur iPhone : quatre blocs (sections) distincts.
                    Section {
                        lien(.oeuvres)
                    }
                    Section {
                        lien(.tableauxVendus)
                        lien(.dessinsVendus)
                        lien(.tapisVendus)
                    }
                    Section {
                        lien(.oeuvresDonnees)
                    }
                    Section {
                        lien(.synthese)
                    }
                    #else
                    // Sur Mac : liste continue avec un filet avant Synthèse.
                    ForEach(Categorie.categoriesData) { cat in
                        lien(cat)
                            .listRowSeparator(.hidden)
                    }

                    Divider()
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)

                    lien(.synthese)
                    #endif
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.cremeFond)
                #else
                .listStyle(.sidebar)
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
            // Titre de la vue principale (liste des catégories) sur iPhone,
            // en grand format pour laisser le même espace que les autres vues.
            .navigationTitle("Inventaire")
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
                               nbSelection: $nbSelection)
                    .id(cat)
                    #else
                    // Interface iPhone/iPad de consultation (lecture seule).
                    // La vue « Œuvres » a une présentation structurée
                    // (récapitulatif + sections Ventes et Dons).
                    if cat == .oeuvres {
                        VueOeuvresStructuree()
                            .id(cat)
                    } else if cat == .oeuvresDonnees {
                        VueDonsStructuree()
                            .id(cat)
                    } else {
                        VueiOS(feuille: cat.feuille, titre: cat.titre)
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
        // Recrée la hiérarchie au changement de thème (relit les couleurs).
        .id(themeApp)
    }

    // MARK: Barre de sélection du thème (bas de la sidebar)

    /// Pastilles de choix de thème. Seuls Crème et Gris sont proposés ;
    /// les thèmes vert et bleu existent encore dans le code (Couleurs.swift)
    /// mais ne sont volontairement plus exposés dans l'interface.
    private var barreThemes: some View {
        HStack(spacing: 10) {
            pastilleTheme("creme", couleur: Color(red: 0.98, green: 0.96, blue: 0.92))
            pastilleTheme("gris",  couleur: Color(red: 0.90, green: 0.93, blue: 0.94))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func pastilleTheme(_ id: String, couleur: Color) -> some View {
        Button {
            themeApp = id
        } label: {
            Circle()
                .fill(couleur)
                .frame(width: 26, height: 26)
                .overlay(
                    Circle().strokeBorder(
                        themeApp == id ? Color.orangeInternational : Color.gray.opacity(0.4),
                        lineWidth: themeApp == id ? 2.5 : 1)
                )
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
            Label {
                #if os(macOS)
                // Titre en blanc quand la ligne est sélectionnée (surlignée),
                // y compris en mode Clair où il resterait noir sinon.
                Text(cat.titre)
                    .foregroundStyle(categorie == cat ? Color.white : Color.textePrincipal)
                #else
                Text(cat.titre)
                #endif
            } icon: {
                #if os(macOS)
                Image(systemName: cat.symbole)
                    .foregroundStyle(categorie == cat ? Color.white : Color.orangeInternational)
                #else
                Image(systemName: cat.symbole)
                    .foregroundStyle(Color.orangeInternational)
                #endif
            }
        }
        #if os(iOS)
        // Fond de cellule suivant le thème (blanc en clair, gris en sombre).
        .listRowBackground(Color.fondCelluleSidebar)
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
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.31, blue: 0.0))
                }

                // Groupe 2 : œuvres données (même style et couleur).
                VStack(alignment: .leading, spacing: 4) {
                    Text("Œuvres données")
                        .font(.system(size: 14, weight: .bold))
                    Text("\(nbDonnees)")
                        .font(.system(size: 20, weight: .bold))
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
