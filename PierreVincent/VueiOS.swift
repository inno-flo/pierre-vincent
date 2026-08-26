#if os(iOS)
import SwiftUI
import SwiftData
import UIKit

/// Vue de consultation pour iPhone/iPad (lecture seule).
/// Affiche les entrées d'une catégorie en liste ou en galerie, avec accès
/// à une fiche de détail (photo, prix, informations) au toucher.
struct VueiOS: View {
    /// Accent de la rubrique — orange dans « Ventes et dons », bleu ardoise
    /// dans la Réserve. Posé sur la colonne de contenu, il descend jusqu'ici.
    @Environment(\.accentRubrique) private var accent

    let feuille: Feuille?
    let titre: String
    let modesVente: [String]
    let statuts: [String]          // statuts recensés par la rubrique
    let types: [String]            // filtre sur le champ Type (vide = aucun)
    let themes: [String]           // filtre sur le champ Thème (vide = aucun)
    let collectionSeule: Bool      // ne recenser que la collection personnelle
    let favoriSeul: Bool           // ne recenser que les favoris (rubrique Favoris)
    /// Pastilles de type proposées (vide = pas de bandeau). Décidées par la
    /// rubrique, voir `Categorie.typesFiltre`.
    let typesFiltre: [String]

    /// Symbole de l'entrée « Tous » du menu de filtre par type — l'icône de
    /// la rubrique dans les deux Catalogue, la grille générique ailleurs.
    let symboleFiltreTous: String

    let visionneuseIntegree: Bool  // appui prolongé : visionneuse plein écran

    init(feuille: Feuille?, titre: String, modesVente: [String] = [],
         statuts: [String] = Array(statutsVentesEtDons),
         types: [String] = [],
         themes: [String] = [],
         collectionSeule: Bool = false,
         favoriSeul: Bool = false,
         typesFiltre: [String] = [],
         symboleFiltreTous: String = "square.grid.2x2",
         visionneuseIntegree: Bool = false) {
        self.feuille = feuille
        self.titre = titre
        self.modesVente = modesVente
        self.statuts = statuts
        self.types = types
        self.themes = themes
        self.collectionSeule = collectionSeule
        self.favoriSeul = favoriSeul
        self.typesFiltre = typesFiltre
        self.symboleFiltreTous = symboleFiltreTous
        self.visionneuseIntegree = visionneuseIntegree
    }

    @Query private var toutes: [Oeuvre]
    @State private var tri: [KeyPathComparator<Oeuvre>] = [
        KeyPathComparator(\Oeuvre.type)
    ]
    // Mode d'affichage, conservé entre les sessions (comme sur Mac).
    @AppStorage("modeAffichage") private var modeAffichage: String = "icone"
    // Critère de tri de la galerie (partagé avec le Mac via le même réglage).
    @AppStorage("triGalerie") private var triGalerie: String = "prix"
    // Sens du tri : true = croissant (du plus petit au plus grand).
    @AppStorage("triCroissant") private var triCroissant: Bool = false
    @State private var selection: Set<UUID> = []
    @State private var detail: Oeuvre?
    // Œuvre vers laquelle défiler à la fermeture de la fiche Détails.
    @State private var oeuvreADefiler: UUID?
    // Position courante dans la visionneuse plein écran (nil = fermée).
    @State private var indexVisionneuse: Int?
    // Type retenu par le bandeau de pastilles (nil = tous). Non persisté :
    // c'est un filtre de consultation, pas un réglage.
    @State private var typeRetenu: String?
    // Espace de la transition de zoom : la vignette pressée s'agrandit pour
    // devenir la visionneuse. C'est l'effet standard d'Apple pour une
    // présentation plein écran issue d'un élément précis.
    @Namespace private var espaceZoom


