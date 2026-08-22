#if os(iOS)
import SwiftUI
import SwiftData
import UIKit

/// Vue de consultation pour iPhone/iPad (lecture seule).
/// Affiche les entrées d'une catégorie en liste ou en galerie, avec accès
/// à une fiche de détail (photo, prix, informations) au toucher.
struct VueiOS: View {
    let feuille: Feuille?
    let titre: String
    let modesVente: [String]
    let filtreParVendeur: Bool     // filtre par vendeur au lieu du menu de tri
    let statuts: [String]          // statuts recensés par la rubrique
    let types: [String]            // filtre sur le champ Type (vide = aucun)

    init(feuille: Feuille?, titre: String, modesVente: [String] = [],
         filtreParVendeur: Bool = false,
         statuts: [String] = Array(statutsVentesEtDons),
         types: [String] = []) {
        self.feuille = feuille
        self.titre = titre
        self.modesVente = modesVente
        self.filtreParVendeur = filtreParVendeur
        self.statuts = statuts
        self.types = types
    }

    @Query private var toutes: [Oeuvre]
    @State private var tri: [KeyPathComparator<Oeuvre>] = [
        KeyPathComparator(\Oeuvre.type)
    ]
    // Mode d'affichage, conservé entre les sessions (comme sur Mac).
    @AppStorage("modeAffichage") private var modeAffichage: String = "liste"
    // Critère de tri de la galerie (partagé avec le Mac via le même réglage).
    @AppStorage("triGalerie") private var triGalerie: String = "prix"
    // Sens du tri : true = croissant (du plus petit au plus grand).
    @AppStorage("triCroissant") private var triCroissant: Bool = false
    @State private var selection: Set<UUID> = []
    @State private var detail: Oeuvre?
    // Œuvre vers laquelle défiler à la fermeture de la fiche Détails.
    @State private var oeuvreADefiler: UUID?
    // Filtre vendeur actif (uniquement quand filtreParVendeur est vrai).
    @State private var vendeurFiltre: String = "Tout"

