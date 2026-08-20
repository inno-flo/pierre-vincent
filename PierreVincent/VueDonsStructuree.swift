#if os(iOS)
import SwiftUI
import SwiftData

/// Vue « Œuvres données » structurée pour iPhone.
///
/// Sur le modèle de la vue « Inventaire » :
///  1. un bloc récapitulatif : « Tableaux donnés » et « Dessins donnés » avec
///     leur quantité (en orange), tapables pour défiler jusqu'à la section ;
///  2. une section « Tableaux » listant les tableaux donnés ;
///  3. une section « Dessins » listant les dessins donnés.
///
/// La répartition tableaux/dessins se fait sur le champ « type »
/// (qui contient « tableau » ou « dessin »), comme dans la Synthèse.
struct VueDonsStructuree: View {
    @Query private var toutes: [Oeuvre]

    @AppStorage("modeAffichage") private var modeAffichage: String = "liste"
    @AppStorage("triGalerie") private var triGalerie: String = "prix"
    @AppStorage("triCroissant") private var triCroissant: Bool = false

    @State private var detail: Oeuvre?
    @State private var selection: Set<UUID> = []
    // Œuvre vers laquelle faire défiler la vue de fond, pour qu'elle suive la
    // navigation faite dans la fiche de détail (même mécanisme que VueiOS).
    @State private var oeuvreADefiler: UUID?

    private let ancreTableaux = "ancre-tableaux-donnes"
    private let ancreDessins  = "ancre-dessins-donnes"

    /// Tous les dons.
    private var dons: [Oeuvre] {
        toutes.filter { $0.feuille == .oeuvresDonnees }
    }

    /// Tableaux donnés (type contenant « tableau »).
    private var tableauxDonnes: [Oeuvre] {
        trier(dons.filter { $0.type.localizedCaseInsensitiveContains("tableau") })
    }

    /// Dessins donnés (type contenant « dessin »).
    private var dessinsDonnes: [Oeuvre] {
        trier(dons.filter { $0.type.localizedCaseInsensitiveContains("dessin") })
    }

    /// Icône du bouton de menu selon le critère actif.
    private var iconeMenu: String {
        triGalerie == "acheteur" ? "person" : "ruler"
    }

