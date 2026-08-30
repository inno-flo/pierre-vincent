#if os(iOS)
import SwiftUI
import SwiftData
import UIKit

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
    /// Remplace le menu de tri par un filtre par vendeur (enchères, expositions).
    let filtreParVendeur: Bool
    let estModeVentes: Bool
    /// Ligne de nom en tête de légende de vignette (fausse pour les enchères
    /// et les expositions, où l'acheteur ne renseigne pas).
    let nomEnGalerie: Bool
    /// Pastilles de type proposées (vide = pas de bandeau). Décidées par la
    /// rubrique, voir `Categorie.typesFiltre` : trois pour Catalogue et
    /// Ventes, aucune pour les sous-rubriques de mode de vente, qui ont déjà
    /// leur filtre par vendeur.
    let typesFiltre: [String]


    // Cette vue déclare un init EXPLICITE : ajouter une propriété ne suffit
    // pas à pouvoir la passer à l'appel, il faut aussi l'étendre ici.
    init(modesVente: [String] = [], filtreParVendeur: Bool = false,
         estModeVentes: Bool = false, titre: String = "Catalogue",
         nomEnGalerie: Bool = true, typesFiltre: [String] = []) {
        self.modesVente = modesVente
        self.filtreParVendeur = filtreParVendeur
        self.estModeVentes = estModeVentes
        self.titre = titre
        self.nomEnGalerie = nomEnGalerie
        self.typesFiltre = typesFiltre
    }

    @Query private var toutes: [Oeuvre]

    @AppStorage("modeAffichage") private var modeAffichage: String = "icone"
    @AppStorage("triGalerie") private var triGalerie: String = "prix"
    // Sens du tri : true = croissant (du plus petit au plus grand).
    @AppStorage("triCroissant") private var triCroissant: Bool = false

    @State private var selection: Set<UUID> = []
    // Œuvre vers laquelle faire défiler la vue de fond, pour qu'elle suive la
    // navigation faite dans la fiche de détail (même mécanisme que VueiOS).
    @State private var oeuvreADefiler: UUID?
    @State private var detail: Oeuvre?
    // Visionneuse plein écran : position courante (nil = fermée), et moteur
    // haptique conservé puis préparé au contact — un générateur neuf déclenche
    // à froid, ce qui se ressent comme un choc mou. Même patron que `VueiOS`.
    @State private var indexVisionneuse: Int?
    // Espace de la transition de zoom : la vignette pressée s'agrandit pour
    // devenir la visionneuse. C'est l'effet standard d'Apple pour une
    // présentation plein écran issue d'un élément précis.
    @Namespace private var espaceZoom


    @State private var vendeurFiltre: String = "Toutes"
    // Type retenu par le bandeau de pastilles (nil = tous). Non persisté :
    // c'est un filtre de consultation, pas un réglage.
    @State private var typeRetenu: String?

    // Identifiants d'ancrage pour le défilement vers une section.
    private let ancreVentes = "ancre-ventes"
    private let ancreDons   = "ancre-dons"

    /// Vrai si la vue opère en mode « filtre modeVente » (rubrique Ventes).
    /// Titre de la page, fourni par l'appelant.
    let titre: String
    /// Vrai pour la rubrique Ventes et ses sous-catégories : la section des
    /// dons est alors masquée.
    ///
    /// Reçu en paramètre et NON déduit de `modesVente` : depuis que Ventes
    /// n'impose plus de liste de modes (pour rester la somme de ses
    /// sous-catégories), cette liste est vide et la déduction basculait à faux.

    /// Icône du bouton de menu selon le critère actif.
    private var iconeMenu: String {
        if filtreParVendeur {
            // « person », pas « person.fill » : c'est l'icône que porte
            // chaque entrée de vendeur dans le menu (voir plus bas). Le
            // bouton doit reprendre EXACTEMENT celle de l'élément retenu,
            // pas une variante.
            return vendeurFiltre == "Toutes" ? "person.3" : "person"
        }
        switch triGalerie {
        case "acheteur":   return "person"
        case "dimensions": return "ruler"
        default:           return "eurosign"
        }
    }

    /// Œuvres vendues de la rubrique, AVANT le filtre par vendeur.
    ///
    /// Les vendeurs du menu s'en déduisent : les calculer après le filtre
    /// ferait disparaître toutes les autres entrées dès qu'on en retient une,
    /// sans moyen de revenir.
    private var baseVentes: [Oeuvre] {
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
        return base
    }

    /// Vendeurs réellement présents dans la rubrique, par ordre alphabétique.
    ///
    /// **Déduits des données, aucune liste en dur.** Le menu proposait quatre
    /// entrées figées, dont certaines n'ont rien vendu par ce canal : elles
    /// filtraient vers une liste vide. Un lieu inédit obtient son entrée dès
    /// qu'une œuvre le porte. Vides et « Inconnu » écartés.
    private var vendeursPresents: [String] {
        var vus: [String: String] = [:]
        for o in baseVentes {
            let brut = o.vendeur.trimmingCharacters(in: .whitespacesAndNewlines)
            let cle = brut.lowercased()
            guard !brut.isEmpty,
                  brut.caseInsensitiveCompare(valeurInconnue) != .orderedSame,
                  vus[cle] == nil else { continue }
            vus[cle] = brut
        }
        return vus.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Œuvres vendues (tableaux + dessins + tapis), filtrées si besoin, triées.
    private var ventes: [Oeuvre] {
        var base = baseVentes
        if filtreParVendeur && vendeurFiltre != "Toutes" {
            // Comparaison sur le seul champ Vendeur : les entrées du menu en
            // sont issues.
            base = base.filter {
                $0.vendeur.caseInsensitiveCompare(vendeurFiltre) == .orderedSame
            }
        }
        // Après le filtre par vendeur, et surtout après `baseVentes`, d'où se
        // déduisent les vendeurs du menu : les calculer sur une liste déjà
        // filtrée par type ferait disparaître des entrées.
        return trier(filtrerParType(base, mot: typeRetenu))
    }

    /// Œuvres données (masquées en mode « filtre modeVente »).
    private var dons: [Oeuvre] {
        let base = toutes.filter { $0.feuille == .oeuvresDonnees }
            .filter(estVenduOuDonne)
        return trier(filtrerParType(base, mot: typeRetenu))
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
        // Le champ se choisit sur la FEUILLE, jamais sur le vide : depuis la
        // reprise « Inconnu », `acheteur` n'est plus jamais vide sur un don —
        // il contient ce mot — et un test d'emptiness affichait donc
        // « Inconnu » à la place du destinataire.
        if o.feuille == .oeuvresDonnees { return afficher(o.destinataire) }
        return afficher(o.acheteur)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // --- 1. Filtre par type, DIRECTEMENT sous le titre ---
                    // Rendu DANS la zone de défilement, comme le
                    // récapitulatif : ancré au-dessus, la barre de navigation
                    // perdrait sa translucidité.
                    if !typesFiltre.isEmpty {
                        BandeauTypes(mots: typesFiltre,
                                     typeRetenu: $typeRetenu,
                                     nombreAffiche: ventes.count
                                                  + (estModeVentes ? 0 : dons.count),
                                     // Catalogue seulement (`!estModeVentes`) :
                                     // aligne le bord droit du compteur sur
                                     // celui de `ligneRecap`, juste en dessous.
                                     // Les sous-rubriques de mode de vente
                                     // n'ont pas de récapitulatif visible ici
                                     // (`recapInutile`) : elles gardent le
                                     // réglage par défaut du composant.
                                     paddingCompteur: estModeVentes ? 12 : 20)
                    }

                    // --- 2. Récapitulatif, SOUS les capsules ---
                    // Les deux lignes Ventes et Dons se lisent après le filtre
                    // qui les détermine, et non avant.
                    recapitulatif(proxy: proxy)

                    // --- 3. Section Ventes ---
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

                    // --- 4. Section Œuvres données (masquée en mode filtre) ---
                    if !estModeVentes {
                        titreSection("Dons")
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
        .navigationTitle(titre)
        .toolbar {
            // Un seul set de contrôles, compact : Liste, Galerie, tri, sens.
            // Regroupés dans un HStack pour maîtriser l'espacement.
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {

                // 1. Vue Galerie — en tête : présentation par défaut à la
                // première ouverture (`modeAffichage` vaut "icone").
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

                // 2. Vue Liste.
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

                // 3. Filtre vendeur (vue Ventes) ou critère de tri standard.
                if filtreParVendeur {
                    Menu {
                        // « Toutes » (les ventes) porte `person.3`, la
                        // même icône que le bouton du menu quand rien n'est
                        // retenu — plus l'icône générique de la rubrique
                        // (`symboleFiltreTous`, « cart »), qui ne dit rien du
                        // critère « vendeur ». Les entrées de vendeur
                        // prennent `person`, même famille — et le bouton du
                        // menu reprend cette icône EXACTE une fois un
                        // vendeur retenu (`iconeMenu`), pas une variante.
                        Button { vendeurFiltre = "Toutes" } label: {
                            Label(vendeurFiltre == "Toutes" ? "✓ Toutes" : "Toutes",
                                  systemImage: "person.3")
                        }
                        ForEach(vendeursPresents, id: \.self) { vendeur in
                            Button { vendeurFiltre = vendeur } label: {
                                Label(vendeurFiltre == vendeur ? "✓ \(vendeur)" : vendeur,
                                      systemImage: "person")
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
        .fullScreenCover(isPresented: visionneuseOuverte) { contenuVisionneuse }
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
    /// Vrai quand le récapitulatif n'a plus rien à apprendre : en mode Ventes,
    /// sa seule ligne annonce un nombre que le compteur du bandeau de
    /// pastilles donne déjà, juste en dessous.
    ///
    /// Les sous-rubriques de mode de vente, elles, n'ont PAS de bandeau
    /// (`typesFiltre` y est vide) : elles gardent leur ligne, faute de quoi
    /// le nombre d'œuvres ne s'afficherait plus nulle part.
    private var recapInutile: Bool { estModeVentes && !typesFiltre.isEmpty }

    @ViewBuilder
    private func recapitulatif(proxy: ScrollViewProxy) -> some View {
        if !recapInutile {
        VStack(spacing: 0) {
            ligneRecap(titre: estModeVentes ? "Nombre de ventes" : "Ventes",
                       nombre: ventes.count, gras: estModeVentes) {
                withAnimation { proxy.scrollTo(ancreVentes, anchor: .top) }
            }
            if !estModeVentes {
                Divider().padding(.leading, 20)
                // `gras: false` : dans le Catalogue SEULEMENT (cette ligne ne
                // s'affiche jamais dans les sous-rubriques de mode de vente,
                // où `estModeVentes` vaut `true`) — style normal demandé pour
                // « Ventes » et « Dons » et leurs compteurs. La ligne
                // « Nombre de ventes » d'un mode de vente garde son gras.
                ligneRecap(titre: "Dons", nombre: dons.count, gras: false) {
                    withAnimation { proxy.scrollTo(ancreDons, anchor: .top) }
                }
            }
        }
        .background(Color.fondLegende)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        // Marge basse portée ICI, par la cellule qui en a besoin : c'était le
        // bandeau qui la tenait quand il suivait, et il le précède désormais.
        .padding(.bottom, 8)
        }
    }

    private func ligneRecap(titre: String, nombre: Int, gras: Bool = true,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(titre)
                    .font(.headline)
                    .fontWeight(gras ? nil : .regular)
                    .foregroundStyle(Color.texteLegende)
                Spacer()
                Text("\(nombre)")
                    .font(.headline)
                    .fontWeight(gras ? .bold : .regular)
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

    // MARK: Visionneuse

    /// Œuvres affichées ayant réellement une photo — ce que parcourt la
    /// visionneuse. Une œuvre sans photo n'y mènerait qu'à un écran vide.
    private var oeuvresAvecPhoto: [Oeuvre] {
        (estModeVentes ? ventes : ventes + dons).filter { !$0.photoNom.isEmpty }
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
                if nomEnGalerie {
                    // ESSAI VISUEL : `.headline` garde sa taille, plus sa
                    // graisse — même vignette que `VueGalerie.swift`, à
                    // tenir d'accord avec elle.
                    Text(ligneNom(o).isEmpty ? " " : ligneNom(o))
                        .font(.headline)
                        .fontWeight(.regular)
                        .foregroundStyle(Color.texteLegende)
                        .lineLimit(1)
                }
                HStack {
                    if aUnPrix(o) {
                        PrixText(o.prix)
                            .foregroundStyle(Color.orangeInternational)
                        Spacer()
                        Text(o.dimensions)
                            .foregroundStyle(Color.texteLegende.opacity(0.6))
                    } else {
                        // Dons : les dimensions prennent la place du prix,
                        // alignées à gauche comme le destinataire au-dessus.
                        Text(o.dimensions)
                            .foregroundStyle(Color.texteLegende.opacity(0.6))
                        Spacer()
                    }
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
        // Sur iPhone : un simple tap ouvre la fiche de détail.

        // Source de la transition de zoom vers la visionneuse.
        .matchedTransitionSource(id: o.id, in: espaceZoom)
        // Tap et appui prolongé pris par une vue UIKit en overlay :
        // elle seule peut prévenir d'un tap sur l'aperçu du menu contextuel,
        // le geste de Photos, que SwiftUI n'expose pas.
        .overlay(InteractionApercu(
            oeuvre: o,
            onTap: { selection = [o.id]; detail = o },
            onAfficher: { ouvrirVisionneuse(o) }))
    }

    /// Liste de lignes compactes (vignette + informations).
    private func listeLignes(_ liste: [Oeuvre]) -> some View {
        // Lazy : ne construit que les lignes visibles à l'écran.
        LazyVStack(spacing: 8) {
            ForEach(liste) { o in
                HStack(spacing: 14) {
                        VignetteCachee(nom: o.photoNom, cote: 76)
                        VStack(alignment: .leading, spacing: 3) {
                            if aUnPrix(o) {
                                // Acheteur en premier, puis prix.
                                // ESSAI VISUEL : `.headline` garde sa taille,
                                // plus sa graisse — même traitement qu'en
                                // Galerie.
                                Text(o.acheteur.isEmpty ? "—" : o.acheteur)
                                    .font(.headline)
                                    .fontWeight(.regular)
                                    .lineLimit(1)
                                PrixText(o.prix)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.orangeInternational)
                            } else {
                                Text(o.destinataire.isEmpty ? "—" : o.destinataire)
                                    .font(.headline)
                                    .fontWeight(.regular)
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
                .contentShape(Rectangle())
                // Appui prolongé : la visionneuse, avec le menu contextuel
                // « Ajouter aux favoris » — même mécanisme que sur les
                // vignettes de galerie. PLUS un `Button` : c'est justement
                // ce qui empêchait l'appui prolongé d'aboutir ici.
                .overlay(InteractionApercu(
                    oeuvre: o,
                    onTap: { selection = [o.id]; detail = o },
                    onAfficher: { ouvrirVisionneuse(o) }))
                // Cible de défilement (proxy.scrollTo).
                .id(o.id)
            }
        }
        .padding(.horizontal, 16)
    }
}
#endif
