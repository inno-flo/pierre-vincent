#if os(iOS)
import SwiftUI
import SwiftData
import UIKit

/// Vue « Œuvres données » structurée pour iPhone.
///
/// Un bloc récapitulatif — « Nombre de dons » et sa quantité en orange —
/// au-dessus de la liste de TOUS les dons.
///
/// **Pas de découpage par type.** La vue séparait « Tableaux » et « Dessins »
/// en cherchant ces mots dans le champ `type`. Une œuvre dont le type disait
/// autre chose — une technique, « Inconnu » — n'entrait dans aucune des deux
/// sections et disparaissait purement et simplement : 9 dons affichés sur 53.
/// Un découpage par test d'appartenance doit toujours prévoir le reste, ou
/// n'exister qu'une fois le champ garanti fermé (voir `typesOeuvre`).
struct VueDonsStructuree: View {
    @Query private var toutes: [Oeuvre]

    @AppStorage("modeAffichage") private var modeAffichage: String = "liste"
    @AppStorage("triGalerie") private var triGalerie: String = "prix"
    @AppStorage("triCroissant") private var triCroissant: Bool = false

    @State private var detail: Oeuvre?
    // Visionneuse plein écran : position courante (nil = fermée), et moteur
    // haptique conservé puis préparé au contact — un générateur neuf déclenche
    // à froid, ce qui se ressent comme un choc mou. Même patron que `VueiOS`.
    @State private var indexVisionneuse: Int?
    // Cadres des vignettes visibles, pour que la visionneuse sache d'où
    // partir quand la transition est faite à la main.
    @State private var cadresVignettes: [UUID: CGRect] = [:]
    // Espace de la transition de zoom : la vignette pressée s'agrandit pour
    // devenir la visionneuse. C'est l'effet standard d'Apple pour une
    // présentation plein écran issue d'un élément précis.
    @Namespace private var espaceZoom


    @State private var selection: Set<UUID> = []
    // Œuvre vers laquelle faire défiler la vue de fond, pour qu'elle suive la
    // navigation faite dans la fiche de détail (même mécanisme que VueiOS).
    @State private var oeuvreADefiler: UUID?

    private let ancreDons = "ancre-dons"