    /// Applique le tri choisi. Pour les dons : acheteur → destinataire,
    /// prix sans objet (retombe sur les dimensions).
    private func trier(_ liste: [Oeuvre]) -> [Oeuvre] {
        let triees: [Oeuvre]
        switch triGalerie {
        case "acheteur":
            triees = liste.sorted {
                $0.destinataire.localizedCaseInsensitiveCompare($1.destinataire) == .orderedAscending
            }
        default: // "dimensions" ou "prix" (sans objet) → tri par surface
            triees = liste.sorted {
                surfaceDimensions($0.dimensions) < surfaceDimensions($1.dimensions)
            }
        }
        return triCroissant ? triees : triees.reversed()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // --- 1. Bloc récapitulatif ---
                    recapitulatif(proxy: proxy)

                    // --- 2. Section Tableaux ---
                    titreSection("Tableaux")
                        .id(ancreTableaux)
                    contenuSection(tableauxDonnes)

                    // --- 3. Section Dessins ---
                    titreSection("Dessins")
                        .id(ancreDessins)
                    contenuSection(dessinsDonnes)
                }
                .padding(.bottom, 30)
            }
            // Suit l'œuvre consultée dans la fiche de détail.
            .onChange(of: oeuvreADefiler) { _, cible in
                guard let cible else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(cible, anchor: .center)
                    }
                }
            }
        }
        .background(Color.cremeFond)
        .navigationTitle("Œuvres données")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Button { modeAffichage = "liste" } label: {
                        Image(systemName: "list.bullet")
                            .padding(6)
                            .background(
                                Circle().fill(modeAffichage == "liste"
                                              ? Color.primary.opacity(0.12) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)

                    Button { modeAffichage = "icone" } label: {
                        Image(systemName: "square.grid.2x2")
                            .padding(6)
                            .background(
                                Circle().fill(modeAffichage == "icone"
                                              ? Color.primary.opacity(0.12) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)

                    // Tri : pour les dons, Acheteur (→ destinataire) et Dimensions.
                    Menu {
                        Button { triGalerie = "acheteur" } label: {
                            Label(triGalerie == "acheteur" ? "✓ Destinataire" : "Destinataire",
                                  systemImage: "person")
                        }
                        Button { triGalerie = "dimensions" } label: {
                            Label(triGalerie == "dimensions" ? "✓ Dimensions" : "Dimensions",
                                  systemImage: "ruler")
                        }
                    } label: {
                        Image(systemName: iconeMenu)
                    }

                    // Sens du tri (icône retournée pour le sens inverse).
                    Button {
                        triCroissant.toggle()
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .scaleEffect(x: 1, y: triCroissant ? -1 : 1)
                    }
                    .id("bouton-sens-tri")
                }
            }
        }
        .sheet(item: $detail) { o in
            DetailiOS(oeuvre: o, estFeuilleDon: true,
                      listeNavigation: tableauxDonnes + dessinsDonnes,
                      onFermeture: { derniere in
                          selection = [derniere.id]
                          oeuvreADefiler = derniere.id
                      },
                      onStabilise: { stable in
                          // Positionne la vue de fond par anticipation, pendant
                          // les pauses de navigation (avant même la fermeture).
                          selection = [stable.id]
                          oeuvreADefiler = stable.id
                      })
        }
    }

    // MARK: Récapitulatif

    private func recapitulatif(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            ligneRecap(titre: "Tableaux donnés", nombre: tableauxDonnes.count) {
                withAnimation { proxy.scrollTo(ancreTableaux, anchor: .top) }
            }
            Divider().padding(.leading, 20)
            ligneRecap(titre: "Dessins donnés", nombre: dessinsDonnes.count) {
                withAnimation { proxy.scrollTo(ancreDessins, anchor: .top) }
            }
        }
        .background(Color.fondLegende)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func ligneRecap(titre: String, nombre: Int,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(titre)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.texteLegende)
                Spacer()
                Text("\(nombre)")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.orangeInternational)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Sections

    private func titreSection(_ texte: String) -> some View {
        Text(texte)
            .font(.system(size: 24, weight: .semibold))
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func contenuSection(_ liste: [Oeuvre]) -> some View {
        if liste.isEmpty {
            Text("Aucune entrée")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
        } else if modeAffichage == "icone" {
            grilleVignettes(liste)
        } else {
            listeLignes(liste)
        }
    }

    private func grilleVignettes(_ liste: [Oeuvre]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)], spacing: 16) {
            ForEach(liste) { o in
                carte(o)
            }
        }
        .padding(.horizontal, 16)
    }

    private func carte(_ o: Oeuvre) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Color.gray.opacity(0.12)
                VignetteCacheeFlexible(nom: o.photoNom, coteSource: 240)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipped()

            VStack(alignment: .leading, spacing: 5) {
                Text(o.destinataire.isEmpty ? " " : o.destinataire)
                    .font(.headline)
                    .foregroundStyle(Color.texteLegende)
                    .lineLimit(1)
                HStack {
                    Spacer()
                    Text(o.dimensions)
                        .foregroundStyle(Color.texteLegende.opacity(0.6))
                }
                .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.fondLegende)
        }
        .background(Color.fondLegende)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.filetVignette, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 5, x: 0, y: 2)
        .contentShape(Rectangle())
        // Cible de défilement (proxy.scrollTo).
        .id(o.id)
        .onTapGesture { selection = [o.id]; detail = o }
    }

    private func listeLignes(_ liste: [Oeuvre]) -> some View {
        // Lazy : ne construit que les lignes visibles à l'écran.
        LazyVStack(spacing: 8) {
            ForEach(liste) { o in
                Button {
                    selection = [o.id]
                    detail = o
                } label: {
                    HStack(spacing: 14) {
                        VignetteCachee(nom: o.photoNom, cote: 76)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(o.destinataire.isEmpty ? "—" : o.destinataire)
                                .font(.headline).lineLimit(1)
                            if !o.dimensions.isEmpty {
                                Text(o.dimensions)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .frame(height: 92)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.fondLegende)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selection.contains(o.id)
                                          ? Color.orangeInternational : Color.clear,
                                          lineWidth: 3)
                    )
                }
                .buttonStyle(.plain)
                // Cible de défilement (proxy.scrollTo).
                .id(o.id)
            }
        }
        .padding(.horizontal, 16)
    }
}
#endif
