#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Une vue de feuille = un onglet, construite autour du composant natif `Table`
/// de macOS : colonnes redimensionnables, tri par en-tête, sélection multiple
/// et grille gérés nativement. L'édition d'une entrée se fait via une fiche
/// (double-clic sur une ligne, ou bouton Modifier).
struct VueFeuille: View {
    let feuille: Feuille?          // nil = vue compilée « Œuvres »
    let lectureSeule: Bool
    let titre: String
    let modesVente: [String]       // filtre supplémentaire sur modeVente (vide = aucun)
    /// Nombre d'entrées sélectionnées, remonté vers la sidebar.
    @Binding var nbSelection: Int

    init(feuille: Feuille?, lectureSeule: Bool, titre: String,
         modesVente: [String] = [], nbSelection: Binding<Int>) {
        self.feuille = feuille
        self.lectureSeule = lectureSeule
        self.titre = titre
        self.modesVente = modesVente
        self._nbSelection = nbSelection
    }

    @Environment(\.modelContext) private var context
    @Query private var toutes: [Oeuvre]

    @State private var tri: [KeyPathComparator<Oeuvre>] = [
        KeyPathComparator(\Oeuvre.type)
    ]
    @State private var selection: Set<UUID> = []
    @State private var editionEntree: Oeuvre?
    @State private var editionNouvelle = false
    @State private var messageExport: String?
    // Vrai pendant la préparation d'un export long (base .pvbase avec images) :
    // affiche un indicateur de progression sans bouton.
    @State private var exportEnCours = false
    @State private var texteProgression = ""
    // Pilote l'affichage de la fenêtre de confirmation de suppression.
    @State private var confirmerSuppression = false
    // URL de l'image à prévisualiser via Quick Look (barre d'espace).
    @State private var apercuURL: URL?
    // Affichage du panneau Inspecteur (mode galerie uniquement).
    // En @AppStorage pour être piloté aussi depuis le menu système « Présentation ».
    @AppStorage("inspecteurVisible") private var inspecteurVisible = false
    // Mode d'affichage : « liste » (tableau) ou « icone » (galerie).
    // Conservé entre les sessions ; « liste » par défaut au tout premier lancement.
    @AppStorage("modeAffichage") private var modeAffichage: String = "liste"
    // Critère de tri de la galerie (indépendant du tri du tableau).
    @AppStorage("triGalerie") private var triGalerie: String = "prix"
    // Sens du tri : true = croissant (du plus petit au plus grand).
    @AppStorage("triCroissant") private var triCroissant: Bool = false
    // Masquage des prix : observé ici pour que l'inspecteur se rafraîchisse.
    @AppStorage("prixMasques") private var prixMasques = false
    // Signaux venus du menu « Édition » pour ouvrir / fermer l'éditeur.
    @AppStorage("signalOuvrirEditeur") private var signalOuvrirEditeur = 0
    @AppStorage("signalFermerEditeur") private var signalFermerEditeur = 0
    // Action déclenchée depuis le menu « Fichier » (import/export). On stocke le
    // nom de l'action + un compteur pour redéclencher même deux fois de suite.
    @AppStorage("actionFichier") private var actionFichier = ""
    @AppStorage("actionFichierSignal") private var actionFichierSignal = 0
    // États remontés vers le menu « Édition » pour griser « Ouvrir l'éditeur ».
    @AppStorage("uneSelectionExiste") private var uneSelectionExiste = false
    @AppStorage("editeurOuvert") private var editeurOuvert = false
    // Message affiché après un import (déplacé ici pour grouper le set Import).
    @State private var messageImport: String?

    /// Œuvres de cette feuille (ou compilation des 4), triées par le composant.
    private var oeuvres: [Oeuvre] {
        var base: [Oeuvre]
        if let f = feuille {
            base = toutes.filter { $0.feuille == f }
        } else if !modesVente.isEmpty {
            // Filtre modeVente actif : on se restreint aux feuilles vendues (tableaux, dessins, tapis)
            base = toutes.filter { $0.feuille != .oeuvresDonnees }
        } else {
            base = toutes
        }
        if !modesVente.isEmpty {
            base = base.filter { modesVente.contains($0.modeVente) }
        }
        return base.sorted(using: tri)
    }