    /// Œuvres retenues par la rubrique (feuille, mode de vente, statut, type),
    /// avant tri.
    private var baseRubrique: [Oeuvre] {
        var base: [Oeuvre]
        if let f = feuille {
            base = toutes.filter { $0.feuille == f }
        } else if !modesVente.isEmpty {
            // Filtre modeVente actif : ni dons, ni réserve.
            base = toutes.filter { !feuillesSansPrix.contains($0.feuille) }
        } else {
            base = toutes
        }
        if !modesVente.isEmpty {
            base = base.filter { modesVente.contains($0.modeVente) }
        }
        // Filtres propres à la rubrique : statut, type, thème.
        let retenues = base.filter {
            correspond($0, statuts: statuts, types: types, themes: themes,
                       collectionSeule: collectionSeule, favoriSeul: favoriSeul)
        }
        return filtrerParType(retenues, mot: typeRetenu)
    }
    /// Œuvres de cette catégorie, filtrées et triées.
    private var oeuvres: [Oeuvre] {
        baseRubrique.sorted(using: tri)
    }

    private var estFeuilleDon: Bool { feuille == .oeuvresDonnees }

    /// Vrai si la rubrique n'a pas de prix à montrer : dons et Réserve.
    private var rubriqueSansPrix: Bool {
        guard let f = feuille else { return false }
        return feuillesSansPrix.contains(f)
    }

    /// Œuvres triées pour la galerie, selon le critère choisi (prix ou acheteur).
    private var oeuvresGalerie: [Oeuvre] {
        let base = baseRubrique
        // Critère effectif : on retombe sur un tri pertinent si le critère
        // mémorisé ne s'applique pas à cette feuille (ex. prix dans les dons,
        // dimensions dans les tapis).
        var critere = triGalerie
        if rubriqueSansPrix, critere == "prix" { critere = "dimensions" }
        if feuille == .tapisVendus, critere == "dimensions" { critere = "prix" }

        // Tri de base, toujours calculé en ordre CROISSANT
        // (du plus petit / début d'alphabet au plus grand).
        let triees: [Oeuvre]
        switch critere {
        case "acheteur":
            // Pour les dons, l'acheteur est vide : on trie alors sur le
            // destinataire, qui joue le même rôle dans l'affichage.
            func nom(_ o: Oeuvre) -> String {
                !o.acheteur.isEmpty ? o.acheteur : o.destinataire
            }
            triees = base.sorted { nom($0).localizedCaseInsensitiveCompare(nom($1)) == .orderedAscending }
        case "dimensions":
            // Tri par SURFACE (largeur × hauteur) plutôt que par texte.
            triees = base.sorted { surfaceDimensions($0.dimensions) < surfaceDimensions($1.dimensions) }
        default: // "prix"
            triees = base.sorted { $0.prix < $1.prix }
        }
        // Le bouton d'ordre inverse la liste si l'on veut du plus grand au plus petit.
        return triCroissant ? triees : triees.reversed()
    }

    /// Cellule récapitulative affichée en haut de la vue (nombre d'œuvres correspondant aux filtres actifs).
    /// Le récapitulatif compte des VENTES : sans objet dans la Réserve, dont
    /// les œuvres n'ont par définition pas encore été vendues. Retiré des deux
    /// présentations, galerie et liste.
    private var recapVisible: Bool { feuille != .reserve }

    /// En-tête commun aux deux présentations : le récapitulatif quand il a du
    /// sens, et le bandeau de pastilles quand la rubrique le déclare.
    ///
    /// Rendu DANS la zone de défilement — comme le récapitulatif — pour que la
    /// barre de navigation garde sa translucidité. Ancré au-dessus, elle
    /// deviendrait pleine.
    private var entete: AnyView? {
        guard recapVisible || !typesFiltre.isEmpty else { return nil }
        return AnyView(
            VStack(spacing: 0) {
                if recapVisible { recapCell }
                if !typesFiltre.isEmpty {
                    BandeauTypes(mots: typesFiltre,
                                 typeRetenu: $typeRetenu,
                                 nombreAffiche: oeuvresGalerie.count)
                }
            }
        )
    }

