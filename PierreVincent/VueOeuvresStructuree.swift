#if os(iOS)
import SwiftUI
import SwiftData
import UIKit

/// Vue « Inventaire » structurée pour iPhone.
///
/// Sert deux rôles distincts :
///  - **Catalogue** (`cat == .oeuvres`) : Ventes et Dons réunis en une seule
///    Galerie/Liste (`catalogueComplet`), triable par les pastilles de
///    type — pas de récapitulatif ni de découpage en sections, simplifié à
///    la demande.
///  - **Ventes et ses sous-rubriques de mode de vente** (`estModeVentes`) :
///    un récapitulatif à une ligne (« Nombre de ventes ») au-dessus d'une
///    seule Galerie/Liste des œuvres vendues.
///
/// Le contenu respecte le mode d'affichage choisi (liste ou galerie), comme
/// dans les autres vues. **La Galerie délègue à `VueGalerie`** — le MÊME
/// composant que le Catalogue de la Réserve (`VueiOS`) — plutôt qu'une
/// grille dupliquée : les deux Catalogue restent ainsi identiques en rendu
/// ET en fluidité de défilement (voir CLAUDE.md).
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

    /// ESSAI TEMPORAIRE (voir `TestFondPage`, `Couleurs.swift`) : observé
    /// pour que cette vue se redessine quand le fond de page testé change,
    /// bien qu'elle ne s'en serve pas autrement. À retirer avec l'essai.
    @AppStorage(TestFondPage.cle) private var testFondPage = "creme"
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
    // Synchronisation du défilement entre Galerie et Liste : identifiant de
    // l'œuvre en tête d'écran, tenu à jour par `.scrollPosition(id:)`. Le
    // même `ScrollView` sert aux deux présentations ici (seul le contenu
    // change), mais le décalage brut ne correspond plus au même endroit une
    // fois la mise en page changée — ce modificateur recale sur l'ŒUVRE.
    @State private var idPositionDefilement: UUID?


    @State private var vendeurFiltre: String = "Toutes"
    // Type retenu par le bandeau de pastilles (nil = tous). Non persisté :
    // c'est un filtre de consultation, pas un réglage.
    @State private var typeRetenu: String?

    // Tout en haut de la vue — cible du bouton « Retour en haut ».
    private let ancreHaut = "ancre-haut"

    /// Visibilité du bouton flottant « Retour en haut » — voir
    /// `BoutonRetourHaut.swift`.
    @State private var boutonHautVisible = false

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

    /// Catalogue : Ventes et Dons RÉUNIS avant filtre et tri, pour un
    /// classement global unique — `ventes + dons` (chacune déjà triée
    /// séparément) donnerait deux séries triées mises bout à bout, pas un
    /// classement d'ensemble. Remplace le découpage en sections.
    private var catalogueComplet: [Oeuvre] {
        let base = baseVentes
            + toutes.filter { $0.feuille == .oeuvresDonnees }.filter(estVenduOuDonne)
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
        // La Galerie DÉLÈGUE désormais à `VueGalerie` — le MÊME composant
        // que le Catalogue de la Réserve (`VueiOS`) — au lieu d'une grille
        // dupliquée : même patron d'en-tête (`entete`, ci-dessous), même
        // fluidité de défilement déjà éprouvée là-bas. La Liste garde son
        // propre `ScrollViewReader` local (`liste`), calqué sur celui de
        // `VueiOS`. Plus de `ScrollView` unique partagé entre les deux
        // présentations : chacune a désormais la sienne, comme partout
        // ailleurs dans l'app.
        Group {
            if modeAffichage == "icone" {
                VueGalerie(
                    oeuvres: estModeVentes ? ventes : catalogueComplet,
                    selection: $selection,
                    onOuvrir: { o in selection = [o.id]; detail = o },
                    onAppuiLong: { o in ouvrirVisionneuse(o) },
                    espaceZoom: espaceZoom,
                    nomEnGalerie: nomEnGalerie,
                    entete: entete,
                    positionDefilement: $idPositionDefilement
                )
            } else {
                liste
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
                      listeNavigation: estModeVentes ? ventes : catalogueComplet,
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

    // MARK: En-tête (récapitulatif + bandeau de pastilles)

    /// Vrai quand le récapitulatif « Nombre de ventes » a quelque chose à
    /// dire que le compteur du bandeau de pastilles, juste en dessous, ne
    /// donne pas déjà — n'existe que pour les sous-rubriques de mode de
    /// vente (`estModeVentes`), jamais pour le Catalogue, et seulement sans
    /// bandeau (`typesFiltre` vide).
    private var afficherRecap: Bool { estModeVentes && typesFiltre.isEmpty }

    /// En-tête commun aux deux présentations (Galerie ET Liste), même
    /// patron que `VueiOS.entete` (Réserve) : rendu DANS la zone de
    /// défilement — pas au-dessus, où la barre de navigation perdrait sa
    /// translucidité — et passé tel quel à `VueGalerie` comme à `liste`.
    private var entete: AnyView? {
        guard afficherRecap || !typesFiltre.isEmpty else { return nil }
        return AnyView(
            VStack(spacing: 0) {
                if afficherRecap { recapCell }
                if !typesFiltre.isEmpty {
                    BandeauTypes(mots: typesFiltre,
                                 typeRetenu: $typeRetenu,
                                 nombreAffiche: estModeVentes
                                              ? ventes.count
                                              : catalogueComplet.count,
                                 // Catalogue (`!estModeVentes`) : 20 pt plutôt
                                 // que le défaut 12, valeur retenue pour
                                 // l'alignement visuel avec le bord de
                                 // l'écran — cette rubrique n'a plus de
                                 // récapitulatif à aligner en dessous depuis
                                 // la simplification à une seule Galerie/Liste.
                                 paddingCompteur: estModeVentes ? 12 : 20)
                }
            }
        )
    }

    /// Ligne « Nombre de ventes » avec son compte — sans action, comme
    /// `VueiOS.recapCell` : le tap-pour-défiler qu'avait l'ancienne version
    /// n'a plus de sens, `VueGalerie` possédant son propre `ScrollViewReader`
    /// interne, hors de portée de cette vue.
    private var recapCell: some View {
        HStack {
            Text("Nombre de ventes")
                .font(.headline)
                .foregroundStyle(Color.texteLegende)
            Spacer()
            Text("\(ventes.count)")
                .font(.headline.bold())
                .foregroundStyle(Color.orangeInternational)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.fondLegende)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// Présentation Liste — même patron que `VueiOS.liste` (Réserve) : un
    /// `ScrollViewReader` local et propre à cette présentation (Galerie a le
    /// sien, interne à `VueGalerie`), `entete` en tête de la zone de
    /// défilement, puis les lignes.
    private var liste: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Tout en haut : cible du bouton « Retour en haut ».
                Color.clear.frame(height: 0).id(ancreHaut)
                if let entete {
                    entete
                } else {
                    // Sans en-tête, la première ligne se collerait au haut de
                    // la zone de défilement (voir le piège des marges portées
                    // par un voisin, CLAUDE.md).
                    Color.clear.frame(height: 8)
                }
                listeLignes(estModeVentes ? ventes : catalogueComplet)
            }
            .background(Color.cremeFond)
            // Synchronisation Galerie ↔ Liste — voir `idPositionDefilement`.
            .scrollPosition(id: $idPositionDefilement, anchor: .top)
            // Suit l'œuvre consultée dans la fiche de détail.
            .onChange(of: oeuvreADefiler) { _, cible in
                guard let cible else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(cible, anchor: .center)
                    }
                }
            }
            // Bouton « Retour en haut » — voir `BoutonRetourHaut.swift`.
            .retourEnHaut(visible: $boutonHautVisible) {
                withAnimation { proxy.scrollTo(ancreHaut, anchor: .top) }
            }
        }
    }

    // MARK: Visionneuse

    /// Œuvres affichées ayant réellement une photo — ce que parcourt la
    /// visionneuse. Une œuvre sans photo n'y mènerait qu'à un écran vide.
    private var oeuvresAvecPhoto: [Oeuvre] {
        (estModeVentes ? ventes : catalogueComplet).filter { !$0.photoNom.isEmpty }
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

    /// Liste de lignes compactes (vignette + informations). Gère elle-même
    /// le cas vide — auparavant à la charge de l'appelant (`contenuSection`,
    /// supprimée avec la délégation de la Galerie à `VueGalerie`).
    @ViewBuilder
    private func listeLignes(_ liste: [Oeuvre]) -> some View {
        if liste.isEmpty {
            Text("Aucune entrée")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
        } else {
            // Lazy : ne construit que les lignes visibles à l'écran.
            LazyVStack(spacing: 8) {
                ForEach(liste) { o in ligneListe(o) }
            }
            // Indispensable à `.scrollPosition(id:)` — voir `VueGalerie`.
            .scrollTargetLayout()
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
    }

    /// Une ligne de la présentation Liste — extraite de `listeLignes` pour
    /// être réutilisable telle quelle par `listeCatalogueComplete`, qui a
    /// besoin de la poser dans DEUX `Section` d'une même `LazyVStack`.
    private func ligneListe(_ o: Oeuvre) -> some View {
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

#endif
