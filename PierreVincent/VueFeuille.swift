#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Rend le contenu d'une ligne sélectionnée lisible sur le bleu AppKit.
/// La couleur de fond reste entièrement celle du système ; seules les cellules
/// changent de style, de façon identique dans les trois tableaux.
private struct TexteLigneSelectionnee: ViewModifier {
    let estSelectionnee: Bool
    var couleurAuRepos: Color = .textePrincipal

    func body(content: Content) -> some View {
        content
            .fontWeight(estSelectionnee ? .bold : .regular)
            .foregroundStyle(estSelectionnee ? Color.white : couleurAuRepos)
    }
}

/// Une vue de feuille = un onglet, construite autour du composant natif `Table`
/// de macOS : colonnes redimensionnables, tri par en-tête, sélection multiple
/// et grille gérés nativement. L'édition d'une entrée se fait via une fiche
/// (double-clic sur une ligne, ou bouton Modifier).
struct VueFeuille: View {
    /// Accent de la rubrique — orange dans « Ventes et dons », bleu ardoise
    /// dans la Réserve. Posé sur la colonne de contenu, il descend jusqu'ici.
    @Environment(\.accentRubrique) private var accent

    let feuille: Feuille?          // nil = vue compilée « Œuvres »
    /// Feuille visée par le bouton « Ajouter » — distincte de `feuille`, voir
    /// `Categorie.feuilleAjout`. `nil` = pas de bouton.
    let feuilleAjout: Feuille?
    let lectureSeule: Bool
    let titre: String
    let modesVente: [String]       // filtre supplémentaire sur modeVente (vide = aucun)
    let statuts: [String]          // statuts recensés par la rubrique
    let types: [String]            // filtre sur le champ Type (vide = aucun)
    let themes: [String]           // filtre sur le champ Thème (vide = aucun)
    let collectionSeule: Bool      // ne recenser que la collection personnelle
    let favoriSeul: Bool           // ne recenser que les favoris (rubrique Favoris)
    let filtreParVendeur: Bool     // bandeau de pastilles filtrant par vendeur
    /// Pastilles de type proposées (vide = pas de bandeau). Décidées par la
    /// rubrique, voir `Categorie.typesFiltre`.
    let typesFiltre: [String]

    /// Symbole de l'entrée « Tous » du menu de filtre par type — l'icône de
    /// la rubrique dans les deux Catalogue, la grille générique ailleurs.
    let symboleFiltreTous: String

    let nomEnGalerie: Bool         // ligne de nom en tête de légende de vignette
    let visionneuseIntegree: Bool  // barre d'espace : visionneuse maison au lieu de Quick Look
    /// Nombre d'entrées sélectionnées, remonté vers la sidebar.
    @Binding var nbSelection: Int

    init(feuille: Feuille?, feuilleAjout: Feuille?, lectureSeule: Bool, titre: String,
         modesVente: [String] = [],
         statuts: [String] = Array(statutsVentesEtDons),
         types: [String] = [],
         themes: [String] = [],
         collectionSeule: Bool = false,
         favoriSeul: Bool = false,
         filtreParVendeur: Bool = false,
         typesFiltre: [String] = [],
         symboleFiltreTous: String = "square.grid.2x2",
         nomEnGalerie: Bool = true,
         visionneuseIntegree: Bool = false,
         nbSelection: Binding<Int>) {
        self.feuille = feuille
        self.feuilleAjout = feuilleAjout
        self.lectureSeule = lectureSeule
        self.titre = titre
        self.modesVente = modesVente
        self.statuts = statuts
        self.types = types
        self.themes = themes
        self.collectionSeule = collectionSeule
        self.favoriSeul = favoriSeul
        self.filtreParVendeur = filtreParVendeur
        self.typesFiltre = typesFiltre
        self.symboleFiltreTous = symboleFiltreTous
        self.nomEnGalerie = nomEnGalerie
        self.visionneuseIntegree = visionneuseIntegree
        self._nbSelection = nbSelection
    }

    @Environment(\.modelContext) private var context
    @Query private var toutes: [Oeuvre]

    @State private var tri: [KeyPathComparator<Oeuvre>] = [
        KeyPathComparator(\Oeuvre.type)
    ]
    @State private var selection: Set<UUID> = []
    // Vendeur retenu par le bandeau de pastilles (nil = tous). Non persisté :
    // c'est un filtre de consultation, pas un réglage.
    @State private var vendeurRetenu: String?
    // Type retenu par le bandeau des Dons (nil = tous). Non persisté non plus.
    @State private var typeRetenu: String?
    @State private var editionEntree: Oeuvre?
    @State private var editionNouvelle = false
    @State private var messageExport: String?
    // Vrai pendant la préparation d'un export long (base .pvbase avec images) :
    // affiche un indicateur de progression sans bouton.
    @State private var exportEnCours = false
    @State private var texteProgression = ""
    // Pilote l'affichage de la fenêtre de confirmation de suppression.
    @State private var confirmerSuppression = false
    // Confirmation de l'annulation du dernier import.
    @State private var confirmerAnnulationImport = false
    // URL de l'image à prévisualiser via Quick Look (barre d'espace).
    @State private var apercuURL: URL?
    // Position courante dans la visionneuse intégrée (nil = fermée).
    @State private var indexVisionneuse: Int?
    // Affichage du panneau Inspecteur (mode galerie uniquement).
    // En @AppStorage pour être piloté aussi depuis le menu système « Présentation ».
    @AppStorage("inspecteurVisible") private var inspecteurVisible = false
    // Mode d'affichage : « liste » (tableau) ou « icone » (galerie).
    // Conservé entre les sessions ; « liste » par défaut au tout premier lancement.
    @AppStorage("modeAffichage") private var modeAffichage: String = "icone"
    // Critère de tri de la galerie (indépendant du tri du tableau).
    @AppStorage("triGalerie") private var triGalerie: String = "prix"
    // Sens du tri : true = croissant (du plus petit au plus grand).
    @AppStorage("triCroissant") private var triCroissant: Bool = false
    // Masquage des prix : observé ici pour que l'inspecteur se rafraîchisse.
    @AppStorage("prixMasques") private var prixMasques = false
    // Signaux venus du menu « Édition » pour ouvrir / fermer l'éditeur.
    @AppStorage("signalOuvrirEditeur") private var signalOuvrirEditeur = 0
    @AppStorage("signalFermerEditeur") private var signalFermerEditeur = 0
    // Signaux venus du menu « Édition » pour « Tout sélectionner » et
    // « Supprimer » — ces commandes standard restaient grisées, la sélection
    // et la suppression de cette vue ne passant pas par la chaîne de
    // répondants (voir CLAUDE.md, ⌘A).
    @AppStorage("signalToutSelectionner") private var signalToutSelectionner = 0
    @AppStorage("signalSupprimer") private var signalSupprimer = 0
    // Signal et état pour « Ajouter aux favoris » / « Supprimer des
    // favoris » depuis le menu Édition — pendant Mac du menu contextuel iOS.
    @AppStorage("signalBasculerFavori") private var signalBasculerFavori = 0
    @AppStorage("selectionEstToutFavorite") private var selectionEstToutFavorite = false
    // Action déclenchée depuis le menu « Fichier » (import/export). On stocke le
    // nom de l'action + un compteur pour redéclencher même deux fois de suite.
    @AppStorage("actionFichier") private var actionFichier = ""
    @AppStorage("actionFichierSignal") private var actionFichierSignal = 0
    // États remontés vers le menu « Édition » pour griser « Ouvrir l'éditeur ».
    @AppStorage("uneSelectionExiste") private var uneSelectionExiste = false
    @AppStorage("editeurOuvert") private var editeurOuvert = false
    // Rubrique sans prix à l'écran (Dons ou Réserve) ? Lu par le menu
    // « Présentation » pour y griser « Masquer les prix ». Nom distinct de la
    // propriété calculée `rubriqueSansPrix`, dont il n'est que le report.
    @AppStorage("rubriqueSansPrix") private var signalSansPrix = false
    // Message affiché après un import (déplacé ici pour grouper le set Import).
    @State private var messageImport: String?
    // Message éphémère « Prix masqués / affichés », affiché brièvement lors
    // d'une bascule du masquage des prix. S'éteint tout seul via une tâche
    // asynchrone (même patron que la surbrillance de section iOS).
    @State private var messagePrix: String?
    @State private var tacheMessagePrix: Task<Void, Never>?

    /// Œuvres retenues par la rubrique (feuille, mode de vente, statut, type),
    /// AVANT le filtre par vendeur et avant tri.
    private var baseRubrique: [Oeuvre] {
        var base: [Oeuvre]
        if let f = feuille {
            base = toutes.filter { $0.feuille == f }
        } else if !modesVente.isEmpty {
            // Filtre modeVente actif : on se restreint aux feuilles vendues
            // (tableaux, dessins, tapis) — ni dons, ni réserve.
            base = toutes.filter { !feuillesSansPrix.contains($0.feuille) }
        } else {
            base = toutes
        }
        if !modesVente.isEmpty {
            base = base.filter { modesVente.contains($0.modeVente) }
        }
        // Filtres propres à la rubrique : statut, et éventuellement type.
        // « Ventes et dons » recense les œuvres sorties du fonds ; la Réserve
        // celles encore détenues (voir `Categorie.statuts`).
        base = base.filter {
            correspond($0, statuts: statuts, types: types, themes: themes,
                       collectionSeule: collectionSeule, favoriSeul: favoriSeul)
        }
        return base
    }