    /// Tous les dons, triés.
    private var dons: [Oeuvre] {
        // Ne recense que les œuvres sorties du fonds (voir `estVenduOuDonne`) :
        // celles encore disponibles relèvent de la section « Réserve ».
        trier(toutes.filter { $0.feuille == .oeuvresDonnees }.filter(estVenduOuDonne))
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

                    // --- 2. La liste, sans découpage ---
                    // Marge haute portée ICI : elle l'était par le titre de
                    // section (`padding(.top, 24)`), disparu avec le découpage
                    // par type, et le récapitulatif s'est retrouvé collé à la
                    // première rangée. Avec les 8 pt du récapitulatif, on
                    // retrouve les 24 pt de `VueiOS`, où la grille apporte les
                    // siens depuis `VueGalerie`.
                    contenuSection(dons)
                        .padding(.top, 16)
                        .id(ancreDons)
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
        .navigationTitle("Dons")
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
        .onPreferenceChange(CadresVignettes.self) { cadresVignettes = $0 }
        .fullScreenCover(isPresented: visionneuseOuverte) { contenuVisionneuse }
        .sheet(item: $detail) { o in
            DetailiOS(oeuvre: o, estFeuilleDon: true,
                      listeNavigation: dons,
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
            ligneRecap(titre: "Nombre de dons", nombre: dons.count) {
                withAnimation { proxy.scrollTo(ancreDons, anchor: .top) }
            }
        }
        .background(Color.fondLegende)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        // Même marge basse que `recapCell` dans `VueiOS` : le récapitulatif
        // doit respirer, quoi qu'il y ait dessous.
        .padding(.bottom, 8)
    }

    private func ligneRecap(titre: String, nombre: Int,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(titre)
                    .font(.headline)
                    .foregroundStyle(Color.texteLegende)
                Spacer()
                Text("\(nombre)")
                    .font(.headline.bold())
                    .foregroundStyle(Color.orangeInternational)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Sections

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


    // MARK: Visionneuse

    /// Œuvres affichées ayant réellement une photo — ce que parcourt la
    /// visionneuse. Une œuvre sans photo n'y mènerait qu'à un écran vide.
    private var oeuvresAvecPhoto: [Oeuvre] {
        dons.filter { !$0.photoNom.isEmpty }
    }

    private func ouvrirVisionneuse(_ o: Oeuvre) {
        guard let i = oeuvresAvecPhoto.firstIndex(where: { $0.id == o.id }) else { return }
        TransitionVisionneuse.presenter { indexVisionneuse = i }
    }

    private var visionneuseOuverte: Binding<Bool> {
        Binding(get: { indexVisionneuse != nil },
                set: { if !$0 { indexVisionneuse = nil } })
    }

    @ViewBuilder
    private var contenuVisionneuse: some View {
        if let i = indexVisionneuse, !oeuvresAvecPhoto.isEmpty {
            VisionneuseOeuvres(
                oeuvres: oeuvresAvecPhoto,
                index: min(i, oeuvresAvecPhoto.count - 1),
                onNaviguer: { o in
                    // La vue de fond suit : à la fermeture, l'œuvre consultée
                    // est sélectionnée et à l'écran.
                    selection = [o.id]
                    oeuvreADefiler = o.id
                },
                cadreDepart: cadresVignettes[oeuvresAvecPhoto[min(i, oeuvresAvecPhoto.count - 1)].id],
                onFermer: { indexVisionneuse = nil })
            // Une seule des deux transitions s'applique. Avec le ressort
            // maison, on coupe AUSSI l'animation de présentation : sinon la
            // feuille glisse depuis le bas pendant que l'image s'agrandit.
            .modifier(TransitionOuverture(
                identifiant: oeuvresAvecPhoto[min(i, oeuvresAvecPhoto.count - 1)].id,
                espace: espaceZoom))
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
                    Text(o.dimensions)
                        .foregroundStyle(Color.texteLegende.opacity(0.6))
                    Spacer()
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
                // Même filet de sélection que `VueGalerie` : orange et 3 px
                // sur la vignette retenue, gris et 1 px sinon. Ces vues ont
                // leur propre rendu de vignette et l'avaient perdu.
                .strokeBorder(selection.contains(o.id)
                              ? Color.orangeInternational : Color.filetVignette,
                              lineWidth: selection.contains(o.id) ? 3 : 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 5, x: 0, y: 2)
        .contentShape(Rectangle())
        // Cible de défilement (proxy.scrollTo).
        .id(o.id)

        // Source de la transition de zoom vers la visionneuse.
        .matchedTransitionSource(id: o.id, in: espaceZoom)
        .publieCadreVignette(o.id)
        // Tap et appui prolongé pris par une vue UIKit en overlay :
        // elle seule peut prévenir d'un tap sur l'aperçu du menu contextuel,
        // le geste de Photos, que SwiftUI n'expose pas.
        .overlay(InteractionApercu(
            oeuvre: o,
            onTap: { selection = [o.id]; detail = o },
            onAfficher: { ouvrirVisionneuse(o) }))
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
                                // Même corps qu'en galerie (.subheadline) :
                                // c'est la même donnée, elle ne doit pas
                                // rapetisser en changeant de présentation.
                                Text(o.dimensions)
                                    .font(.subheadline).foregroundStyle(.secondary)
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
                // PAS d'appui prolongé sur les lignes de liste. Deux
                // tentatives ont échoué : `.onLongPressGesture` n'aboutit
                // jamais, le `Button` de la ligne captant le geste ; et
                // `simultaneousGesture` a causé de nouveaux problèmes. La
                // visionneuse s'ouvre donc depuis les VIGNETTES de galerie,
                // qui ne sont pas des boutons. À reprendre autrement.
                // Cible de défilement (proxy.scrollTo).
                .id(o.id)
            }
        }
        .padding(.horizontal, 16)
    }
}
#endif