    /// Œuvres de la rubrique ayant réellement une photo — ce que parcourt la
    /// visionneuse. Une œuvre sans photo n'y mènerait qu'à un écran vide.
    ///
    /// Les deux présentations partagent `oeuvresGalerie` : la liste affiche
    /// elle aussi cette liste triée, pas `oeuvres`.
    private var oeuvresAvecPhoto: [Oeuvre] {
        oeuvresGalerie.filter { !$0.photoNom.isEmpty }
    }

    /// Présentation de la visionneuse, adossée à `indexVisionneuse`.
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
                    // Sélection ET défilement : à la fermeture, l'œuvre
                    // consultée doit être à l'écran, filet orange visible.
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

    /// Action d'appui prolongé passée à la galerie, ou `nil` si la rubrique
    /// ne propose pas la visionneuse.
    ///
    /// Écrite en `guard` + closure explicite, et non en ternaire : la forme
    /// `visionneuseIntegree ? ouvrirVisionneuse : nil` — une référence de
    /// méthode dans un ternaire à résultat optionnel — faisait échouer la
    /// vérification de types de toute la vue, sans diagnostic exploitable.
    private var appuiLongGalerie: ((Oeuvre) -> Void)? {
        guard visionneuseIntegree else { return nil }
        return { oeuvre in ouvrirVisionneuse(oeuvre) }
    }

    /// Ouvre la visionneuse sur l'œuvre touchée, si elle a une photo.
    private func ouvrirVisionneuse(_ o: Oeuvre) {
        guard let i = oeuvresAvecPhoto.firstIndex(where: { $0.id == o.id }) else { return }
        TransitionVisionneuse.presenter { indexVisionneuse = i }
    }