    /// Œuvres de cette feuille, triées par le composant.
    private var oeuvres: [Oeuvre] {
        appliquerFiltres(baseRubrique).sorted(using: tri)
    }

    /// Les deux filtres du bandeau, enchaînés. Une rubrique n'en propose
    /// jamais qu'un seul, mais les composer évite de le supposer ici.
    private func appliquerFiltres(_ liste: [Oeuvre]) -> [Oeuvre] {
        appliquerFiltreType(appliquerFiltreVendeur(liste))
    }

    /// Retire les œuvres d'un autre vendeur quand une pastille est retenue.
    private func appliquerFiltreVendeur(_ liste: [Oeuvre]) -> [Oeuvre] {
        guard let v = vendeurRetenu else { return liste }
        return liste.filter { $0.vendeur.caseInsensitiveCompare(v) == .orderedSame }
    }

    /// Retire les œuvres d'un autre type quand une pastille est retenue.
    ///
    /// Test par **inclusion** et non par égalité : le champ `type` porte
    /// encore, sur les données anciennes, des libellés composés du genre
    /// « Tableau — huile sur toile ». Corollaire à connaître : une œuvre dont
    /// le type ne nomme ni l'un ni l'autre n'est retenue par AUCUNE des deux
    /// pastilles. Sans filtre, elle reste visible — c'est l'état par défaut.
    private func appliquerFiltreType(_ liste: [Oeuvre]) -> [Oeuvre] {
        filtrerParType(liste, mot: typeRetenu)
    }

    /// Vrai si la rubrique affiche le bandeau et le menu de filtre par type.
    private var filtreParType: Bool { !typesFiltre.isEmpty }

    /// Vendeurs présents dans la rubrique, pour construire les pastilles.
    ///
    /// Calculés sur `baseRubrique`, AVANT le filtre par vendeur : sinon
    /// sélectionner une pastille ferait disparaître toutes les autres, et on
    /// ne pourrait plus revenir en arrière.
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

    /// Liste dans l'ordre actuellement affiché (galerie ou liste) : sert de base
    /// à la navigation Précédent / Suivant de l'éditeur.
    private var listeAffichee: [Oeuvre] {
        modeAffichage == "icone" ? oeuvresGalerie : oeuvres
    }

    /// Œuvres triées pour la galerie, selon le critère et le sens choisis.
    private var oeuvresGalerie: [Oeuvre] {
        let base = appliquerFiltres(baseRubrique)
        // Critère effectif : on retombe sur un tri pertinent si le critère
        // mémorisé ne s'applique pas à cette feuille.
        var critere = triGalerie
        if rubriqueSansPrix, critere == "prix" { critere = "dimensions" }
        if feuille == .tapisVendus, critere == "dimensions" { critere = "prix" }

        // Tri de base toujours calculé en ordre croissant, puis inversé au besoin.
        let triees: [Oeuvre]
        switch critere {
        case "acheteur":
            // Pour les dons, l'acheteur est vide : on trie sur le destinataire.
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
        return triCroissant ? triees : triees.reversed()
    }

    private var colonnesModele: [Colonne] {
        if let f = feuille { return SchemaFeuille.colonnes(pour: f) }
        return SchemaFeuille.colonnesOeuvres
    }

    private var estFeuilleDon: Bool { feuille == .oeuvresDonnees }

    /// Vrai si la rubrique affichée n'a pas de prix à montrer : les dons et la
    /// Réserve. Distinct de `estFeuilleDon`, qui commande ce qui est propre aux
    /// dons (colonne Destinataire, tableau dédié).
    private var rubriqueSansPrix: Bool {
        guard let f = feuille else { return false }
        return feuillesSansPrix.contains(f)
    }

    // MARK: Contenu de l'Inspecteur (mode galerie)

    /// Œuvre à inspecter : uniquement si EXACTEMENT une vignette est sélectionnée.
    private var oeuvreInspectee: Oeuvre? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return oeuvres.first(where: { $0.id == id })
    }

