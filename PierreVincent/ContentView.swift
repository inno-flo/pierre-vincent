import SwiftUI
import SwiftData

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

    @State private var categorie: Categorie? = .oeuvres
    // Nombre d'entrées sélectionnées dans la vue courante (remonté par VueFeuille),
    // pour l'afficher dans le bandeau bas de la sidebar.
    @State private var nbSelection: Int = 0

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
                        NavigationLink(value: cat) {
                            Label(cat.titre, systemImage: cat.symbole)
                        }
                        .listRowSeparator(.hidden)
                    }

                    Divider()
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)

                    NavigationLink(value: Categorie.synthese) {
                        Label(Categorie.synthese.titre,
                              systemImage: Categorie.synthese.symbole)
                    }
                    #endif
                }
                .listStyle(.sidebar)

                Divider()

                // Total en euros en bas de la sidebar.
                bandeauTotal
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
            #if os(iOS)
            // Titre de la vue principale (liste des catégories) sur iPhone,
            // en grand format pour laisser le même espace que les autres vues.
            .navigationTitle("Inventaire")
            .navigationBarTitleDisplayMode(.large)
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
                    VueiOS(feuille: cat.feuille, titre: cat.titre)
                        .id(cat)
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
    }

    // MARK: Lien de catégorie (barre latérale)

    /// Un lien de navigation vers une catégorie, avec son icône.
    private func lien(_ cat: Categorie) -> some View {
        NavigationLink(value: cat) {
            Label(cat.titre, systemImage: cat.symbole)
        }
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