    private var recapCell: some View {
        HStack {
            Text("Nombre de ventes")
                .font(.headline)
                .foregroundStyle(Color.texteLegende)
            Spacer()
            Text("\(oeuvresGalerie.count)")
                .font(.headline.bold())
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.fondLegende)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// Icône du bouton de menu selon le critère actif.
    private var iconeMenu: String {
        switch triGalerie {
        case "acheteur":   return "person"
        case "dimensions": return "ruler"
        default:           return "eurosign"
        }
    }

    var body: some View {
        // Le récapitulatif est passé DANS la zone de défilement, en galerie
        // comme en liste : il défile donc avec le contenu et la barre de
        // navigation prend sa transparence, comme dans les vues Catalogue,
        // Ventes et Dons. Placé au-dessus du ScrollView, il restait ancré et
        // ces deux effets manquaient.
        Group {
            if modeAffichage == "icone" {
                VueGalerie(
                    oeuvres: oeuvresGalerie,
                    selection: $selection,
                    onOuvrir: { o in selection = [o.id]; detail = o },
                    onAppuiLong: appuiLongGalerie,
                    espaceZoom: espaceZoom,
                    entete: entete
                )
            } else {
                liste
            }
        }
        // Plein écran, barres système comprises : `.fullScreenCover` et non
        // `.sheet`, qui laisserait la fiche en carte avec ses coins arrondis.
        .fullScreenCover(isPresented: visionneuseOuverte) { contenuVisionneuse }
        .background(Color.cremeFond)
        .navigationTitle(titre)
        .toolbar {
            // Un seul set de contrôles, compact : Liste, Galerie, tri, sens.
            // Regroupés dans un HStack pour maîtriser l'espacement (plus serré
            // que l'espacement par défaut d'un ToolbarItemGroup).
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {

                // 0. Filtre par type, en TÊTE de la capsule.
                // Retiré pour l'instant : voir `afficherMenuFiltreTypeToolbar`.
                if afficherMenuFiltreTypeToolbar && !typesFiltre.isEmpty {
                    MenuFiltreTypes(mots: typesFiltre,
                                    symboleTous: symboleFiltreTous,
                                    typeRetenu: $typeRetenu)
                }

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

                // 3. Critère de tri.
                //
                // PAS de filtre par vendeur ici : cette vue ne sert QUE les
                // rubriques par type et la Réserve. `Categorie.filtreParVendeur`
                // n'est vrai que pour un mode de vente, et ce cas part vers
                // `VueOeuvresStructuree` par `estVenteRealisee`. La branche qui
                // s'était écrite ici ne s'affichait donc jamais — et divergeait
                // déjà de celle qui vit, faute d'être vue.
                if feuille != .reserve {
                    // Mode tri standard : Prix, Acheteur, Dimensions.
                    // Absent de la Réserve : ces œuvres n'ont ni prix ni
                    // acheteur, et le menu n'y proposerait que Dimensions.
                    // Le bouton de sens du tri, lui, reste.
                    Menu {
                        if !rubriqueSansPrix {
                            Button {
                                triGalerie = "prix"
                            } label: {
                                Label(triGalerie == "prix" ? "✓ Prix" : "Prix",
                                      systemImage: "eurosign")
                            }
                        }
                        Button {
                            triGalerie = "acheteur"
                        } label: {
                            Label(triGalerie == "acheteur" ? "✓ Acheteur" : "Acheteur",
                                  systemImage: "person")
                        }
                        if feuille != .tapisVendus {
                            Button {
                                triGalerie = "dimensions"
                            } label: {
                                Label(triGalerie == "dimensions" ? "✓ Dimensions" : "Dimensions",
                                      systemImage: "ruler")
                            }
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
        // Fiche de détail au toucher d'une entrée.
        .sheet(item: $detail) { o in
            DetailiOS(oeuvre: o, estFeuilleDon: estFeuilleDon,
                      listeNavigation: oeuvresGalerie,
                      onFermeture: { derniere in
                          oeuvreADefiler = derniere.id
                          // Met à jour la sélection : déclenche aussi le
                          // défilement de la galerie (mode icone).
                          selection = [derniere.id]
                      },
                      onStabilise: { stable in
                          // Positionne la liste/galerie par anticipation pendant
                          // les pauses de navigation (avant même la fermeture).
                          oeuvreADefiler = stable.id
                          selection = [stable.id]
                      })
        }
    }

    /// Liste en blocs séparés sur fond beige (même style que la vue « Œuvres »).
    private var liste: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let entete {
                    entete
                } else {
                    // Sans en-tête, la première ligne se collerait au haut de
                    // la zone de défilement : on rend la marge que la cellule
                    // apportait (voir le piège des marges portées par un
                    // voisin, dans CLAUDE.md).
                    Color.clear.frame(height: 8)
                }
                // Lazy : ne construit que les lignes visibles à l'écran.
                LazyVStack(spacing: 8) {
                    ForEach(oeuvresGalerie) { o in
                        Button {
                            selection = [o.id]
                            detail = o
                        } label: {
                            HStack(spacing: 14) {
                                VignetteCachee(nom: o.photoNom, cote: 76)
                                VStack(alignment: .leading, spacing: 3) {
                                    if aUnPrix(o) {
                                        // Acheteur en premier (mis en avant), puis prix.
                                        Text(o.acheteur.isEmpty ? "—" : o.acheteur)
                                            .font(.headline)
                                            .lineLimit(1)
                                        PrixText(o.prix)
                                            .font(.subheadline)
                                            .foregroundStyle(accent)
                                        if !o.modeVente.isEmpty {
                                            Text(o.modeVente)
                                                .font(.body).foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    } else if o.feuille == .reserve {
                                        // Réserve : le rangement remplace le
                                        // couple acheteur / prix. L'intitulé
                                        // vient EN PREMIER, en gris, la valeur
                                        // ensuite — seule, elle ne dit pas de
                                        // quel champ elle relève. Le champ
                                        // montré dépend du type, voir
                                        // `rangementVignette`.
                                        Text(rangementVignette(o).intitule)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Text(rangementVignette(o).valeur)
                                            .font(.headline).lineLimit(1)
                                    } else if !o.destinataire.isEmpty {
                                        Text(o.destinataire)
                                            .font(.headline).lineLimit(1)
                                    }
                                    // Le type n'est PAS affiché ici : ces vues ne
                                    // contiennent qu'un seul type d'œuvre.
                                    if !o.dimensions.isEmpty {
                                        Text(o.dimensions)
                                            .font(.body).foregroundStyle(.secondary)
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
                                                  ? accent : Color.clear,
                                                  lineWidth: 3)
                            )
                        }
                        .buttonStyle(.plain)
                        // Appui prolongé : la visionneuse, comme sur une
                        // vignette de galerie. Le tap du bouton continue
                        // d'ouvrir la fiche de détail.
                        // PAS d'appui prolongé sur les lignes de liste. Deux
                        // tentatives ont échoué : `.onLongPressGesture` n'aboutit
                        // jamais, le `Button` de la ligne captant le geste ; et
                        // `simultaneousGesture` a causé de nouveaux problèmes. La
                        // visionneuse s'ouvre donc depuis les VIGNETTES de galerie,
                        // qui ne sont pas des boutons. À reprendre autrement.
                        .id(o.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .background(Color.cremeFond)
            // Défile vers la dernière œuvre consultée à la fermeture de la fiche.
            .onChange(of: oeuvreADefiler) { _, cible in
                guard let cible else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(cible, anchor: .center)
                    }
                }
            }
        }
    }
}

/// Fiche de détail d'une entrée (lecture seule) pour iPhone/iPad.
struct DetailiOS: View {

    /// Accent de la rubrique — hérité de la vue qui présente cette fiche.
    @Environment(\.accentRubrique) private var accent

    let oeuvre: Oeuvre
    let estFeuilleDon: Bool
    /// Liste ordonnée pour naviguer Précédent / Suivant (ordre d'affichage).
    var listeNavigation: [Oeuvre] = []
    /// Appelé à la fermeture avec la dernière œuvre affichée, pour que la liste
    /// parente se positionne dessus.
    var onFermeture: (Oeuvre) -> Void = { _ in }
    /// Appelé après une courte pause sans navigation, pour positionner la liste
    /// parente sur l'œuvre courante par anticipation (avant même la fermeture).
    var onStabilise: (Oeuvre) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    // Œuvre affichée (change avec les chevrons) et sa position dans la liste.
    @State private var courante: Oeuvre?
    @State private var indexCourant = 0
    // Sens du dernier changement, pour orienter la transition (+1 / -1).
    @State private var sensTransition = 1
    // Verrou : empêche une nouvelle navigation pendant l'animation en cours
    // (sinon deux transitions se chevauchent et un bouton peut se figer).
    @State private var enTransition = false
    // Minuteur réarmable : détecte les pauses dans la navigation.
    @State private var tacheStabilisation: Task<Void, Never>?
    // Affichage de la photo en plein écran (tap prolongé).
    @State private var imagePleinEcranOuverte = false
    /// Désactive le bouton « Fermer » de la barre d'outils pendant la
    /// visionneuse plein écran, et un court instant après sa fermeture.
    ///
    /// **Sans quoi** : le bouton « Fermer » de CETTE fiche occupe le même
    /// coin (haut-droit, `.confirmationAction`) que la croix de la
    /// visionneuse. Si le doigt reste posé au moment où celle-ci se referme,
    /// il retombe exactement sur ce bouton-ci — encore sous contact — qui
    /// affiche alors son état « pressé » (un tremblement), sans pour autant
    /// se déclencher : le geste n'est pas un appui reconnu depuis le début
    /// PAR ce bouton. Le désactiver bloque ce résidu sans avoir à déplacer
    /// la croix.
    @State private var boutonFermerActif = true

    /// Œuvre réellement affichée (la courante, ou celle passée à l'ouverture).
    private var oeuvreAffichee: Oeuvre { courante ?? oeuvre }

    var body: some View {
        NavigationStack {
            ScrollView {
                // Le ZStack est nécessaire pour que l'ancienne et la nouvelle
                // fiche soient réellement superposées pendant l'animation :
                // sans lui, à l'intérieur d'un simple ScrollView, SwiftUI ne
                // compose pas les deux vues en même temps et le glissement
                // latéral ne se voit pas (juste un remplacement sec).
                ZStack {
                    contenuFiche
                        // Identité liée à l'œuvre : SwiftUI anime le
                        // remplacement du contenu à chaque changement.
                        .id(oeuvreAffichee.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: sensTransition > 0 ? .trailing : .leading)
                                .combined(with: .opacity),
                            removal: .move(edge: sensTransition > 0 ? .leading : .trailing)
                                .combined(with: .opacity)
                        ))
                }
            }
            .background(Color.cremeFond)
            // Navigation par glissement latéral : vers la gauche = suivant,
            // vers la droite = précédent.
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { valeur in
                        // On ne réagit qu'aux glissements franchement horizontaux.
                        let dx = valeur.translation.width
                        let dy = valeur.translation.height
                        guard abs(dx) > abs(dy), abs(dx) > 60 else { return }
                        if dx < 0 {
                            naviguer(1)   // glissement vers la gauche → suivant
                        } else {
                            naviguer(-1)  // glissement vers la droite → précédent
                        }
                    }
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Deux boutons natifs séparés par un ToolbarSpacer : sur iOS 26,
                // chacun reçoit son propre fond « liquid glass » au lieu d'être
                // fusionnés dans une capsule commune.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        naviguer(-1)
                    } label: { Image(systemName: "chevron.left") }
                        .disabled(indexCourant <= 0)
                }
                ToolbarSpacer(.fixed, placement: .topBarLeading)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        naviguer(1)
                    } label: { Image(systemName: "chevron.right") }
                        .disabled(indexCourant >= listeNavigation.count - 1)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                        .disabled(!boutonFermerActif)
                }
            }
            .onAppear {
                courante = oeuvre
                if let i = listeNavigation.firstIndex(where: { $0.id == oeuvre.id }) {
                    indexCourant = i
                }
            }
            .onDisappear {
                // Annule le minuteur de stabilisation en attente.
                tacheStabilisation?.cancel()
                // Renvoie la dernière œuvre consultée à la liste parente.
                onFermeture(oeuvreAffichee)
            }
        }
    }