    /// Contenu du panneau Inspecteur : détails de l'œuvre sélectionnée, ou un
    /// message si aucune (ou plusieurs) vignette n'est sélectionnée.
    @ViewBuilder
    private var inspecteurContenu: some View {
        if let o = oeuvreInspectee {
            // Le caractère « don » se lit sur l'ŒUVRE, pas sur la rubrique :
            // dans les vues agrégées (Inventaire, Ventes), `feuille` vaut nil,
            // et l'inspecteur affichait donc Prix/Vendeur/Acheteur/Date même
            // pour une œuvre donnée — alors que l'éditeur, lui, se fonde déjà
            // sur o.feuille. Les deux vues divergeaient sur les mêmes données.
            let estDon = o.feuille == .oeuvresDonnees
            // Une œuvre en réserve n'a ni prix, ni vendeur, ni acheteur, ni
            // date : elle n'est pas encore sortie du fonds.
            let estReserve = o.feuille == .reserve
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Grande image en tête.
                    if let img = PhotoStore.chargerImage(nom: o.photoNom) {
                        Image(nsImage: img).resizable().scaledToFit()
                            .frame(maxWidth: .infinity)
                            .cornerRadius(10)
                    }

                    // Cellule 1 : Prix (ni pour les dons, ni pour la réserve).
                    if aUnPrix(o) {
                        celluleInspecteur {
                            ligneInspecteur("Prix", formaterEuros(o.prix),
                                            couleur: accent, estPrix: true)
                        }
                    }

                    // Cellule 2 : Type + Thème, CÔTE À CÔTE — même
                    // regroupement et même présentation que dans l'éditeur.
                    celluleInspecteur {
                        HStack(alignment: .top, spacing: 16) {
                            ligneInspecteur("Type", o.type)
                            ligneInspecteur("Thème", o.theme)
                        }
                    }

                    // Cellule 3 : Dimensions et Format, CÔTE À CÔTE — et non
                    // superposés.
                    celluleInspecteur {
                        HStack(alignment: .top, spacing: 16) {
                            ligneInspecteur("Dimensions", o.dimensions)
                            ligneInspecteur("Format", o.format)
                        }
                    }

                    // Cellule 4 : Statut, Emplacement.
                    celluleInspecteur {
                        ligneInspecteur("Statut", o.statut)
                        // Placé AVANT l'emplacement : il dit à quel ensemble
                        // l'œuvre appartient, l'emplacement où la trouver.
                        ligneInspecteur("Collection personnelle",
                                        o.collectionPersonnelle)
                        ligneInspecteur("Lieu de stockage", o.lieuStockage)
                        ligneInspecteur("Emplacement", o.emplacement)
                    }

                    // Cellule 5 : Vendeur-Acheteur, ou Vendeur-Destinataire
                    // pour un don (qui a donné, qui a reçu), puis Mode de
                    // vente. Rien pour la réserve : aucune transaction.
                    if !estReserve {
                        celluleInspecteur {
                            if estDon {
                                ligneInspecteur("Vendeur", o.vendeur)
                                ligneInspecteur("Destinataire", o.destinataire)
                                ligneInspecteur("Mode de vente", o.modeVente)
                            } else {
                                ligneInspecteur("Vendeur", o.vendeur)
                                ligneInspecteur("Acheteur", o.acheteur)
                                ligneInspecteur("Mode de vente", o.modeVente)
                            }
                        }
                    }

                    // Cellule 6 : Date (ni dons, ni réserve).
                    if !estDon && !estReserve {
                        celluleInspecteur {
                            ligneInspecteur("Date", o.date)
                        }
                    }

                    // Cellule 7 : Remarques.
                    celluleInspecteur {
                        ligneInspecteur("Remarques", o.remarques)
                    }

                    // Cellule 8 : la photo stockée — poids, définition, nom
                    // de fichier. Permet de vérifier la compression.
                    celluleInspecteur {
                        ligneInspecteur("Image", PhotoStore.infosImage(nom: o.photoNom))
                    }
                }
                .padding()
            }
        } else if selection.count > 1 && !rubriqueSansPrix {
            // Plusieurs œuvres sélectionnées (hors dons) : total des prix.
            let selectionnees = oeuvres.filter { selection.contains($0.id) }
            let total = selectionnees.reduce(0.0) { $0 + $1.prix }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    celluleInspecteur {
                        ligneInspecteur("Œuvres sélectionnées", "\(selectionnees.count)")
                    }
                    celluleInspecteur {
                        ligneInspecteur("Total des prix", formaterEuros(total),
                                        couleur: accent, estPrix: true)
                    }
                }
                .padding()
            }
        } else {
            // Aucune sélection, ou sélection multiple dans les dons : message.
            VStack {
                Spacer()
                Text(selection.count > 1
                     ? "Plusieurs œuvres sélectionnées"
                     : "Sélectionnez une œuvre")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Une cellule de l'inspecteur, dans le style des tuiles de la Synthèse :
    /// fond crème, coins arrondis, filet orange léger.
    @ViewBuilder
    private func celluleInspecteur<Contenu: View>(
        @ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            contenu()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.cremeFond)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(accent.opacity(0.4), lineWidth: 1)
                )
        )
    }

    /// Une ligne libellé + valeur à l'intérieur d'une cellule (masquée si vide).
    @ViewBuilder
    private func ligneInspecteur(_ titre: String, _ valeur: String,
                                 couleur: Color = .primary,
                                 estPrix: Bool = false) -> some View {
        // Règle générale de l'app : un champ vide s'affiche TOUJOURS, avec
        // « Inconnu » à la place de la valeur (voir `afficher`). L'utilisateur
        // voit ainsi la fiche complète et repère ce qui reste à renseigner.
        VStack(alignment: .leading, spacing: 2) {
            Text(titre).font(.body).fontWeight(.bold).foregroundStyle(.secondary)
            Text(afficher(valeur)).font(.body).foregroundStyle(couleur)
                // Floutage piloté directement par l'état de la vue (fiable
                // dans l'inspecteur, contrairement au modificateur AppStorage).
                .blur(radius: (estPrix && prixMasques) ? 6 : 0)
                .animation(.easeInOut(duration: 0.2), value: prixMasques)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Alignement du contenu des cellules « vente » : centré (toutes les
    /// catégories, y compris « Œuvres », sont désormais éditables).
    private var alignementCellules: Alignment {
        lectureSeule ? .leading : .center
    }

    /// Identité de la rubrique affichée, déduite des paramètres reçus.
    ///
    /// Sert à repartir d'un état propre quand on change de rubrique, SANS
    /// changer l'identité de la vue (voir la remarque sur `.id(cat)` dans
    /// `ContentView`). Le titre seul ne suffirait pas : « Catalogue » désigne
    /// deux rubriques distinctes, une par section de la sidebar.
    private var cleRubrique: String {
        [titre, feuille?.rawValue ?? "",
         statuts.joined(separator: ","),
         types.joined(separator: ","),
         themes.joined(separator: ","),
         collectionSeule ? "collection" : "",
         modesVente.joined(separator: ",")].joined(separator: "|")
    }

    var body: some View {
        contenu
        .navigationTitle("")
        // Changement de rubrique : on remet à zéro ce qui n'a plus de sens
        // ailleurs — la sélection (des UUID absents de la nouvelle liste) et
        // le filtre par vendeur. Le reste est soit persistant et voulu tel
        // (mode d'affichage, tri, inspecteur), soit transitoire.
        .task(id: cleRubrique) {
            // Écrit hors du calcul de `body` : y toucher à un @AppStorage
            // relancerait le rendu en boucle.
            signalSansPrix = rubriqueSansPrix
        }
        .onChange(of: cleRubrique) { _, _ in
            selection = []
            vendeurRetenu = nil
            typeRetenu = nil
            editionEntree = nil
            indexVisionneuse = nil
        }
        // Panneau Inspecteur à droite (mode galerie uniquement) : affiche les
        // détails de la vignette sélectionnée, ou rien si 0 ou plusieurs.
        .inspector(isPresented: $inspecteurVisible) {
            inspecteurContenu
                .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
        }
        // L'inspecteur est réservé au mode galerie : on le ferme si on repasse
        // en mode liste.
        .onChange(of: modeAffichage) { _, nouveau in
            if nouveau != "icone" { inspecteurVisible = false }
        }
        // Ouvrir l'éditeur depuis le menu « Édition » : sur la sélection courante.
        .onChange(of: signalOuvrirEditeur) { _, _ in
            ouvrirModification()
        }
        // Fermer l'éditeur depuis le menu « Édition ».
        .onChange(of: signalFermerEditeur) { _, _ in
            editionEntree = nil
        }
        // « Tout sélectionner » depuis le menu « Édition » : MÊME action que ⌘A.
        .onChange(of: signalToutSelectionner) { _, _ in
            selectionnerTout()
        }
        // « Supprimer » depuis le menu « Édition » : déclenche la MÊME
        // confirmation que le bouton de corbeille (masqué), pas une
        // suppression directe.
        .onChange(of: signalSupprimer) { _, _ in
            if !selection.isEmpty && !lectureSeule {
                confirmerSuppression = true
            }
        }
        // Tient à jour les états lus par le menu « Édition ».
        .onChange(of: editionEntree) { _, nouveau in
            editeurOuvert = (nouveau != nil)
        }
        .onChange(of: selection) { _, nouvelle in
            uneSelectionExiste = !nouvelle.isEmpty
            selectionEstToutFavorite = !nouvelle.isEmpty
                && oeuvres.filter { nouvelle.contains($0.id) }.allSatisfy { $0.favori }
            nbSelection = nouvelle.count
            // Sélectionner une œuvre (clic en liste ou en galerie) donne la
            // main au clavier au panneau de contenu.
            if !nouvelle.isEmpty { ZoneClavier.definir(ZoneClavier.contenu) }
        }
        // Action import/export déclenchée depuis le menu « Fichier ».
        .onChange(of: actionFichierSignal) { _, _ in
            executerActionFichier(actionFichier)
        }
        .toolbar {
            contenuBarreOutils
        }
        .sheet(item: $editionEntree, onDismiss: {
            // Réinitialisation explicite : évite que l'état reste « occupé »
            // et empêche la réouverture de l'éditeur (bug intermittent).
            editionEntree = nil
        }) { o in
            EditeurEntree(
                feuille: o.feuille,
                oeuvre: o,
                estNouvelle: editionNouvelle,
                onValider: { try? context.save() },
                onAnnuler: {
                    if editionNouvelle {
                        if !o.photoNom.isEmpty { PhotoStore.supprimerPhoto(nom: o.photoNom) }
                        context.delete(o)
                    }
                },
                onFermer: {
                    editionEntree = nil
                },
                onEnregistrerEtNouveau: {
                    guard let f = feuille else { return nil }
                    let nouvelle = Oeuvre(feuille: f)
                    context.insert(nouvelle)
                    return nouvelle
                },
                // En modification, on passe la liste ordonnée pour naviguer ;
                // en création, liste vide (pas de navigation).
                listeNavigation: editionNouvelle ? [] : listeAffichee,
                onNaviguer: { nouvelle in
                    // Suit la navigation de l'éditeur : sélectionne l'œuvre
                    // affichée dans la fenêtre principale en arrière-plan.
                    selection = [nouvelle.id]
                }
            )
            // La pastille est posée SUR l'éditeur en plus de la fenêtre
            // principale. Une feuille (`.sheet`) se présente au-dessus de
            // toute la hiérarchie qui l'ouvre : un overlay posé plus bas
            // reste donc derrière, quelle que soit sa place. Les deux
            // partagent le même état, il n'y a rien à synchroniser.
            .overlay(alignment: .top) { bandeauPrix }
            .animation(.easeInOut(duration: 0.2), value: messagePrix)
        }
        .modifier(AlertesFeuille(
            confirmerSuppression: $confirmerSuppression,
            titreConfirmation: titreConfirmation,
            messageImport: $messageImport,
            onSupprimer: { supprimerSelection() }))
        // Annulation du dernier import : confirmation explicite, l'opération
        // étant définitive et pouvant porter sur des centaines d'œuvres.
        .alert("Annuler le dernier import ?",
               isPresented: $confirmerAnnulationImport) {
            Button("Annuler l'importation", role: .destructive) {
                let n = DernierImport.annuler(context: context)
                messageImport = "\(n) œuvre(s) supprimée(s)."
            }
            Button("Ne rien faire", role: .cancel) {}
        } message: {
            Text("\(DernierImport.nombre) œuvre(s) et leurs photos seront "
                 + "supprimées définitivement. Les œuvres saisies à la main et "
                 + "les imports antérieurs ne sont pas touchés.")
        }
        // Quick Look natif : affiche l'image de la ligne sélectionnée.
        .apercuQuickLook($apercuURL)
        // Panneau centré unique : progression (indicateur) puis message final
        // (avec OK), toujours au même endroit.
        .overlay {
            if exportEnCours || messageExport != nil {
                panneauProgression
            }
        }
        // Message éphémère lors d'une bascule du masquage des prix.
        .overlay(alignment: .top) { bandeauPrix }
        .animation(.easeInOut(duration: 0.2), value: messagePrix)
        // Déclenché par la VALEUR, pas par le bouton : la bascule est aussi
        // possible depuis le menu « Présentation », et le message doit
        // apparaître dans les deux cas.
        .onChange(of: prixMasques) { _, masques in
            messagePrix = masques ? "Prix masqués" : "Prix affichés"
            tacheMessagePrix?.cancel()
            tacheMessagePrix = Task {
                try? await Task.sleep(nanoseconds: 840_000_000)   // 0,84 s
                if !Task.isCancelled { messagePrix = nil }
            }
        }
        .modifier(RaccourcisClavier(
            editionActive: editionEntree != nil,
            visionneuseOuverte: indexVisionneuse != nil,
            onApercu: { declencherApercu() },
            onToutSelectionner: { selectionnerTout() },
            onDeselectionner: { selection = [] },
            onSupprimer: {
                if !selection.isEmpty && !lectureSeule {
                    confirmerSuppression = true
                }
            }))
        // Le filtre par vendeur ne survit pas au changement de rubrique :
        // c'est `.onChange(of: cleRubrique)` plus haut qui le remet à nil.
        // (La vue n'est plus recréée par un `.id(cat)`, retiré depuis.)
        .onAppear {
            nbSelection = selection.count
            uneSelectionExiste = !selection.isEmpty
            selectionEstToutFavorite = !selection.isEmpty
                && oeuvres.filter { selection.contains($0.id) }.allSatisfy { $0.favori }
            editeurOuvert = (editionEntree != nil)
        }
        // « Ajouter aux favoris » / « Supprimer des favoris » depuis le menu
        // Édition.
        .onChange(of: signalBasculerFavori) { _, _ in
            basculerFavoriSelection()
        }
    }

    /// Sélectionne toutes les entrées de la catégorie affichée.
    private func selectionnerTout() {
        // `listeAffichee` et non `oeuvres` : c'est la liste réellement à
        // l'écran, galerie comme liste.
        selection = Set(listeAffichee.map { $0.id })
    }

    /// Exécute l'action import/export demandée par le menu « Fichier ».
    private func executerActionFichier(_ action: String) {
        switch action {
        case "importer":     importerDonnees()
        case "importerPhotos": importerPhotos()
        case "annulerImport": confirmerAnnulationImport = true
        case "csv":          exporterCSV()
        case "xls":          exporterXLS()
        case "dossier":      exporterDossier()
        case "xlsx":         exporterXLSXImages()
        case "base":         exporterBase()
        case "pdf":          exporterPDF()
        default:             break
        }
    }

    /// Contenu de la barre d'outils, extrait dans une propriété pour éviter que
    /// le compilateur peine à vérifier le type d'une expression trop grosse.
    ///
    /// Important : aucun `placement:` explicite sur les items ni les spacers.
    /// Avec placement: .primaryAction, les items s'étalent sur toute la largeur
    /// de fenêtre (inspecteur inclus). Sans placement, macOS 26 les confine
    /// automatiquement à la section toolbar du panneau de contenu — le pattern
    /// de l'exemple Landmarks d'Apple.
    /// Vrai tant que la visionneuse occupe le panneau : tous les boutons de la
    /// barre d'outils sont alors grisés, **sauf l'Inspecteur** — lui reste utile,
    /// il montre les détails de l'œuvre qu'on est en train de regarder.
    private var barreOutilsInactive: Bool { indexVisionneuse != nil }

    @ToolbarContentBuilder
    private var contenuBarreOutils: some ToolbarContent {
        // Spacer flexible en tête : pousse tous les boutons vers la droite
        // du panneau de contenu (jamais au-dessus de la colonne inspecteur).
        ToolbarSpacer(.flexible)

        // === Set 1 : création / suppression / modification ===
        if !lectureSeule {
            if let f = feuilleAjout {
                ToolbarItem {
                    Button {
                        let o = Oeuvre(feuille: f)
                        context.insert(o)
                        editionNouvelle = true
                        editionEntree = o
                    } label: { Label("Ajouter", systemImage: "plus") }
                    .disabled(barreOutilsInactive)
                }
            }
            // Essai : bouton masqué, voir `afficherBoutonCorbeilleToolbar`.
            // La commande « Supprimer » du menu Édition déclenche la même
            // confirmation.
            if afficherBoutonCorbeilleToolbar {
                ToolbarItem {
                    Button(role: .destructive) {
                        confirmerSuppression = true
                    } label: { Label(labelSupprimer, systemImage: "trash") }
                    .disabled(selection.isEmpty || barreOutilsInactive)
                }
            }
            if selection.count == 1 {
                ToolbarItem {
                    Button {
                        if let id = selection.first, let o = oeuvres.first(where: { $0.id == id }) {
                            editionNouvelle = false
                            editionEntree = o
                        }
                    } label: { Label("Modifier", systemImage: "pencil") }
                    .disabled(barreOutilsInactive)
                }
            }
        }
        // Masquage des prix : sans objet là où les œuvres n'en ont pas —
        // Dons et Réserve. Le menu « Présentation » grise la commande au même
        // moment, via `signalSansPrix`.
        if !rubriqueSansPrix {
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Button {
                    prixMasques.toggle()
                } label: {
                    Image(systemName: prixMasques ? "eye.slash" : "eye")
                }
                .disabled(barreOutilsInactive)
                .help(prixMasques ? "Afficher les prix" : "Masquer les prix")
            }
        }
        ToolbarSpacer(.fixed)
        // Alternative aux pastilles du bandeau : même filtre, même état.
        // En TÊTE de la capsule, avant les boutons de présentation.
        // Retiré pour l'instant, comme sur iOS : voir `afficherMenuFiltreTypeToolbar`.
        if afficherMenuFiltreTypeToolbar && filtreParType {
            ToolbarItem { menuFiltreType }
        }
        // Galerie en tête : c'est la présentation par défaut à la première
        // ouverture d'une vue (`modeAffichage` vaut "icone").
        ToolbarItem {
            Button {
                modeAffichage = "icone"
            } label: { Label("Galerie", systemImage: "square.grid.2x2") }
            .disabled(modeAffichage == "icone" || barreOutilsInactive)
        }
        ToolbarItem {
            Button {
                modeAffichage = "liste"
            } label: { Label("Liste", systemImage: "list.bullet") }
            .disabled(modeAffichage == "liste" || barreOutilsInactive)
        }

        // === Tri + sens + inspecteur (galerie seulement) ===
        if modeAffichage == "icone" {
            ToolbarSpacer(.fixed)
            // Favoris n'a ni critère ni sens de tri : l'œuvre peut être
            // vendue, donnée ou encore en réserve, sans champ commun qui
            // fasse un tri sensé. Retiré comme sur iOS, la galerie et la
            // liste restant seules présentations.
            if !favoriSeul {
                ToolbarItemGroup {
                    // Menu de critère : sans objet dans la Réserve, dont les
                    // œuvres n'ont ni prix ni acheteur. Le bouton de sens reste,
                    // le tri par dimensions y gardant du sens.
                    if feuille != .reserve {
                        menuTri
                            .disabled(barreOutilsInactive)
                    }
                    Button {
                        triCroissant.toggle()
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .scaleEffect(x: 1, y: triCroissant ? -1 : 1)
                    }
                    .disabled(barreOutilsInactive)
                    .help(triCroissant ? "Tri croissant" : "Tri décroissant")
                }
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Button {
                    inspecteurVisible.toggle()
                } label: {
                    Label("Inspecteur", systemImage: "info.circle")
                }
                .help(inspecteurVisible ? "Masquer l'inspecteur" : "Afficher l'inspecteur")
            }
        }
    }

    /// Icône du bouton de menu de tri selon le critère actif (comme sur iOS).
    private var iconeMenuTri: String {
        if rubriqueSansPrix {
            return triGalerie == "acheteur" ? "person" : "ruler"
        }
        switch triGalerie {
        case "acheteur":   return "person"
        case "dimensions": return "ruler"
        default:           return "eurosign"
        }
    }

    /// Menu de filtre par type — alternative aux pastilles du bandeau.
    ///
    /// Les deux pilotent le MÊME état `typeRetenu` : changer l'un met l'autre
    /// à jour, il n'y a pas deux filtres à tenir d'accord.
    private var menuFiltreType: some View {
        Menu {
            Button {
                typeRetenu = nil
            } label: {
                Label(typeRetenu == nil ? "✓ Tout" : "Tout",
                      systemImage: symboleFiltreTous)
                    .labelStyle(.titleAndIcon)
            }
            ForEach(typesFiltre, id: \.self) { mot in
                let libelle = libelleTypeFiltrable(mot)
                Button {
                    typeRetenu = mot
                } label: {
                    Label(typeRetenu == mot ? "✓ \(libelle)" : libelle,
                          systemImage: symboleTypeFiltrable(mot))
                        .labelStyle(.titleAndIcon)
                }
            }
        } label: {
            // L'icône dit le CRITÈRE ACTIF, exactement comme celle du menu
            // de tri : le type retenu quand il y en a un, et sinon l'icône de
            // l'entrée « Tous » — donc celle de la rubrique dans les deux
            // Catalogue. Un symbole de filtre générique ne disait rien de
            // l'état courant.
            Image(systemName: typeRetenu.map(symboleTypeFiltrable)
                              ?? symboleFiltreTous)
        }
        .help("Filtrer par type")
    }



    /// Menu de choix du critère de tri (galerie).
    private var menuTri: some View {
        Menu {
            if !rubriqueSansPrix {
                Button {
                    triGalerie = "prix"
                } label: {
                    Label(triGalerie == "prix" ? "✓ Prix" : "Prix", systemImage: "eurosign")
                        .labelStyle(.titleAndIcon)
                }
            }
            Button {
                triGalerie = "acheteur"
            } label: {
                Label(triGalerie == "acheteur" ? "✓ Acheteur" : "Acheteur", systemImage: "person")
                    .labelStyle(.titleAndIcon)
            }
            if feuille != .tapisVendus {
                Button {
                    triGalerie = "dimensions"
                } label: {
                    Label(triGalerie == "dimensions" ? "✓ Dimensions" : "Dimensions", systemImage: "ruler")
                        .labelStyle(.titleAndIcon)
                }
            }
        } label: {
            // Image seule, comme sur iOS : avec un `Label`, la toolbar macOS
            // n'affiche que le titre (« Trier ») et l'icône du critère actif
            // — tout l'intérêt du réglage — passait à la trappe.
            Image(systemName: iconeMenuTri)
        }
        .help("Trier")
        .accessibilityLabel("Trier")
    }

    /// Bandeau éphémère « Prix masqués » / « Prix affichés », en haut du
    /// panneau de contenu. Simple indication passagère : aucun bouton, il
    /// disparaît de lui-même.
    @ViewBuilder
    private var bandeauPrix: some View {
        if let messagePrix {
            HStack(spacing: 8) {
                Image(systemName: prixMasques ? "eye.slash" : "eye")
                Text(messagePrix)
            }
            .font(.headline)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(accent.opacity(0.4), lineWidth: 1))
            .shadow(radius: 10)
            .padding(.top, 18)
            .transition(.opacity)
            .allowsHitTesting(false)   // ne doit jamais gêner le clic
        }
    }

    /// Panneau modal centré, commun à la progression et au message final d'un
    /// export. Toujours affiché au même endroit (au centre de la fenêtre).
    private var panneauProgression: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 16) {
                if exportEnCours {
                    // Étape en cours : indicateur d'activité + texte.
                    ProgressView()
                        .controlSize(.large)
                    Text(texteProgression)
                        .font(.body)
                        .multilineTextAlignment(.center)
                } else {
                    // Étape terminée : titre, message et bouton de fermeture.
                    Text("Export terminé")
                        .font(.headline)
                    Text(messageExport ?? "")
                        .font(.body)
                        .multilineTextAlignment(.center)
                    Button("OK") { messageExport = nil }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(radius: 20)
            )
        }
    }

    /// Œuvres de la rubrique qui ont réellement une photo — ce que parcourt
    /// la visionneuse intégrée.
    private var oeuvresAvecPhoto: [Oeuvre] {
        listeAffichee.filter { !$0.photoNom.isEmpty }
    }

    /// Ouvre l'aperçu de la ligne sélectionnée (barre d'espace).
    /// Un nouvel appui le referme, comme dans le Finder.
    ///
    /// Deux chemins : la **visionneuse intégrée** dans les rubriques qui la
    /// déclarent (essai en cours, Réserve › Catalogue), **Quick Look** partout
    /// ailleurs. Le second n'a pas été touché.
    private func declencherApercu() {
        if visionneuseIntegree {
            if indexVisionneuse != nil { indexVisionneuse = nil; return }
            guard let id = selection.first,
                  let i = oeuvresAvecPhoto.firstIndex(where: { $0.id == id })
            else { return }
            indexVisionneuse = i
            return
        }
        if QuickLookController.shared.estVisible {
            QuickLookController.shared.fermer()
            return
        }
        guard let id = selection.first,
              let o = oeuvres.first(where: { $0.id == id }),
              !o.photoNom.isEmpty,
              let url = PhotoStore.urlPhoto(nom: o.photoNom) else { return }
        apercuURL = url
    }

    // MARK: Barre d'outils (fond orange, titre + boutons blancs)

    private var labelSupprimer: String {
        selection.count > 1 ? "Supprimer (\(selection.count))" : "Supprimer"
    }

    /// Titre de la fenêtre de confirmation, adapté au nombre d'entrées.
    private var titreConfirmation: String {
        if selection.count > 1 {
            return "Supprimer ces \(selection.count) entrées ?"
        }
        return "Supprimer cette entrée ?"
    }

    // MARK: Tableau natif

    /// Contenu principal : galerie (par icône) ou tableau (par liste).
    @ViewBuilder
    private var contenu: some View {
        // `safeAreaInset` et NON un VStack : le contenu continue de défiler
        // SOUS le bandeau et sous la toolbar, condition pour que l'un et
        // l'autre gardent leur translucidité. Empilé dans un VStack, le
        // bandeau opaque coupait la zone de défilement et les deux barres
        // devenaient pleines.
        contenuPrincipal
            .safeAreaInset(edge: .top, spacing: 0) {
                if filtreParVendeur || filtreParType {
                    bandeauFiltres
                }
            }
            // Visionneuse intégrée : en `overlay` sur le panneau, donc bornée
            // à celui-ci. Une `.sheet` couvrirait toute la fenêtre, sidebar et
            // barre d'outils comprises.
            .overlay {
                if let i = indexVisionneuse, !oeuvresAvecPhoto.isEmpty {
                    VisionneusePanneau(
                        oeuvres: oeuvresAvecPhoto,
                        index: Binding(
                            get: { min(i, oeuvresAvecPhoto.count - 1) },
                            set: { nouveau in
                                indexVisionneuse = nouveau
                                // Garde la sélection du panneau en phase, pour
                                // que fermer la visionneuse laisse l'œuvre
                                // consultée sélectionnée dessous.
                                if oeuvresAvecPhoto.indices.contains(nouveau) {
                                    selection = [oeuvresAvecPhoto[nouveau].id]
                                }
                            }),
                        onFermer: {
                            // Réaffirme la sélection sur l'œuvre consultée :
                            // le panneau doit la montrer, filet orange
                            // compris, dès que la visionneuse s'efface.
                            if oeuvresAvecPhoto.indices.contains(i) {
                                selection = [oeuvresAvecPhoto[i].id]
                            }
                            indexVisionneuse = nil
                            // PAS de centrage : l'œuvre doit simplement être
                            // sélectionnée et VISIBLE. Le défilement suit la
                            // sélection tout seul — `scrollRowToVisible` en
                            // liste, `scrollTo` en galerie — et il opère déjà
                            // pendant la navigation, sous la visionneuse.
                        })
                }
            }
    }

    /// Bandeau de pastilles filtrant le panneau, en haut de celui-ci.
    ///
    /// Deux sortes selon la rubrique, jamais les deux à la fois :
    /// - **par vendeur** (enchères, expositions) : construit d'après les
    ///   vendeurs réellement présents, aucune liste en dur, un lieu inédit
    ///   obtient sa pastille de lui-même ;
    /// - **par type** (Dons) : deux pastilles fixes, Tableaux et Dessins. Fixes
    ///   et non déduites, parce que le champ `type` porte encore des libellés
    ///   composés : les valeurs distinctes ne feraient pas deux pastilles mais
    ///   des dizaines.
    ///
    /// Le bandeau s'affiche dès que la rubrique le déclare, même sans aucune
    /// pastille : le compteur, lui, a toujours du sens.
    private var bandeauFiltres: some View {
        HStack(alignment: .center, spacing: 8) {
            // Les pastilles défilent si elles débordent…
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if filtreParVendeur {
                        ForEach(vendeursPresents, id: \.self) { vendeur in
                            pastilleVendeur(vendeur)
                        }
                    }
                    if filtreParType {
                        ForEach(typesFiltre, id: \.self) { mot in
                            pastilleType(libelle: libelleTypeFiltrable(mot),
                                         mot: mot)
                        }
                    }
                }
            }
            // `ScrollView` réserve sinon une hauteur légèrement supérieure à
            // celle de son contenu (place laissée à la barre de défilement,
            // même masquée) : le texte des pastilles se retrouvait alors
            // centré un peu plus haut que celui du compteur, posé lui
            // directement dans le HStack. `.fixedSize` force le ScrollView à
            // prendre exactement la hauteur de son contenu, et le
            // centrage du HStack aligne alors les deux textes.
            .fixedSize(horizontal: false, vertical: true)
            // …tandis que le compteur reste ancré à droite, hors du défilement.
            pastilleCompteur
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // Matériau le PLUS FIN du catalogue, pour prolonger l'effet de verre
        // de la toolbar sans l'épaissir : le contenu qui défile dessous doit
        // être flouté comme il l'est sous la barre, et non passer net derrière
        // les pastilles.
        //
        // Un essai précédent sans aucun fond laissait justement le contenu
        // net ; un matériau plus épais (`regularMaterial`) faisait au
        // contraire lire les deux barres comme un seul bandeau lourd.
        .background(.ultraThinMaterial)
    }

    /// Compteur des œuvres affichées, à droite du bandeau. Il suit le filtre :
    /// retenir un vendeur met à jour le nombre. Non interactif — c'est une
    /// indication, pas un bouton.
    private var pastilleCompteur: some View {
        Text("\(listeAffichee.count)")
            // Même corps que les libellés de rubrique de la sidebar : 13 pt.
            .font(.system(size: 13))
            // Toujours rempli de l'accent de la section (orange ou bleu
            // ardoise), texte blanc — contrairement aux pastilles de filtre,
            // qui ne se remplissent qu'une fois retenues.
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background { Capsule().fill(accent) }
            .help("Nombre d'œuvres affichées")
    }

    /// Une pastille : contour orange et texte sombre au repos, fond orange et
    /// texte blanc une fois retenue. Même corps que les pastilles de comptage
    /// de la sidebar (11 pt semi-gras, capsule).
    private func pastilleVendeur(_ vendeur: String) -> some View {
        let retenu = vendeurRetenu?.caseInsensitiveCompare(vendeur) == .orderedSame
        return Button {
            // Un second clic sur la pastille retenue lève le filtre.
            vendeurRetenu = retenu ? nil : vendeur
        } label: {
            Text(vendeur)
                // Même corps que les libellés de rubrique de la sidebar :
                // 13 pt, en gras une fois retenu — et non le 11 pt des
                // pastilles de comptage.
                .font(.system(size: 13))
                // ESSAI VISUEL : le libellé retenu ne passe plus en gras, seuls le
                // fond plein et le texte blanc marquent la sélection.
                .fontWeight(.regular)
                .foregroundStyle(retenu ? Color.white : Color.textePrincipal)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    if retenu {
                        Capsule().fill(accent)
                    } else {
                        Capsule().strokeBorder(accent, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(retenu ? "Afficher tous les vendeurs" : "N'afficher que « \(vendeur) »")
    }

    /// Pastille de type — même apparence que celle de vendeur.
    private func pastilleType(libelle: String, mot: String) -> some View {
        let retenu = typeRetenu?.caseInsensitiveCompare(mot) == .orderedSame
        return Button {
            // Un second clic sur la pastille retenue lève le filtre.
            typeRetenu = retenu ? nil : mot
        } label: {
            Text(libelle)
                .font(.system(size: 13))
                // ESSAI VISUEL : le libellé retenu ne passe plus en gras, seuls le
                // fond plein et le texte blanc marquent la sélection.
                .fontWeight(.regular)
                .foregroundStyle(retenu ? Color.white : Color.textePrincipal)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    if retenu {
                        Capsule().fill(accent)
                    } else {
                        Capsule().strokeBorder(accent, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(retenu ? "Afficher tous les types" : "N'afficher que « \(libelle) »")
    }

    @ViewBuilder
    private var contenuPrincipal: some View {
        if modeAffichage == "icone" {
            VueGalerie(
                oeuvres: oeuvresGalerie,
                selection: $selection,
                onOuvrir: { o in
                    if !lectureSeule { editionNouvelle = false; editionEntree = o }
                },
                nomEnGalerie: nomEnGalerie
            )
        } else {
            // Navigation clavier : capteur NSEvent au niveau fenêtre, actif
            // seulement quand la zone clavier est le panneau de contenu.
            // Ni onKeyPress ni @FocusState : voir ZoneClavier (CaptureEspace.swift)
            // et la section « pièges » de CLAUDE.md.
            tableau
                // Fond du tableau suivant le thème : contrairement à la
                // galerie et à la Synthèse, qui peignent leur propre
                // Color.cremeFond, le Table affichait le fond AppKit par
                // défaut et ne suivait donc aucun thème.
                .scrollContentBackground(.hidden)
                .background(Color.cremeFond)
                .background(
                    CaptureFleches(zone: ZoneClavier.contenu,
                                   suspendu: editionEntree != nil
                                             || indexVisionneuse != nil) { delta in
                        naviguerListe(delta: delta)
                    }
                )
                // Défilement vers la ligne sélectionnée, en VERTICAL seulement.
                .background(DefilementTableau(ligne: ligneSelectionnee))
                // Le même NSTableView est réutilisé quand on change de
                // rubrique. On réimpose donc son style bleu natif ici, afin
                // qu'un réglage laissé par une vue précédente ne le fasse
                // jamais passer en gris.
                .background(ForceSelectionBleueTableau())
        }
    }

    /// Indice de la ligne sélectionnée dans la liste triée courante
    /// (nil si aucune ou plusieurs) : sert au défilement automatique.
    private var ligneSelectionnee: Int? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return oeuvres.firstIndex(where: { $0.id == id })
    }

    /// Déplace la sélection d'une ligne (−1 = ↑, +1 = ↓). Si rien n'est
    /// sélectionné, on entre par le haut ou par le bas de la liste — plutôt
    /// que de ne rien faire, ce qui laissait l'utilisateur sans repère.
    private func naviguerListe(delta: Int) {
        guard !oeuvres.isEmpty else { return }
        guard selection.count == 1,
              let id = selection.first,
              let idx = oeuvres.firstIndex(where: { $0.id == id }) else {
            selection = [delta > 0 ? oeuvres[0].id : oeuvres[oeuvres.count - 1].id]
            return
        }
        let nouveau = idx + delta
        guard nouveau >= 0, nouveau < oeuvres.count else { return }
        selection = [oeuvres[nouveau].id]
    }

    @ViewBuilder
    private var tableau: some View {
        if estFeuilleDon {
            tableDon
        } else if feuille == .reserve {
            tableReserve
        } else {
            tableVente
        }
    }

    /// Tableau de la Réserve : les colonnes de transaction (Prix, Vendeur,
    /// Acheteur, Mode de vente, Date) n'ont pas lieu d'être, et il n'y a pas
    /// non plus de destinataire. Huit colonnes, sous la limite de dix.
    private var tableReserve: some View {
        Table(oeuvres, selection: $selection, sortOrder: $tri) {
            TableColumn("Photo") { (o: Oeuvre) in
                Color.clear.frame(width: 1, height: hauteurContenu)
                    .overlay(alignment: .leading) { vignette(o) }
            }
            .width(96)
            TableColumn("Type", value: \Oeuvre.type) { o in
                Text(o.type)
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: .center)
            }
            TableColumn("Dimensions", value: \Oeuvre.dimensions) { o in
                Text(o.dimensions)
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: .center)
            }
            TableColumn("Format", value: \Oeuvre.format) { o in
                Text(o.format)
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: .center)
            }
            TableColumn("Statut", value: \Oeuvre.statut) { o in
                Text(afficher(o.statut))
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: .center)
            }
            TableColumn("Thème", value: \Oeuvre.theme) { o in
                Text(afficher(o.theme))
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: .center)
            }
            TableColumn("Emplacement", value: \Oeuvre.emplacement) { o in
                Text(afficher(o.emplacement))
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: .center)
            }
            TableColumn("Remarques", value: \Oeuvre.remarques) { o in
                Text(o.remarques)
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(minHeight: hauteurContenu, alignment: .leading)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { _ in
            menuContextuel
        } primaryAction: { ids in
            ouvrirDepuisDoubleClic(ids)
        }
    }

    /// Hauteur de contenu qui donne des rangées « un peu plus hautes ».
    private let hauteurContenu: CGFloat = 90

    /// Tableau des 4 feuilles « vendues » (+ vue compilée « Œuvres »).
    private var tableVente: some View {
        Table(oeuvres, selection: $selection, sortOrder: $tri) {
            TableColumn("Photo") { (o: Oeuvre) in
                Color.clear.frame(width: 1, height: hauteurContenu)
                    .overlay(alignment: .leading) { vignette(o) }
            }
            .width(96)
            TableColumn("Prix", value: \Oeuvre.prix) { o in
                Text(formaterEuros(o.prix))
                    .modifier(TexteLigneSelectionnee(
                        estSelectionnee: selection.contains(o.id),
                        couleurAuRepos: accent))
                    .blur(radius: prixMasques ? 5 : 0)
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
            }
            TableColumn("Type", value: \Oeuvre.type) { o in
                Text(o.type)
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
            }
            TableColumn("Dimensions", value: \Oeuvre.dimensions) { o in
                Text(o.dimensions)
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
            }
            TableColumn("Format", value: \Oeuvre.format) { o in
                Text(o.format)
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
            }
            TableColumn("Vendeur", value: \Oeuvre.vendeur) { o in
                Text(o.vendeur)
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
            }
            TableColumn("Acheteur", value: \Oeuvre.acheteur) { o in
                Text(o.acheteur)
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
            }
            TableColumn("Mode de vente", value: \Oeuvre.modeVente) { o in
                Text(o.modeVente)
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
            }
            TableColumn("Date", value: \Oeuvre.date) { o in
                Text(o.date)
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
            }
            // Regroupées : le builder de `Table` n'accepte que 10 colonnes
            // au premier niveau, et ce tableau en compte désormais 13.
            Group {
                TableColumn("Statut", value: \Oeuvre.statut) { o in
                    Text(afficher(o.statut))
                        .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                        .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
                }
                TableColumn("Thème", value: \Oeuvre.theme) { o in
                    Text(afficher(o.theme))
                        .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                        .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
                }
                TableColumn("Emplacement", value: \Oeuvre.emplacement) { o in
                    Text(afficher(o.emplacement))
                        .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                        .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
                }
                TableColumn("Remarques", value: \Oeuvre.remarques) { o in
                    Text(o.remarques)
                        .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                        .frame(minHeight: hauteurContenu, alignment: .leading)
                }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { _ in
            menuContextuel
        } primaryAction: { ids in
            ouvrirDepuisDoubleClic(ids)
        }
    }

    /// Tableau de la feuille « Œuvres données ».
    private var tableDon: some View {
        Table(oeuvres, selection: $selection, sortOrder: $tri) {
            TableColumn("Photo") { (o: Oeuvre) in
                Color.clear.frame(width: 1, height: hauteurContenu)
                    .overlay(alignment: .leading) { vignette(o) }
            }
            .width(96)
            TableColumn("Destinataire", value: \Oeuvre.destinataire) { o in
                Text(o.destinataire)
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(minHeight: hauteurContenu, alignment: .leading)
            }
            TableColumn("Type", value: \Oeuvre.type) { o in
                Text(o.type)
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: .center)
            }
            TableColumn("Dimensions", value: \Oeuvre.dimensions) { o in
                Text(o.dimensions)
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: .center)
            }
            TableColumn("Format", value: \Oeuvre.format) { o in
                Text(o.format)
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: .center)
            }
            TableColumn("Statut", value: \Oeuvre.statut) { o in
                Text(afficher(o.statut))
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: .center)
            }
            TableColumn("Thème", value: \Oeuvre.theme) { o in
                Text(afficher(o.theme))
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: .center)
            }
            TableColumn("Emplacement", value: \Oeuvre.emplacement) { o in
                Text(afficher(o.emplacement))
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: .center)
            }
            TableColumn("Remarques", value: \Oeuvre.remarques) { o in
                Text(o.remarques)
                    .modifier(TexteLigneSelectionnee(estSelectionnee: selection.contains(o.id)))
                    .frame(minHeight: hauteurContenu, alignment: .leading)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { _ in
            menuContextuel
        } primaryAction: { ids in
            ouvrirDepuisDoubleClic(ids)
        }
    }

    @ViewBuilder
    private var menuContextuel: some View {
        if !lectureSeule {
            Button("Modifier") { ouvrirModification() }
            if selection.count == 1 {
                Button("Dupliquer") { dupliquerSelection() }
            }
            Button("Supprimer…", role: .destructive) { confirmerSuppression = true }
            Divider()
        }
        // Pendant Mac du menu contextuel iOS — même bascule que la commande
        // du menu Édition, mais calculée ici sur `selection` directement :
        // le signal `@AppStorage` sert à faire remonter l'action jusqu'au
        // menu Édition (une scène différente), il n'a pas à transiter par
        // là pour un menu posé sur la vue elle-même.
        Button(selectionToutFavorite ? "Retirer des favoris" : "Ajouter aux favoris") {
            basculerFavoriSelection()
        }
    }

    /// Vrai si la sélection n'est pas vide et l'est ENTIÈREMENT déjà favorite.
    private var selectionToutFavorite: Bool {
        !selection.isEmpty
            && oeuvres.filter { selection.contains($0.id) }.allSatisfy { $0.favori }
    }

    /// Bascule TOUTE la sélection vers l'état opposé à `selectionToutFavorite`
    /// — comme un « marquer » à bascule sur plusieurs éléments, pas un simple
    /// `.toggle()` œuvre par œuvre, qui mélangerait les états sur une
    /// sélection hétérogène. Point de passage UNIQUE pour le menu Édition et
    /// le menu contextuel, qui ne doivent pas diverger.
    private func basculerFavoriSelection() {
        let selectionnees = oeuvres.filter { selection.contains($0.id) }
        guard !selectionnees.isEmpty else { return }
        let nouvelEtat = !selectionToutFavorite
        for o in selectionnees { o.favori = nouvelEtat }
        try? context.save()
        selectionEstToutFavorite = nouvelEtat
    }

    private func ouvrirDepuisDoubleClic(_ ids: Set<UUID>) {
        if !lectureSeule, let id = ids.first,
           let o = oeuvres.first(where: { $0.id == id }) {
            editionNouvelle = false
            editionEntree = o
        }
    }

    private func vignette(_ o: Oeuvre) -> some View {
        // La vignette suit la hauteur de rangée (avec une petite marge) pour
        // profiter de la place et améliorer la lisibilité des images.
        // On passe par le cache de vignettes pour un défilement fluide
        // (sinon la grosse image est rechargée à chaque affichage → saccades).
        let cote = max(28, hauteurContenu - 10)
        return VignetteCachee(nom: o.photoNom, cote: cote, coinsArrondis: 4)
        // Glisser-déposer d'une image sur la cellule Photo (sauf en lecture seule).
        .onDrop(of: lectureSeule ? [] : [UTType.fileURL], isTargeted: nil) { fournisseurs in
            deposerPhoto(fournisseurs, sur: o)
        }
    }

    /// Reçoit un fichier image déposé sur la cellule Photo d'une entrée
    /// existante et l'associe à cette entrée (remplace l'éventuelle photo).
    private func deposerPhoto(_ fournisseurs: [NSItemProvider], sur o: Oeuvre) -> Bool {
        guard !lectureSeule, let fournisseur = fournisseurs.first else { return false }

        fournisseur.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let u = item as? URL {
                url = u
            }
            guard let fichier = url else { return }

            let ext = fichier.pathExtension.lowercased()
            guard ["jpg", "jpeg", "png", "heic"].contains(ext) else { return }

            DispatchQueue.main.async {
                // Retire l'ancienne photo si présente, puis importe la nouvelle.
                if !o.photoNom.isEmpty { PhotoStore.supprimerPhoto(nom: o.photoNom) }
                if let nom = PhotoStore.importerImageCompressee(depuis: fichier) {
                    o.photoNom = nom
                    try? context.save()
                }
            }
        }
        return true
    }

    // MARK: Barre de totaux

    // MARK: Actions

    /// Duplique la ligne sélectionnée : reprend tous les champs SAUF la photo
    /// (la cellule photo de la copie reste vide).
    private func dupliquerSelection() {
        guard !lectureSeule,
              let id = selection.first,
              let o = oeuvres.first(where: { $0.id == id }) else { return }

        let copie = Oeuvre(feuille: o.feuille)
        copie.type         = o.type
        copie.dimensions   = o.dimensions
        copie.format       = o.format
        copie.remarques    = o.remarques
        copie.prix         = o.prix
        copie.vendeur      = o.vendeur
        copie.acheteur     = o.acheteur
        copie.date         = o.date
        copie.destinataire = o.destinataire
        copie.photoNom     = ""   // photo volontairement vide

        // `setActionName` exige un groupe d'annulation OUVERT — sans
        // `beginUndoGrouping()` avant, NSUndoManager lève une exception
        // ("no undo grouping in progress") qui plantait la commande sans
        // aucun message dans l'interface. Même patron que `supprimerSelection`.
        let undo = context.undoManager
        undo?.beginUndoGrouping()
        undo?.setActionName("Dupliquer l'entrée")
        context.insert(copie)
        context.processPendingChanges()
        undo?.endUndoGrouping()
        try? context.save()
        selection = [copie.id]
    }

    private func ouvrirModification() {
        guard let id = selection.first, let o = oeuvres.first(where: { $0.id == id }) else { return }
        editionNouvelle = false
        editionEntree = o
    }

    private func supprimerSelection() {
        let aSupprimer = oeuvres.filter { selection.contains($0.id) }
        guard !aSupprimer.isEmpty else { return }

        let undo = context.undoManager
        undo?.beginUndoGrouping()
        undo?.setActionName(
            aSupprimer.count > 1 ? "Supprimer \(aSupprimer.count) entrées" : "Supprimer l'entrée")
        for o in aSupprimer { context.delete(o) }
        // Force SwiftData à enregistrer la suppression comme une étape
        // d'annulation distincte (sinon Cmd Z ne la retrouve pas).
        context.processPendingChanges()
        undo?.endUndoGrouping()
        selection.removeAll()
    }

    private func panneauEnregistrer(nom: String) -> URL? {
        let p = NSSavePanel()
        p.nameFieldStringValue = nom
        p.canCreateDirectories = true
        // Autorise n'importe quelle extension (y compris .pvbase, .html…),
        // sinon macOS peut bloquer l'ouverture du panneau pour un type inconnu.
        p.allowedContentTypes = []
        return p.runModal() == .OK ? p.url : nil
    }

    /// Ouvre le dossier unique des données (base + photos) dans le Finder.
    private func ouvrirDossierDonnees() {
        NSWorkspace.shared.activateFileViewerSelecting([PhotoStore.dossierRacine])
    }

    /// Importe soit un fichier CSV seul (sans images), soit un dossier de
    /// migration (import.csv + sous-dossier Photos, avec les images).
    /// Import d'œuvres depuis des fichiers image (mots-clés IPTC + photo
    /// compressée). Sélection multiple : une œuvre créée par photo.
    private func importerPhotos() {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        // Un DOSSIER est accepté : l'import y cherche toutes les images, y
        // compris dans les sous-dossiers (voir `imagesContenues(dans:)`).
        p.canChooseDirectories = true
        p.allowsMultipleSelection = true
        // Pas de `allowedContentTypes` : il grise les dossiers, qu'on veut
        // pouvoir choisir. Le tri par type se fait à l'import.
        p.prompt = "Importer"
        // PAS de `message` : il s'affiche dans un bandeau en tête du panneau et
        // y impose une largeur minimale, qui empêchait d'ajuster la largeur de
        // la barre latérale — le glissement restait sans effet alors que le
        // curseur changeait bien de forme. Ne pas le réintroduire ; le titre du
        // menu (« Photos… ») dit déjà ce qu'on attend.
        guard p.runModal() == .OK, !p.urls.isEmpty else { return }

        // Les vues agrégées (Inventaire, Ventes) n'ont pas de feuille propre :
        // on retombe sur « Tableaux vendus », comme l'import CSV.
        let cible = feuille ?? .tableauxVendus
        // En tâche : l'import rend la main entre deux fichiers pour que la
        // progression s'affiche (voir `ProgressionImport`).
        Task {
            let r = await ImportPhotos.importer(fichiers: p.urls,
                                                feuilleCible: cible,
                                                context: context)
            if let err = r.erreur {
                messageImport = "Échec : \(err)"
            } else if r.ignorees > 0 {
                messageImport = "\(r.importees) photo(s) importée(s), \(r.ignorees) ignorée(s) (illisibles)."
            } else {
                messageImport = "\(r.importees) photo(s) importée(s)."
            }
        }
    }

    private func importerDonnees() {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = true
        p.allowedContentTypes = [.commaSeparatedText, .plainText, .folder]
        p.prompt = "Importer"
        // `message` conservé ICI, contrairement au panneau des photos : il dit
        // la structure attendue du dossier, que rien d'autre n'indique. Sa
        // longueur reste sous le seuil où le bandeau bloque le redimensionnement
        // de la barre latérale (voir la remarque dans `importerPhotos`) — ne pas
        // l'allonger.
        p.message = "Choisissez un fichier CSV, ou un dossier contenant import.csv et un sous-dossier Photos"
        guard p.runModal() == .OK, let choix = p.url else { return }

        // Détermine si l'utilisateur a choisi un dossier ou un fichier.
        let estDossier = (try? choix.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

        let feuilleCible = feuille ?? .tableauxVendus
        let r: Import.Resultat
        if estDossier {
            // Dossier de migration : import.csv + images du sous-dossier Photos.
            r = Import.importer(depuis: choix, context: context)
        } else {
            // Fichier CSV seul : données texte uniquement.
            r = Import.importerCSV(fichier: choix, context: context,
                                   feuilleParDefaut: feuilleCible)
        }

        if let err = r.erreur {
            messageImport = "Échec : \(err)"
        } else {
            messageImport = "\(r.importees) entrée(s) importée(s)."
        }
    }

    private func exporterCSV() {
        guard let url = panneauEnregistrer(nom: "\(titre).csv") else { return }
        do { try Exports.exporterCSV(oeuvres: oeuvres, colonnes: colonnesModele, vers: url)
             messageExport = "Fichier CSV enregistré." }
        catch { messageExport = "Erreur : \(error.localizedDescription)" }
    }

    private func exporterXLS() {
        guard let url = panneauEnregistrer(nom: "\(titre).xls") else { return }
        do { try Exports.exporterXLS(oeuvres: oeuvres, colonnes: colonnesModele,
                                     nomFeuille: titre, vers: url)
             messageExport = "Fichier Excel enregistré." }
        catch { messageExport = "Erreur : \(error.localizedDescription)" }
    }

    /// Exporte TOUTE la base (données + images) dans un fichier .pvbase unique,
    /// destiné à être transféré sur l'iPhone (via iCloud Drive / Fichiers).
    private func exporterBase() {
        guard let url = panneauEnregistrer(nom: EchangeBase.nomFichierDefaut) else {
            // Si le panneau n'a pas renvoyé d'URL (annulé ou bloqué), on le signale.
            return
        }
        let listeToutes = toutes
        if listeToutes.isEmpty {
            messageExport = "La base est vide : rien à exporter."
            return
        }
        // Indicateur de progression pendant la préparation (peut être long car
        // toutes les images sont encodées dans le fichier).
        texteProgression = "Préparation du fichier (images incluses)…"
        exportEnCours = true
        Task { @MainActor in
            do {
                let donnees = try EchangeBase.exporter(oeuvres: listeToutes)
                try donnees.write(to: url)
                exportEnCours = false
                messageExport = "Base exportée (\(listeToutes.count) œuvres). "
                    + "Déposez ce fichier sur iCloud Drive pour le récupérer sur l'iPhone."
            } catch {
                exportEnCours = false
                messageExport = "Erreur : \(error.localizedDescription)"
            }
        }
    }

    private func exporterXLSXImages() {
        guard let url = panneauEnregistrer(nom: "\(titre).xlsx") else { return }
        // L'export XLKit est asynchrone (incrustation d'images) : on le lance
        // dans une tâche, puis on affiche le résultat.
        let listeOeuvres = oeuvres
        let listeColonnes = colonnesModele
        let nom = titre
        Task { @MainActor in
            do {
                try await ExportXLSXImages.exporter(
                    oeuvres: listeOeuvres,
                    colonnes: listeColonnes,
                    nomFeuille: nom,
                    vers: url)
                messageExport = "Fichier Excel avec images enregistré."
            } catch {
                messageExport = "Erreur : \(error.localizedDescription)"
            }
        }
    }

    private func exporterDossier() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        p.canCreateDirectories = true; p.prompt = "Exporter ici"
        guard p.runModal() == .OK, let dossier = p.url else { return }
        do { try Exports.exporterDossier(oeuvres: oeuvres, colonnes: colonnesModele,
                                         nomFeuille: titre, vers: dossier)
             messageExport = "Dossier « \(titre) » créé avec les images." }
        catch { messageExport = "Erreur : \(error.localizedDescription)" }
    }

    private func exporterPDF() {
        guard let url = panneauEnregistrer(nom: "\(titre).pdf") else { return }
        do { try Exports.exporterPDF(oeuvres: oeuvres, colonnes: colonnesModele,
                                     titre: titre, vers: url)
             messageExport = "PDF généré." }
        catch { messageExport = "Erreur : \(error.localizedDescription)" }
    }
}

