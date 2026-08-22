#if os(iOS)
import SwiftUI
import SwiftData

/// Vue « Inventaire » structurée pour iPhone.
///
/// Elle présente :
///  1. un en-tête récapitulatif : deux lignes « Ventes » et « Œuvres données »
///     avec le nombre d'œuvres correspondant (un tap fait défiler jusqu'à la
///     section) ;
///  2. une section « Ventes » avec les œuvres vendues ;
///  3. une section « Œuvres données » avec les œuvres données.
///
/// Le contenu de chaque section respecte le mode d'affichage choisi
/// (liste ou galerie), comme dans les autres vues.
struct VueOeuvresStructuree: View {
    /// Quand non vide, filtre les ventes sur ce mode de vente (ex. vue « Ventes »).
    let modesVente: [String]
    /// Quand non vide, remplace le menu de tri par un filtre par vendeur.
    let filtresVendeur: [String]

    init(modesVente: [String] = [], filtresVendeur: [String] = []) {
        self.modesVente = modesVente
        self.filtresVendeur = filtresVendeur
    }

    @Query private var toutes: [Oeuvre]

    @AppStorage("modeAffichage") private var modeAffichage: String = "liste"
    @AppStorage("triGalerie") private var triGalerie: String = "prix"
    // Sens du tri : true = croissant (du plus petit au plus grand).
    @AppStorage("triCroissant") private var triCroissant: Bool = false

    @State private var selection: Set<UUID> = []
    // Œuvre vers laquelle faire défiler la vue de fond, pour qu'elle suive la
    // navigation faite dans la fiche de détail (même mécanisme que VueiOS).
    @State private var oeuvreADefiler: UUID?
    @State private var detail: Oeuvre?
    @State private var vendeurFiltre: String = "Tout"

    // Identifiants d'ancrage pour le défilement vers une section.
    private let ancreVentes = "ancre-ventes"
    private let ancreDons   = "ancre-dons"

    /// Vrai si la vue opère en mode « filtre modeVente » (rubrique Ventes).
    private var estModeVentes: Bool { !modesVente.isEmpty }

    /// Icône du bouton de menu selon le critère actif.
    private var iconeMenu: String {
        if !filtresVendeur.isEmpty {
            return vendeurFiltre == "Tout" ? "person.3" : "person.fill"
        }
        switch triGalerie {
        case "acheteur":   return "person"
        case "dimensions": return "ruler"
        default:           return "eurosign"
        }
    }

    /// Œuvres vendues (tableaux + dessins + tapis), filtrées si besoin, triées.
    private var ventes: [Oeuvre] {
        var base = toutes.filter {
            $0.feuille == .tableauxVendus
            || $0.feuille == .dessinsVendus
            || $0.feuille == .tapisVendus
        }
        // Rubriques de « Ventes et dons » : uniquement les œuvres sorties du
        // fonds, en mode Inventaire comme en mode Ventes.
        base = base.filter(estVenduOuDonne)
        if !modesVente.isEmpty {
            base = base.filter { modesVente.contains($0.modeVente) }
        }
        if !filtresVendeur.isEmpty && vendeurFiltre != "Tout" {
            base = base.filter { $0.vendeur == vendeurFiltre }
        }
        return trier(base)
    }

    /// Œuvres données (masquées en mode « filtre modeVente »).
    private var dons: [Oeuvre] {
        let base = toutes.filter { $0.feuille == .oeuvresDonnees }
            .filter(estVenduOuDonne)
        return trier(base)
    }

    /// Applique le tri choisi (prix décroissant, ou acheteur alphabétique).
    private func trier(_ liste: [Oeuvre]) -> [Oeuvre] {
        // Tri de base en ordre croissant, puis inversion si demandé.
        let triees: [Oeuvre]
        switch triGalerie {
        case "acheteur":
            triees = liste.sorted {
                ligneNom($0).localizedCaseInsensitiveCompare(ligneNom($1)) == .orderedAscending
            }
        case "dimensions":
            // Tri par SURFACE (largeur × hauteur) plutôt que par texte.
            triees = liste.sorted {
                surfaceDimensions($0.dimensions) < surfaceDimensions($1.dimensions)
            }
        default:
            triees = liste.sorted { $0.prix < $1.prix }
        }
        return triCroissant ? triees : triees.reversed()
    }