    /// Contenu de la fiche (extrait pour alléger la vérification de type).
    private var contenuFiche: some View {
        let oeuvre = oeuvreAffichee
        return VStack(alignment: .leading, spacing: 12) {
            // Grande image, ou vignette « image manquante » si absente.
            if let img = PhotoStore.chargerImage(nom: oeuvre.photoNom) {
                Image(imagePlateforme: img).resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .cornerRadius(12)
                    // Tap prolongé (comme sur une icône d'écran d'accueil) :
                    // retour haptique puis ouverture en plein écran, zoomable.
                    .onLongPressGesture(minimumDuration: RetourAppuiLong.duree) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        boutonFermerActif = false
                        imagePleinEcranOuverte = true
                    }
                    .fullScreenCover(isPresented: $imagePleinEcranOuverte, onDismiss: {
                        // `onDismiss` : la visionneuse a COMPLÈTEMENT disparu.
                        // Un court délai supplémentaire couvre le doigt encore
                        // posé au moment où l'animation s'achève.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            boutonFermerActif = true
                        }
                    }) {
                        VisionneuseImagePleinEcran(image: img)
                    }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.15))
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            }

            // Cellule 1 : Prix (ni dons, ni réserve). Le test porte sur
            // l'ŒUVRE et non sur la rubrique : dans les vues agrégées, la
            // feuille de la rubrique ne dit rien de l'œuvre affichée.
            if aUnPrix(oeuvre) {
                cellule {
                    ligne("Prix", formaterEuros(oeuvre.prix),
                          couleur: accent, estPrix: true)
                }
            }

            // Cellule 2 : Type + Thème, CÔTE À CÔTE — même regroupement et
            // même présentation que sur Mac (éditeur et inspecteur).
            cellule {
                HStack(alignment: .top, spacing: 16) {
                    ligne("Type", oeuvre.type)
                    ligne("Thème", oeuvre.theme)
                }
            }

            // Cellule 3 : Dimensions et Format, CÔTE À CÔTE.
            cellule {
                HStack(alignment: .top, spacing: 16) {
                    ligne("Dimensions", oeuvre.dimensions)
                    ligne("Format", oeuvre.format)
                }
            }

            // Cellule 4 : Statut, Emplacement.
            cellule {
                // Thème est monté dans la cellule Type, juste au-dessus.
                ligne("Statut", oeuvre.statut)
                // Placé AVANT l'emplacement : il dit à quel ensemble l'œuvre
                // appartient, l'emplacement où la trouver.
                ligne("Collection personnelle", oeuvre.collectionPersonnelle)
                ligne("Lieu de stockage", oeuvre.lieuStockage)
                ligne("Emplacement", oeuvre.emplacement)
            }

            // Cellule 5 : Vendeur, Acheteur (ou Destinataire), Mode de vente.
            // Rien pour la réserve : aucune transaction n'a eu lieu.
            if oeuvre.feuille != .reserve {
                cellule {
                    if estFeuilleDon {
                        ligne("Destinataire", oeuvre.destinataire)
                        ligne("Mode de vente", oeuvre.modeVente)
                    } else {
                        ligne("Vendeur", oeuvre.vendeur)
                        ligne("Acheteur", oeuvre.acheteur)
                        ligne("Mode de vente", oeuvre.modeVente)
                    }
                }
            }

            // Cellule 6 : Date (ni dons, ni réserve).
            if !estFeuilleDon && oeuvre.feuille != .reserve {
                cellule {
                    ligne("Date", oeuvre.date)
                }
            }

            // Cellule 7 : Remarques.
            cellule {
                ligne("Remarques", oeuvre.remarques)
            }
        }
        .padding()
    }

    /// Passe à l'œuvre précédente (-1) ou suivante (+1).
    private func naviguer(_ sens: Int) {
        // Ignore l'appui si une transition est déjà en cours.
        guard !enTransition else { return }
        let nouvel = indexCourant + sens
        guard nouvel >= 0, nouvel < listeNavigation.count else { return }
        sensTransition = sens
        enTransition = true
        // Durée un peu plus longue que l'ancienne (0,15 s) : à cette
        // vitesse-là le glissement latéral n'avait pas le temps de se voir,
        // et ressemblait à un simple remplacement.
        withAnimation(.easeInOut(duration: 0.25)) {
            indexCourant = nouvel
            courante = listeNavigation[nouvel]
        }
        // Libère le verrou une fois l'animation terminée.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            enTransition = false
        }
        // Réarme le minuteur de stabilisation : si aucune nouvelle navigation
        // n'arrive dans les 0,4 s, on positionne la liste parente par
        // anticipation (la personne s'apprête peut-être à fermer la vue).
        tacheStabilisation?.cancel()
        let oeuvreStable = listeNavigation[nouvel]
        tacheStabilisation = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)   // 0,4 s
            if !Task.isCancelled {
                await MainActor.run { onStabilise(oeuvreStable) }
            }
        }
    }

    /// Une cellule façon Synthèse / Inspecteur : fond crème, filet orange léger.
    @ViewBuilder
    private func cellule<Contenu: View>(
        @ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            contenu()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.fondLegende)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(accent.opacity(0.4), lineWidth: 1)
                )
        )
    }

    /// Une ligne libellé + valeur dans une cellule (masquée si vide).
    /// Style aligné sur l'inspecteur macOS : intitulé en gras, taille body.
    @ViewBuilder
    private func ligne(_ titre: String, _ valeur: String,
                       couleur: Color = .primary,
                       estPrix: Bool = false) -> some View {
        // Règle générale de l'app : un champ vide s'affiche TOUJOURS, avec
        // « Inconnu » à la place de la valeur (voir `afficher`).
        VStack(alignment: .leading, spacing: 2) {
            Text(titre).font(.body).fontWeight(.bold).foregroundStyle(.secondary)
            if estPrix {
                Text(afficher(valeur)).font(.body).foregroundStyle(couleur)
                    .flouteSiPrixMasques()
            } else {
                Text(afficher(valeur)).font(.body).foregroundStyle(couleur)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