/// Fait défiler le tableau natif jusqu'à la ligne sélectionnée, **verticalement
/// seulement**, via `scrollRowToVisible` d'AppKit.
///
/// Pourquoi pas un `ScrollViewReader` : `proxy.scrollTo(id, anchor: .center)`
/// recentre sur les DEUX axes. Le défilement horizontal qui en résultait
/// décalait tout le tableau vers la gauche (colonne Photo passant sous la
/// sidebar) dès que la fenêtre était trop étroite pour afficher toutes les
/// colonnes — invisible en fenêtre large, puisqu'il n'y a alors rien à faire
/// défiler horizontalement.
private struct DefilementTableau: NSViewRepresentable {
    /// Indice de la ligne à rendre visible (nil = ne rien faire).
    let ligne: Int?

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let ligne, ligne >= 0 else { return }
        // Différé : au moment de la mise à jour SwiftUI, le NSTableView n'a pas
        // forcément encore pris en compte le nouveau nombre de lignes.
        DispatchQueue.main.async {
            guard let table = Self.tableauProche(de: nsView),
                  ligne < table.numberOfRows else { return }
            table.scrollRowToVisible(ligne)
        }
    }

    /// Cherche le tableau du panneau de contenu **de proche en proche**, en
    /// remontant depuis la vue du représentable — laquelle est posée en
    /// `.background` du `Table`, donc juste à côté de lui.
    ///
    /// **Ne PAS repartir de la racine de la fenêtre en filtrant par classe.**
    /// La version précédente cherchait le premier `NSTableView` en excluant
    /// les `NSOutlineView`, au motif que la sidebar en est une. Mais le `Table`
    /// de SwiftUI peut lui aussi être adossé à un `NSOutlineView` selon la
    /// version : il devenait alors introuvable, et **plus aucune liste de
    /// l'app ne défilait**. Le voisinage est un critère stable, la classe non.
    static func tableauProche(de vue: NSView) -> NSTableView? {
        var courant: NSView? = vue.superview
        while let ancetre = courant {
            if let t = premierTableau(dans: ancetre) { return t }
            courant = ancetre.superview
        }
        return nil
    }

    /// Premier tableau trouvé en profondeur, `NSOutlineView` compris.
    private static func premierTableau(dans vue: NSView) -> NSTableView? {
        if let t = vue as? NSTableView { return t }
        for sous in vue.subviews {
            if let t = premierTableau(dans: sous) { return t }
        }
        return nil
    }
}