    /// Nom affiché en gras : acheteur si présent, sinon destinataire.
    private func ligneNom(_ o: Oeuvre) -> String {
        !o.acheteur.isEmpty ? o.acheteur : o.destinataire
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // --- 1. En-tête récapitulatif ---
                    recapitulatif(proxy: proxy)

                    // --- 2. Section Ventes ---
                    // En mode Inventaire, le titre distingue la section "Ventes" des "Œuvres données".
                    // En mode Ventes, il est redondant avec le titre de navigation → masqué.
                    // L'ancre invisible garantit que le scroll du recap fonctionne dans les deux modes.
                    if !estModeVentes {
                        titreSection("Ventes")
                    }
                    Color.clear.frame(height: 0)
                        .padding(.top, estModeVentes ? 24 : 0)
                        .id(ancreVentes)
                    contenuSection(ventes, estDon: false)

                    // --- 3. Section Œuvres données (masquée en mode filtre) ---
                    if !estModeVentes {
                        titreSection("Œuvres données")
                            .id(ancreDons)
                        contenuSection(dons, estDon: true)
                    }
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
        .navigationTitle(estModeVentes ? "Ventes" : "Catalogue")
        .toolbar {
            // Un seul set de contrôles, compact : Liste, Galerie, tri, sens.
            // Regroupés dans un HStack pour maîtriser l'espacement.
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {

                // 1. Vue Liste.
                Button {
                    modeAffichage = "liste"
                } label: {
                    Image(systemName: "list.bullet")
                        .padding(6)
                        .background(
                            Circle().fill(modeAffichage == "liste"
                                          ? Color.primary.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)

                // 2. Vue Galerie.
                Button {
                    modeAffichage = "icone"
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .padding(6)
                        .background(
                            Circle().fill(modeAffichage == "icone"
                                          ? Color.primary.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)

                // 3. Filtre vendeur (vue Ventes) ou critère de tri standard.
                if !filtresVendeur.isEmpty {
                    Menu {
                        Button { vendeurFiltre = "Tout" } label: {
                            Text(vendeurFiltre == "Tout" ? "✓ Tout" : "Tout")
                        }
                        ForEach(filtresVendeur, id: \.self) { vendeur in
                            Button { vendeurFiltre = vendeur } label: {
                                Text(vendeurFiltre == vendeur ? "✓ \(vendeur)" : vendeur)
                            }
                        }
                    } label: {
                        Image(systemName: iconeMenu)
                    }
                } else {
                    Menu {
                        Button { triGalerie = "prix" } label: {
                            Label(triGalerie == "prix" ? "✓ Prix" : "Prix",
                                  systemImage: "eurosign")
                        }
                        Button { triGalerie = "acheteur" } label: {
                            Label(triGalerie == "acheteur" ? "✓ Acheteur" : "Acheteur",
                                  systemImage: "person")
                        }
                        Button { triGalerie = "dimensions" } label: {
                            Label(triGalerie == "dimensions" ? "✓ Dimensions" : "Dimensions",
                                  systemImage: "ruler")
                        }
                    } label: {
                        Image(systemName: iconeMenu)
                    }
                }

                // 4. Sens du tri : on utilise UNE seule icône (dont l'existence
                // est certaine) que l'on retourne verticalement pour figurer le
                // sens inverse. Les longueurs des traits s'inversent ainsi :
                // décroissant = grand/moyen/petit, croissant = petit/moyen/grand.
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
            DetailiOS(oeuvre: o, estFeuilleDon: o.feuille == .oeuvresDonnees,
                      listeNavigation: estModeVentes ? ventes : ventes + dons,
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

    // MARK: En-tête récapitulatif

    /// Deux lignes « Ventes » et « Œuvres données » avec leur nombre.
    /// Un tap fait défiler la vue jusqu'à la section correspondante.
    private func recapitulatif(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            ligneRecap(titre: estModeVentes ? "Nombre de ventes" : "Ventes",
                       nombre: ventes.count) {
                withAnimation { proxy.scrollTo(ancreVentes, anchor: .top) }
            }
            if !estModeVentes {
                Divider().padding(.leading, 20)
                ligneRecap(titre: "Œuvres données", nombre: dons.count) {
                    withAnimation { proxy.scrollTo(ancreDons, anchor: .top) }
                }
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

    private func titreSection(_ texte: String) -> some View {
        Text(texte)
            .font(.title2)
            .fontWeight(.semibold)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Contenu d'une section : galerie ou liste selon le mode d'affichage.
    @ViewBuilder
    private func contenuSection(_ liste: [Oeuvre], estDon: Bool) -> some View {
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

    /// Grille de vignettes (2 colonnes), style « polaroïd » comme la galerie.
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
                Text(ligneNom(o).isEmpty ? " " : ligneNom(o))
                    .font(.headline)
                    .foregroundStyle(Color.texteLegende)
                    .lineLimit(1)
                HStack {
                    if o.feuille != .oeuvresDonnees {
                        PrixText(o.prix)
                            .foregroundStyle(Color.orangeInternational)
                    }
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
        // Sur iPhone : un simple tap ouvre la fiche de détail.
        .onTapGesture { selection = [o.id]; detail = o }
    }

    /// Liste de lignes compactes (vignette + informations).
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
                            if o.feuille != .oeuvresDonnees {
                                // Acheteur en premier, puis prix.
                                Text(o.acheteur.isEmpty ? "—" : o.acheteur)
                                    .font(.headline)
                                    .lineLimit(1)
                                PrixText(o.prix)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.orangeInternational)
                            } else {
                                Text(o.destinataire.isEmpty ? "—" : o.destinataire)
                                    .font(.headline)
                            }
                            Text(o.type.isEmpty ? "—" : o.type)
                                .font(.subheadline).foregroundStyle(.secondary)
                                .lineLimit(1)
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
