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
    /// Nombre d'entrées sélectionnées, remonté vers la sidebar.
    @Binding var nbSelection: Int

    @Environment(\.modelContext) private var context
    @Query private var toutes: [Oeuvre]

    @State private var tri: [KeyPathComparator<Oeuvre>] = [
        KeyPathComparator(\Oeuvre.type)
    ]
    @State private var selection: Set<UUID> = []
    @State private var editionEntree: Oeuvre?
    @State private var editionNouvelle = false
    @State private var messageExport: String?
    // Pilote l'affichage de la fenêtre de confirmation de suppression.
    @State private var confirmerSuppression = false
    // URL de l'image à prévisualiser via Quick Look (barre d'espace).
    @State private var apercuURL: URL?
    // Mode d'affichage : « liste » (tableau) ou « icone » (galerie).
    // Conservé entre les sessions ; « liste » par défaut au tout premier lancement.
    @AppStorage("modeAffichage") private var modeAffichage: String = "liste"
    // Message affiché après un import (déplacé ici pour grouper le set Import).
    @State private var messageImport: String?

    /// Œuvres de cette feuille (ou compilation des 4), triées par le composant.
    private var oeuvres: [Oeuvre] {
        let base: [Oeuvre]
        if let f = feuille {
            base = toutes.filter { $0.feuille == f }
        } else {
            base = toutes
        }
        return base.sorted(using: tri)
    }

    private var colonnesModele: [Colonne] {
        if let f = feuille { return SchemaFeuille.colonnes(pour: f) }
        return SchemaFeuille.colonnesOeuvres
    }

    private var estFeuilleDon: Bool { feuille == .oeuvresDonnees }

    /// Alignement du contenu des cellules « vente » :
    /// à gauche dans l'onglet Œuvres (vue compilée, en lecture seule),
    /// centré dans les autres onglets.
    private var alignementCellules: Alignment {
        lectureSeule ? .leading : .center
    }

    var body: some View {
        contenu
        .navigationTitle("")
        .toolbar {
            // === Set 1 : création/suppression/modification + affichage ===
            if !lectureSeule, let f = feuille {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let o = Oeuvre(feuille: f)
                        context.insert(o)
                        editionNouvelle = true
                        editionEntree = o
                    } label: { Label("Ajouter", systemImage: "plus") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        confirmerSuppression = true
                    } label: { Label(labelSupprimer, systemImage: "trash") }
                    .disabled(selection.isEmpty)
                }
                if selection.count == 1 {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            if let id = selection.first, let o = oeuvres.first(where: { $0.id == id }) {
                                editionNouvelle = false
                                editionEntree = o
                            }
                        } label: { Label("Modifier", systemImage: "pencil") }
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    modeAffichage = "liste"
                } label: { Label("Liste", systemImage: "list.bullet") }
                .disabled(modeAffichage == "liste")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    modeAffichage = "icone"
                } label: { Label("Galerie", systemImage: "square.grid.2x2") }
                .disabled(modeAffichage == "icone")
            }

            // Espacement entre le set 1 et le set 2.
            ToolbarItem(placement: .primaryAction) { Spacer() }

            // === Set 2 : migration (Importer) ===
            ToolbarItem(placement: .primaryAction) {
                Button {
                    importerDonnees()
                } label: { Label("Importer…", systemImage: "square.and.arrow.down") }
            }

            // Espacement entre le set 2 et le set 3.
            ToolbarItem(placement: .primaryAction) { Spacer() }

            // === Set 3 : export ===
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Exporter en CSV…") { exporterCSV() }
                    Button("Exporter en Excel (.xls)…") { exporterXLS() }
                    Button("Exporter dossier avec images…") { exporterDossier() }
                    Button("Exporter Excel avec images (.xlsx)…") { exporterXLSXImages() }
                    if lectureSeule {
                        Divider()
                        Button("Générer un PDF…") { exporterPDF() }
                    }
                } label: {
                    Label("Exporter", systemImage: "square.and.arrow.up")
                }
            }

            // Espacement entre le set 3 et le set 4.
            ToolbarItem(placement: .primaryAction) { Spacer() }

            // === Set 4 : dossier des données de l'app ===
            ToolbarItem(placement: .primaryAction) {
                Button {
                    ouvrirDossierDonnees()
                } label: { Label("Ouvrir le dossier des données", systemImage: "folder") }
            }
        }
        .sheet(item: $editionEntree) { o in
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
                onEnregistrerEtNouveau: {
                    guard let f = feuille else { return nil }
                    let nouvelle = Oeuvre(feuille: f)
                    context.insert(nouvelle)
                    return nouvelle
                }
            )
        }
        .alert("Export", isPresented: Binding(
            get: { messageExport != nil },
            set: { if !$0 { messageExport = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(messageExport ?? "") }
        // Fenêtre de confirmation avant suppression (standard macOS).
        .alert(titreConfirmation, isPresented: $confirmerSuppression) {
            Button("Supprimer", role: .destructive) { supprimerSelection() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cette action peut être annulée avec Cmd + Z tant que l'application reste ouverte.")
        }
        .alert("Import", isPresented: Binding(
            get: { messageImport != nil },
            set: { if !$0 { messageImport = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(messageImport ?? "") }
        // Quick Look natif : affiche l'image de la ligne sélectionnée.
        .apercuQuickLook($apercuURL)
        // Capte la barre d'espace pour le Quick Look, sauf quand la fiche
        // d'édition est ouverte (pour laisser taper des espaces dans le texte).
        .background(
            Group {
                if editionEntree == nil {
                    CaptureEspace { declencherApercu() }
                }
            }
        )
        // Remonte le nombre sélectionné vers la sidebar.
        .onChange(of: selection) { _, nouvelle in
            nbSelection = nouvelle.count
        }
        .onAppear { nbSelection = selection.count }
        // Commande « Tout sélectionner » (Cmd A) : sélectionne toutes les
        // entrées de la catégorie affichée. Le bouton est masqué mais actif.
        // Désactivé pendant l'édition pour laisser Cmd A agir dans les champs.
        .background(
            Group {
                if editionEntree == nil {
                    Button("Tout sélectionner") { selectionnerTout() }
                        .keyboardShortcut("a", modifiers: .command)
                        .hidden()

                    // Touche Delete (retour arrière) : lance la suppression
                    // (avec confirmation) si des entrées sont sélectionnées.
                    Button("Supprimer") {
                        if !selection.isEmpty && !lectureSeule {
                            confirmerSuppression = true
                        }
                    }
                    .keyboardShortcut(.delete, modifiers: [])
                    .hidden()
                }
            }
        )
    }

    /// Sélectionne toutes les entrées de la catégorie affichée.
    private func selectionnerTout() {
        selection = Set(oeuvres.map { $0.id })
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
                oeuvres: oeuvres,
                estFeuilleDon: estFeuilleDon,
                selection: $selection,
                onOuvrir: { o in
                    if !lectureSeule { editionNouvelle = false; editionEntree = o }
                }
            )
        } else {
            tableau
        }
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

    @ViewBuilder
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
        return p.runModal() == .OK ? p.url : nil
    }

    /// Ouvre le dossier unique des données (base + photos) dans le Finder.
    private func ouvrirDossierDonnees() {
        NSWorkspace.shared.activateFileViewerSelecting([PhotoStore.dossierRacine])
    }

    /// Importe un dossier de migration (import.csv + Photos).
    private func importerDonnees() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.prompt = "Importer ce dossier"
        p.message = "Choisissez le dossier de migration (contenant import.csv et Photos)"
        guard p.runModal() == .OK, let dossier = p.url else { return }
        let r = Import.importer(depuis: dossier, context: context)
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

#endif