/// Réaffirme le style de sélection standard des tableaux de contenu.
/// La sidebar conserve son traitement marron indépendant.
private struct ForceSelectionBleueTableau: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        VueSelectionBleueTableau(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? VueSelectionBleueTableau)?.appliquerStyle()
    }

    private final class VueSelectionBleueTableau: NSView {
        private var moniteur: Any?

        func appliquerStyle() {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let table = DefilementTableau.tableauProche(de: self) else { return }
                if table.selectionHighlightStyle != .regular {
                    table.selectionHighlightStyle = .regular
                }
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let moniteur { NSEvent.removeMonitor(moniteur) }
            moniteur = nil
            guard window != nil else { return }

            appliquerStyle()
            moniteur = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self,
                      self.window?.isKeyWindow == true,
                      let table = DefilementTableau.tableauProche(de: self),
                      event.window === table.window else { return event }

                let position = table.convert(event.locationInWindow, from: nil)
                guard table.bounds.contains(position) else { return event }

                // Le clic doit rendre le tableau de contenu actif. Sinon
                // AppKit conserve l'apparence grise d'une sélection inactive,
                // même si la ligne vient bien d'être sélectionnée.
                table.window?.makeFirstResponder(table)
                return event
            }
        }

        deinit {
            if let moniteur { NSEvent.removeMonitor(moniteur) }
        }
    }
}