    /// Liste dans l'ordre actuellement affiché (galerie ou liste) : sert de base
    /// à la navigation Précédent / Suivant de l'éditeur.
    private var listeAffichee: [Oeuvre] {
        modeAffichage == "icone" ? oeuvresGalerie : oeuvres
    }

    /// Œuvres triées pour la galerie, selon le critère et le sens choisis.
    private var oeuvresGalerie: [Oeuvre] {
        var base: [Oeuvre]
        if let f = feuille {
            base = toutes.filter { $0.feuille == f }
        } else if !modesVente.isEmpty {
            // Filtre modeVente actif : on se restreint aux feuilles vendues (tableaux, dessins, tapis)
            base = toutes.filter { $0.feuille != .oeuvresDonnees }
        } else {
            base = toutes
        }
        if !modesVente.isEmpty {
            base = base.filter { modesVente.contains($0.modeVente) }
        }
        // Critère effectif : on retombe sur un tri pertinent si le critère
        // mémorisé ne s'applique pas à cette feuille.
        var critere = triGalerie
        if estFeuilleDon, critere == "prix" { critere = "dimensions" }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Grande image en tête.
                    if let img = PhotoStore.chargerImage(nom: o.photoNom) {
                        Image(nsImage: img).resizable().scaledToFit()
                            .frame(maxWidth: .infinity)
                            .cornerRadius(10)
                    }

                    // Cellule 1 : Prix (sauf dons).
                    if !estFeuilleDon {
                        celluleInspecteur {
                            ligneInspecteur("Prix", formaterEuros(o.prix),
                                            couleur: Color.orangeInternational, estPrix: true)
                        }
                    }

                    // Cellule 2 : Type.
                    celluleInspecteur {
                        ligneInspecteur("Type", o.type)
                    }

                    // Cellule 3 : Dimensions et Format.
                    celluleInspecteur {
                        ligneInspecteur("Dimensions", o.dimensions)
                        ligneInspecteur("Format", o.format)
                    }

                    // Cellule 4 : Vendeur, Acheteur (ou Destinataire), Mode de vente.
                    celluleInspecteur {
                        if estFeuilleDon {
                            ligneInspecteur("Destinataire", o.destinataire)
                        } else {
                            ligneInspecteur("Vendeur", o.vendeur)
                            ligneInspecteur("Acheteur", o.acheteur)
                            ligneInspecteur("Mode de vente", o.modeVente)
                        }
                    }

                    // Cellule 5 : Date (sauf dons, qui n'en ont pas).
                    if !estFeuilleDon {
                        celluleInspecteur {
                            ligneInspecteur("Date", o.date)
                        }
                    }

                    // Cellule 6 : Remarques, seulement si renseignées.
                    if !o.remarques.isEmpty {
                        celluleInspecteur {
                            ligneInspecteur("Remarques", o.remarques)
                        }
                    }
                }
                .padding()
            }
        } else if selection.count > 1 && !estFeuilleDon {
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
                                        couleur: Color.orangeInternational, estPrix: true)
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
                        .strokeBorder(Color.orangeInternational.opacity(0.4), lineWidth: 1)
                )
        )
    }

    /// Une ligne libellé + valeur à l'intérieur d'une cellule (masquée si vide).
    @ViewBuilder
    private func ligneInspecteur(_ titre: String, _ valeur: String,
                                 couleur: Color = .primary,
                                 estPrix: Bool = false) -> some View {
        if !valeur.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(titre).font(.body).fontWeight(.bold).foregroundStyle(.secondary)
                Text(valeur).font(.body).foregroundStyle(couleur)
                    // Floutage piloté directement par l'état de la vue (fiable
                    // dans l'inspecteur, contrairement au modificateur AppStorage).
                    .blur(radius: (estPrix && prixMasques) ? 6 : 0)
                    .animation(.easeInOut(duration: 0.2), value: prixMasques)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Alignement du contenu des cellules « vente » : centré (toutes les
    /// catégories, y compris « Œuvres », sont désormais éditables).
    private var alignementCellules: Alignment {
        lectureSeule ? .leading : .center
    }

    var body: some View {
        contenu
        .navigationTitle("")
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
        // Tient à jour les états lus par le menu « Édition ».
        .onChange(of: editionEntree) { _, nouveau in
            editeurOuvert = (nouveau != nil)
        }
        .onChange(of: selection) { _, nouvelle in
            uneSelectionExiste = !nouvelle.isEmpty
            nbSelection = nouvelle.count
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
        }
        .modifier(AlertesFeuille(
            confirmerSuppression: $confirmerSuppression,
            titreConfirmation: titreConfirmation,
            messageImport: $messageImport,
            onSupprimer: { supprimerSelection() }))
        // Quick Look natif : affiche l'image de la ligne sélectionnée.
        .apercuQuickLook($apercuURL)
        // Panneau centré unique : progression (indicateur) puis message final
        // (avec OK), toujours au même endroit.
        .overlay {
            if exportEnCours || messageExport != nil {
                panneauProgression
            }
        }
        .modifier(RaccourcisClavier(
            editionActive: editionEntree != nil,
            onApercu: { declencherApercu() },
            onToutSelectionner: { selectionnerTout() },
            onSupprimer: {
                if !selection.isEmpty && !lectureSeule {
                    confirmerSuppression = true
                }
            }))
        .onAppear {
            nbSelection = selection.count
            uneSelectionExiste = !selection.isEmpty
            editeurOuvert = (editionEntree != nil)
        }
    }

    /// Sélectionne toutes les entrées de la catégorie affichée.
    private func selectionnerTout() {
        selection = Set(oeuvres.map { $0.id })
    }

    /// Exécute l'action import/export demandée par le menu « Fichier ».
    private func executerActionFichier(_ action: String) {
        switch action {
        case "importer":     importerDonnees()
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
    @ToolbarContentBuilder
    private var contenuBarreOutils: some ToolbarContent {
        // Spacer flexible en tête : pousse tous les boutons vers la droite
        // du panneau de contenu (jamais au-dessus de la colonne inspecteur).
        ToolbarSpacer(.flexible)

        // === Set 1 : création / suppression / modification ===
        if !lectureSeule {
            if let f = feuille {
                ToolbarItem {
                    Button {
                        let o = Oeuvre(feuille: f)
                        context.insert(o)
                        editionNouvelle = true
                        editionEntree = o
                    } label: { Label("Ajouter", systemImage: "plus") }
                }
            }
            ToolbarItem {
                Button(role: .destructive) {
                    confirmerSuppression = true
                } label: { Label(labelSupprimer, systemImage: "trash") }
                .disabled(selection.isEmpty)
            }
            if selection.count == 1 {
                ToolbarItem {
                    Button {
                        if let id = selection.first, let o = oeuvres.first(where: { $0.id == id }) {
                            editionNouvelle = false
                            editionEntree = o
                        }
                    } label: { Label("Modifier", systemImage: "pencil") }
                }
            }
        }
        ToolbarSpacer(.fixed)
        ToolbarItem {
            Button {
                prixMasques.toggle()
            } label: {
                Image(systemName: prixMasques ? "eye.slash" : "eye")
            }
            .help(prixMasques ? "Afficher les prix" : "Masquer les prix")
        }
        ToolbarSpacer(.fixed)
        ToolbarItem {
            Button {
                modeAffichage = "liste"
            } label: { Label("Liste", systemImage: "list.bullet") }
            .disabled(modeAffichage == "liste")
        }
        ToolbarItem {
            Button {
                modeAffichage = "icone"
            } label: { Label("Galerie", systemImage: "square.grid.2x2") }
            .disabled(modeAffichage == "icone")
        }

        // === Tri + sens + inspecteur (galerie seulement) ===
        if modeAffichage == "icone" {
            ToolbarSpacer(.fixed)
            ToolbarItemGroup {
                menuTri
                Button {
                    triCroissant.toggle()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .scaleEffect(x: 1, y: triCroissant ? -1 : 1)
                }
                .help(triCroissant ? "Tri croissant" : "Tri décroissant")
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Button {
                    inspecteurVisible.toggle()
                } label: {
                    Label("Inspecteur", systemImage: "sidebar.right")
                }
                .help(inspecteurVisible ? "Masquer l'inspecteur" : "Afficher l'inspecteur")
            }
        }
    }

    /// Icône du bouton de menu de tri selon le critère actif (comme sur iOS).
    private var iconeMenuTri: String {
        if estFeuilleDon {
            return triGalerie == "acheteur" ? "person" : "ruler"
        }
        switch triGalerie {
        case "acheteur":   return "person"
        case "dimensions": return "ruler"
        default:           return "eurosign"
        }
    }

    /// Menu de choix du critère de tri (galerie).
    private var menuTri: some View {
        Menu {
            if !estFeuilleDon {
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
            Label("Trier", systemImage: iconeMenuTri)
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

    /// Ouvre Quick Look sur la photo de la ligne sélectionnée (barre d'espace).
    /// Si l'aperçu est déjà ouvert, un nouvel appui le referme (comme le Finder).
    private func declencherApercu() {
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
        if modeAffichage == "icone" {
            VueGalerie(
                oeuvres: oeuvresGalerie,
                estFeuilleDon: estFeuilleDon,
                selection: $selection,
                onOuvrir: { o in
                    if !lectureSeule { editionNouvelle = false; editionEntree = o }
                }
            )
        } else {
            // ↑↓ gérés nativement par NSTableView (ne pas intercepter).
            // ←→ ajoutés ici pour naviguer en mode liste (NSTableView ne les utilise pas).
            tableau
                .onKeyPress(.leftArrow)  { naviguerListe(delta: -1) }
                .onKeyPress(.rightArrow) { naviguerListe(delta: +1) }
        }
    }

    // Déplace la sélection d'une entrée dans la liste triée courante.
    private func naviguerListe(delta: Int) -> KeyPress.Result {
        guard selection.count == 1,
              let id = selection.first,
              let idx = oeuvres.firstIndex(where: { $0.id == id }) else { return .ignored }
        let nouveauIdx = idx + delta
        guard nouveauIdx >= 0, nouveauIdx < oeuvres.count else { return .handled }
        selection = [oeuvres[nouveauIdx].id]
        return .handled
    }

    @ViewBuilder
    private var tableau: some View {
        if estFeuilleDon {
            tableDon
        } else {
            tableVente
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
                    .foregroundStyle(Color.orangeInternational)
                    .blur(radius: prixMasques ? 5 : 0)
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
            }
            TableColumn("Type", value: \Oeuvre.type) { o in
                Text(o.type)
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
            }
            TableColumn("Dimensions", value: \Oeuvre.dimensions) { o in
                Text(o.dimensions)
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
            }
            TableColumn("Format", value: \Oeuvre.format) { o in
                Text(o.format)
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
            }
            TableColumn("Vendeur", value: \Oeuvre.vendeur) { o in
                Text(o.vendeur)
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
            }
            TableColumn("Acheteur", value: \Oeuvre.acheteur) { o in
                Text(o.acheteur)
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
            }
            TableColumn("Mode de vente", value: \Oeuvre.modeVente) { o in
                Text(o.modeVente)
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
            }
            TableColumn("Date", value: \Oeuvre.date) { o in
                Text(o.date)
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: alignementCellules)
            }
            TableColumn("Remarques", value: \Oeuvre.remarques) { o in
                Text(o.remarques)
                    .frame(minHeight: hauteurContenu, alignment: .leading)
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
                    .frame(minHeight: hauteurContenu, alignment: .leading)
            }
            TableColumn("Type", value: \Oeuvre.type) { o in
                Text(o.type)
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: .center)
            }
            TableColumn("Dimensions", value: \Oeuvre.dimensions) { o in
                Text(o.dimensions)
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: .center)
            }
            TableColumn("Format", value: \Oeuvre.format) { o in
                Text(o.format)
                    .frame(maxWidth: .infinity, minHeight: hauteurContenu, alignment: .center)
            }
            TableColumn("Remarques", value: \Oeuvre.remarques) { o in
                Text(o.remarques)
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
            Button("Supprimer", role: .destructive) { confirmerSuppression = true }
        }
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
                if let nom = PhotoStore.importerImage(depuis: fichier) {
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

        context.undoManager?.setActionName("Dupliquer l'entrée")
        context.insert(copie)
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
    private func importerDonnees() {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = true
        p.allowedContentTypes = [.commaSeparatedText, .plainText, .folder]
        p.prompt = "Importer"
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
    let onApercu: () -> Void
    let onToutSelectionner: () -> Void
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
            // Cmd A (tout sélectionner) et Delete (supprimer), boutons masqués.
            .background(
                Group {
                    if !editionActive {
                        Button("Tout sélectionner") { onToutSelectionner() }
                            .keyboardShortcut("a", modifiers: .command)
                            .hidden()
                        Button("Supprimer") { onSupprimer() }
                            .keyboardShortcut(.delete, modifiers: [])
                            .hidden()
                    }
                }
            )
    }
}

#endif