    /// Œuvres retenues par la rubrique (feuille, mode de vente, statut, type),
    /// AVANT le filtre par vendeur et avant tri.
    ///
    /// Mis en commun pour que `vendeursPresents` se calcule sur la rubrique
    /// entière : après le filtre, retenir un vendeur ferait disparaître tous
    /// les autres du menu, sans retour possible.
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
        // Filtres propres à la rubrique : statut, et éventuellement type.
        return base.filter { correspond($0, statuts: statuts, types: types) }
    }

    /// Vendeurs réellement présents dans la rubrique, par ordre alphabétique.
    ///
    /// **Déduits des données, aucune liste en dur.** Le menu proposait quatre
    /// entrées figées, dont « RempART » et « Vente privée », qui n'ont rien
    /// vendu aux enchères : elles filtraient donc vers une liste vide. Un lieu
    /// inédit obtient au contraire son entrée dès qu'une œuvre le porte.
    /// Les valeurs vides et « Inconnu » sont écartées.
    private var vendeursPresents: [String] {
        var vus: [String: String] = [:]
        for o in baseRubrique {
            let brut = o.vendeur.trimmingCharacters(in: .whitespacesAndNewlines)
            let cle = brut.lowercased()
            guard !brut.isEmpty,
                  brut.caseInsensitiveCompare(valeurInconnue) != .orderedSame,
                  vus[cle] == nil else { continue }
            vus[cle] = brut
        }
        return vus.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Applique le filtre par vendeur. La comparaison porte sur le seul champ
    /// Vendeur : les entrées du menu en sont issues.
    private func appliquerFiltreVendeur(_ liste: [Oeuvre]) -> [Oeuvre] {
        guard filtreParVendeur, vendeurFiltre != "Tout" else { return liste }
        return liste.filter { $0.vendeur.caseInsensitiveCompare(vendeurFiltre) == .orderedSame }
    }

    /// Œuvres de cette catégorie, filtrées et triées.
    private var oeuvres: [Oeuvre] {
        appliquerFiltreVendeur(baseRubrique).sorted(using: tri)
    }

    private var estFeuilleDon: Bool { feuille == .oeuvresDonnees }

    /// Vrai si la rubrique n'a pas de prix à montrer : dons et Réserve.
    private var rubriqueSansPrix: Bool {
        guard let f = feuille else { return false }
        return feuillesSansPrix.contains(f)
    }

    /// Œuvres triées pour la galerie, selon le critère choisi (prix ou acheteur).
    private var oeuvresGalerie: [Oeuvre] {
        let base = appliquerFiltreVendeur(baseRubrique)
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
    private var recapCell: some View {
        HStack {
            Text("Nombre de ventes")
                .font(.headline)
                .foregroundStyle(Color.texteLegende)
            Spacer()
            Text("\(oeuvresGalerie.count)")
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

    /// Icône du bouton de menu selon le critère actif.
    private var iconeMenu: String {
        if filtreParVendeur {
            return vendeurFiltre == "Tout" ? "person.3" : "person.fill"
        }
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
                    entete: AnyView(recapCell)
                )
            } else {
                liste
            }
        }
        .background(Color.cremeFond)
        .navigationTitle(titre)
        .toolbar {
            // Un seul set de contrôles, compact : Liste, Galerie, tri, sens.
            // Regroupés dans un HStack pour maîtriser l'espacement (plus serré
            // que l'espacement par défaut d'un ToolbarItemGroup).
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

                // 3. Filtre vendeur (Ventes réalisées) ou critère de tri standard.
                if filtreParVendeur {
                    // Mode filtre par vendeur : Tout + chaque vendeur de la liste.
                    Menu {
                        Button {
                            vendeurFiltre = "Tout"
                        } label: {
                            Label(vendeurFiltre == "Tout" ? "✓ Tout" : "Tout",
                                  systemImage: "tray.full")
                        }
                        ForEach(vendeursPresents, id: \.self) { vendeur in
                            Button {
                                vendeurFiltre = vendeur
                            } label: {
                                Text(vendeurFiltre == vendeur ? "✓ \(vendeur)" : vendeur)
                            }
                        }
                    } label: {
                        Image(systemName: iconeMenu)
                    }
                } else {
                    // Mode tri standard : Prix, Acheteur, Dimensions.
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
                recapCell
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
                                            .foregroundStyle(Color.orangeInternational)
                                        if !o.modeVente.isEmpty {
                                            Text(o.modeVente)
                                                .font(.body).foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    } else if o.feuille == .reserve {
                                        // Réserve : l'emplacement remplace le
                                        // couple acheteur / prix. L'intitulé
                                        // vient EN PREMIER, en gris, la valeur
                                        // ensuite — seule, elle ne dit pas de
                                        // quel champ elle relève.
                                        Text("Emplacement")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Text(afficher(o.emplacement))
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
                                                  ? Color.orangeInternational : Color.clear,
                                                  lineWidth: 3)
                            )
                        }
                        .buttonStyle(.plain)
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
                    .onLongPressGesture(minimumDuration: 0.5) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        imagePleinEcranOuverte = true
                    }
                    .fullScreenCover(isPresented: $imagePleinEcranOuverte) {
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
                          couleur: Color.orangeInternational, estPrix: true)
                }
            }

            // Cellule 2 : Type.
            cellule {
                ligne("Type", oeuvre.type)
            }

            // Cellule 3 : Dimensions et Format.
            cellule {
                ligne("Dimensions", oeuvre.dimensions)
                ligne("Format", oeuvre.format)
            }

            // Cellule 4 : Statut, Thème, Emplacement.
            cellule {
                ligne("Statut", oeuvre.statut)
                ligne("Thème", oeuvre.theme)
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
                        .strokeBorder(Color.orangeInternational.opacity(0.4), lineWidth: 1)
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