/// Regroupe les trois alertes de la feuille (export, suppression, import) dans
/// un seul modificateur, pour raccourcir la chaîne de modificateurs du body
/// (le compilateur peinait à vérifier le type d'une expression trop grosse).
private struct AlertesFeuille: ViewModifier {
    @Binding var confirmerSuppression: Bool
    let titreConfirmation: String
    @Binding var messageImport: String?
    let onSupprimer: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(titreConfirmation, isPresented: $confirmerSuppression) {
                Button("Supprimer", role: .destructive) { onSupprimer() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Cette action peut être annulée avec Cmd + Z tant que l'application reste ouverte.")
            }
            .alert("Import", isPresented: Binding(
                get: { messageImport != nil },
                set: { if !$0 { messageImport = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(messageImport ?? "") }
    }
}

/// Regroupe les raccourcis clavier (barre d'espace pour Quick Look, Cmd A pour
/// tout sélectionner, Delete pour supprimer) en un seul modificateur — pour
/// raccourcir la chaîne de modificateurs du body.
private struct RaccourcisClavier: ViewModifier {
    let editionActive: Bool
    /// Vrai tant que la visionneuse intégrée est à l'écran : elle a son propre
    /// capteur pour Échap.
    let visionneuseOuverte: Bool
    let onApercu: () -> Void
    let onToutSelectionner: () -> Void
    let onDeselectionner: () -> Void
    let onSupprimer: () -> Void

    func body(content: Content) -> some View {
        content
            // Barre d'espace : Quick Look (désactivé pendant l'édition pour
            // laisser taper des espaces dans les champs).
            .background(
                Group {
                    if !editionActive {
                        CaptureEspace { onApercu() }
                    }
                }
            )
            // ⌘A : moniteur NSEvent, et non un bouton caché à raccourci —
            // celui-ci ne répondait que dans certaines rubriques.
            .background(
                Group {
                    if !editionActive {
                        CaptureCommandeA { onToutSelectionner() }
                    }
                }
            )
            // Échap : lève la sélection, contrepartie naturelle de ⌘A.
            // Le capteur est retiré quand la visionneuse est ouverte, où Échap
            // sert à la fermer — deux moniteurs sur la même touche se
            // disputeraient l'événement.
            .background(
                Group {
                    if !editionActive && !visionneuseOuverte {
                        CaptureEchap { onDeselectionner() }
                    }
                }
            )
            // Delete (supprimer), bouton masqué.
            .background(
                Group {
                    if !editionActive {
                        Button("Supprimer") { onSupprimer() }
                            .keyboardShortcut(.delete, modifiers: [])
                            .hidden()
                    }
                }
            )
    }
}

#endif
