import SwiftUI
import SwiftData
import AppKit

/// Catégories affichées dans la barre latérale (sidebar).
/// L'ordre est volontaire : Œuvres en premier, Œuvres données en dernier.
enum Categorie: Hashable, CaseIterable, Identifiable {
    case oeuvres          // vue compilée, lecture seule
    case tableauxVendus
    case dessinsVendus
    case tapisVendus
    case oeuvresDonnees

    var id: Self { self }

    var titre: String {
        switch self {
        case .oeuvres:        return "Œuvres"
        case .tableauxVendus: return "Tableaux vendus"
        case .dessinsVendus:  return "Dessins vendus"
        case .tapisVendus:    return "Tapis vendus"
        case .oeuvresDonnees: return "Œuvres données"
        }
    }

    var symbole: String {
        switch self {
        case .oeuvres:        return "square.grid.2x2"
        case .tableauxVendus: return "paintpalette"
        case .dessinsVendus:  return "pencil.and.outline"
        case .tapisVendus:    return "square.grid.3x3.square"
        case .oeuvresDonnees: return "gift"
        }
    }

    /// La feuille correspondante (nil pour la vue compilée « Œuvres »).
    var feuille: Feuille? {
        switch self {
        case .oeuvres:        return nil
        case .tableauxVendus: return .tableauxVendus
        case .dessinsVendus:  return .dessinsVendus
        case .tapisVendus:    return .tapisVendus
        case .oeuvresDonnees: return .oeuvresDonnees
        }
    }

    var lectureSeule: Bool { self == .oeuvres }
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
                List(Categorie.allCases, selection: $categorie) { cat in
                    NavigationLink(value: cat) {
                        Label(cat.titre, systemImage: cat.symbole)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                // Total en euros en bas de la sidebar.
                bandeauTotal
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            // --- Zone de contenu (canvas) ---
            if let cat = categorie {
                VueFeuille(feuille: cat.feuille,
                           lectureSeule: cat.lectureSeule,
                           titre: cat.titre,
                           nbSelection: $nbSelection)
                // Un identifiant par catégorie pour repartir « propre » à chaque
                // changement de sélection (tri, sélection, etc. réinitialisés).
                .id(cat)
            } else {
                Text("Choisissez une catégorie")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Total en bas de la sidebar

    /// Nombre d'entrées et total en euros de la catégorie sélectionnée.
    private var bandeauTotal: some View {
        let cat = categorie ?? .oeuvres
        let liste: [Oeuvre]
        if let f = cat.feuille {
            liste = toutes.filter { $0.feuille == f }
        } else {
            liste = toutes
        }
        let total = liste.reduce(0.0) { $0 + $1.prix }
        let estDon = cat == .oeuvresDonnees

        return VStack(alignment: .leading, spacing: 4) {
            Text("\(liste.count) \(cat.titre.lowercased())")
                .font(.caption).foregroundStyle(.secondary)
            if nbSelection > 0 {
                Text("\(nbSelection) sélectionné\(nbSelection > 1 ? "s" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !estDon {
                Text("Total : \(formaterEuros(total))")
                    .font(.callout.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}
