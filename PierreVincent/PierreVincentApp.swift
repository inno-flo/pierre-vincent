import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// Point d'entrée de l'application « Pierre-Vincent ».
@main
struct PierreVincentApp: App {
    #if os(macOS)
    // États partagés avec la toolbar (pilotés aussi par le menu « Présentation »).
    @AppStorage("modeAffichage") private var modeAffichage: String = "icone"
    @AppStorage("inspecteurVisible") private var inspecteurVisible = false
    @AppStorage("prixMasques") private var prixMasques = false
    // Signaux pour piloter l'éditeur depuis le menu « Édition » (on incrémente
    // pour déclencher l'action côté vue, qui observe le changement).
    @AppStorage("signalOuvrirEditeur") private var signalOuvrirEditeur = 0
    @AppStorage("signalFermerEditeur") private var signalFermerEditeur = 0
    // Mêmes signaux, pour « Tout sélectionner » et « Supprimer » : ces deux
    // commandes du menu Édition étaient grisées faute d'action câblée — les
    // sélections et suppressions de VueFeuille ne passent pas par la chaîne
    // de répondants standard (voir CLAUDE.md, ⌘A). « Supprimer » déclenche la
    // MÊME confirmation que le bouton de corbeille, pas une suppression directe.
    @AppStorage("signalToutSelectionner") private var signalToutSelectionner = 0
    @AppStorage("signalSupprimer") private var signalSupprimer = 0
    // Signal pour basculer le favori de la sélection, depuis le menu Édition.
    @AppStorage("signalBasculerFavori") private var signalBasculerFavori = 0
    // Remonté par la vue : la sélection est-elle DÉJÀ tout entière favorite ?
    // Dit si la commande doit ajouter (au moins une œuvre ne l'est pas) ou
    // retirer (toutes le sont déjà) — même convention qu'un « marquer »/
    // « démarquer » à bascule sur plusieurs éléments.
    @AppStorage("selectionEstToutFavorite") private var selectionEstToutFavorite = false
    // État remonté par la vue : y a-t-il une œuvre sélectionnée, et l'éditeur
    // est-il ouvert ? Sert à griser « Ouvrir l'éditeur » au bon moment.
    @AppStorage("uneSelectionExiste") private var uneSelectionExiste = false
    @AppStorage("editeurOuvert") private var editeurOuvert = false
    // Un champ de texte de l'éditeur a-t-il le focus ? (`EditeurEntree.swift`,
    // via son `@FocusState`). Sert à griser Couper/Copier/Coller hors d'un
    // champ éditable, et à router Annuler/Rétablir vers le bon gestionnaire.
    @AppStorage("champTexteFocalise") private var champTexteFocalise = false
    // Remonté par la vue : sert à griser « Supprimer » quand rien n'est
    // sélectionné — même condition que le bouton de corbeille et la touche
    // Suppr, réutilisée telle quelle (`uneSelectionExiste`).
    // Remonté par la vue : la rubrique affichée est-elle sans prix (Dons ou
    // Réserve) ? Sert à griser « Masquer les prix ».
    @AppStorage("rubriqueSansPrix") private var rubriqueSansPrix = false
    // Y a-t-il un import à annuler ? Posé par les deux moteurs d'import,
    // effacé par l'annulation (voir `DernierImport`).
    @AppStorage("importAnnulable") private var importAnnulable = false
    // Pilotage des actions import/export depuis le menu « Fichier ».
    @AppStorage("actionFichier") private var actionFichier = ""
    @AppStorage("actionFichierSignal") private var actionFichierSignal = 0

    #endif

    init() {
        #if os(macOS)
        // Désactive les onglets de fenêtre : retire du menu « Présentation »
        // les commandes « Afficher la barre d'onglets / tous les onglets ».
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif
        Self.arrangerSidebar()
    }

    /// Arrangement de la barre latérale au lancement, identique sur les deux
    /// plateformes : les DEUX GRANDS BLOCS sont dépliés, et les QUATRE
    /// sous-groupes repliés — les deux « Catégories », « Modes de vente » et
    /// « Thèmes ».
    ///
    /// L'ouverture montre ainsi les seules vues d'ensemble, une poignée de
    /// rubriques au lieu d'une vingtaine. Les sous-groupes se déplient à la
    /// demande.
    ///
    /// Écrit à CHAQUE lancement, et non posé comme simple valeur par défaut de
    /// `@AppStorage` : ces clés existent déjà chez qui a utilisé l'app, et une
    /// valeur par défaut ne s'applique qu'à une clé absente — l'arrangement ne
    /// serait donc jamais appliqué. Conséquence assumée : les replis faits à la
    /// main ne survivent plus à la fermeture de l'app.
    private static func arrangerSidebar() {
        let reglages = UserDefaults.standard
        reglages.set(true,  forKey: "blocVentesOuvert")
        reglages.set(true,  forKey: "blocStockOuvert")
        reglages.set(false, forKey: "sousBlocCategoriesOuvert")
        reglages.set(false, forKey: "sousBlocModesVenteOuvert")
        reglages.set(false, forKey: "sousBlocReserveCategoriesOuvert")
        reglages.set(false, forKey: "sousBlocReserveThemesOuvert")
    }

    /// Conteneur SwiftData : la base de données locale des œuvres.
    /// Le fichier est stocké dans Application Support/Pierre-Vincent.
    var conteneur: ModelContainer = {
        let schema = Schema([Oeuvre.self])
        let dossier = PhotoStore.dossierRacine
        let config = ModelConfiguration(
            schema: schema,
            url: dossier.appendingPathComponent("PierreVincent.store")
        )
        do {
            let c = try ModelContainer(for: schema, configurations: [config])
            // On attache NOTRE gestionnaire d'annulation partagé au contexte,
            // pour pouvoir y câbler Cmd Z / Cmd Maj Z depuis le menu.
            c.mainContext.undoManager = GestionAnnulation.shared.undoManager
            return c
        } catch {
            fatalError("Impossible de créer la base de données : \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(conteneur)
        // Les réglages de fenêtre et les menus ci-dessous n'existent que sur Mac.
        #if os(macOS)
        .windowStyle(.titleBar)
        .commands {
            // Remplace le panneau « À propos » standard pour y ajouter les
            // bibliothèques tierces (Credits) — le seul moyen offert par
            // AppKit : `orderFrontStandardAboutPanel(options:)` avec la clé
            // `.credits`, qui accepte un texte enrichi affiché sous le nom et
            // la version. Le panneau reste celui du système pour le reste
            // (icône, nom, version, copyright).
            CommandGroup(replacing: .appInfo) {
                Button("À propos de PierreVincent") { afficherAPropos() }
            }
            CommandGroup(replacing: .newItem) {}
            // On retire le « Fermer » système par défaut (il se place en tête du
            // menu Fichier) pour le recréer nous-mêmes à la fin.
            CommandGroup(replacing: .saveItem) {}

            // Import / export dans le menu système « Fichier ».
            CommandGroup(replacing: .importExport) {
                // Deux moteurs distincts : les photos passent par un import
                // fondé sur les métadonnées IPTC, le dossier par le moteur CSV.
                Menu("Importer") {
                    Button("Photos…") { declencherFichier("importerPhotos") }
                    Button("Dossier CSV et photos…") { declencherFichier("importer") }
                    Divider()
                    // Grisée tant qu'aucun import n'est annulable, et de
                    // nouveau après l'annulation.
                    Button("Annuler l'importation…") {
                        declencherFichier("annulerImport")
                    }
                    .disabled(!importAnnulable)
                }
                Divider()
                // Entretien du dossier de photos. Séparée des imports : elle ne
                // fait entrer aucune donnée, elle réécrit celles déjà là.
                Button("Recompresser les photos…") {
                    declencherFichier("recompresser")
                }
                Divider()
                // Tous les exports regroupés dans un sous-menu « Exporter ».
                Menu("Exporter") {
                    // Les deux exports les plus utilisés en tête.
                    Button("Base pour iPhone (.pvbase)") { declencherFichier("base") }
                    Button("PDF…") { declencherFichier("pdf") }
                    Divider()
                    Button("CSV…") { declencherFichier("csv") }
                    Button("Excel (.xls)…") { declencherFichier("xls") }
                    Button("Excel avec images (.xlsx)…") { declencherFichier("xlsx") }
                    Button("Dossier avec images…") { declencherFichier("dossier") }
                }
                Divider()
                Button("Ouvrir le dossier des données") {
                    NSWorkspace.shared.activateFileViewerSelecting([PhotoStore.dossierRacine])
                }
                Divider()
                // Fermer la fenêtre, placé en dernier (le « Fermer » système
                // par défaut se met en tête, ce qu'on ne veut pas).
                Button("Fermer") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            // On remplace Annuler/Rétablir pour viser le gestionnaire SwiftData —
            // MAIS SEULEMENT hors d'un champ de texte. Ce remplacement visait
            // SANS CONDITION jusqu'ici, et cassait la correction d'une frappe
            // dans l'éditeur : ⌘Z appelait TOUJOURS le gestionnaire SwiftData,
            // qui n'a rien enregistré de la saisie, au lieu de laisser le
            // champ de texte défaire son propre caractère. Cible `nil` dans ce
            // cas, exactement comme Couper/Copier/Coller : la frappe suit le
            // PREMIER RÉPONDANT et son propre historique.
            CommandGroup(replacing: .undoRedo) {
                Button("Annuler") {
                    if champTexteFocalise {
                        // `#selector` ne peut pas viser `undo:` : ce n'est
                        // pas une méthode déclarée de `NSResponder` côté
                        // Swift, seulement une action standard reconnue à
                        // l'exécution. D'où le sélecteur construit à la main.
                        NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                    } else {
                        let u = GestionAnnulation.shared.undoManager
                        if u.canUndo { u.undo() }
                    }
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Rétablir") {
                    if champTexteFocalise {
                        NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                    } else {
                        let u = GestionAnnulation.shared.undoManager
                        if u.canRedo { u.redo() }
                    }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            // Retire les commandes de barre latérale ET de barre d'onglets du
            // menu « Présentation » standard (inutiles pour cette app).
            CommandGroup(replacing: .sidebar) {}

            // « Tout sélectionner » et « Supprimer », dans le menu « Édition ».
            //
            // **`CommandGroup(replacing: .pasteboard)`, et non `after:`** :
            // ce groupe standard porte Cut/Copy/Paste/Delete/Select All, dont
            // les versions par défaut (Select All, Delete) restent GRISÉES
            // ici — elles visent le premier répondant, que ni la sélection de
            // `VueFeuille` ni la suppression confirmée n'utilisent. Les
            // remplacer entièrement évite d'afficher DEUX commandes
            // « Supprimer », l'une grisée et l'autre active.
            //
            // **Couper/Copier/Coller sont RECRÉÉS, et non perdus** : l'éditeur
            // (`EditeurEntree`) en a besoin dans ses champs de texte. Cible
            // `nil` : l'action suit le PREMIER RÉPONDANT, exactement le
            // mécanisme standard par lequel un champ de texte les traite déjà
            // — à la différence de Select All / Delete, ces trois-là n'ont
            // jamais posé de problème de chaîne de répondants.
            //
            // **Grisées hors d'un champ de texte** (`champTexteFocalise`,
            // remonté par `EditeurEntree` via son `@FocusState`) : sans ce
            // test, elles restaient cliquables en permanence, sans jamais se
            // désactiver comme les items système d'origine.
            CommandGroup(replacing: .pasteboard) {
                Button("Couper") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)
                .disabled(!champTexteFocalise)
                Button("Copier") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(!champTexteFocalise)
                Button("Coller") {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(!champTexteFocalise)
                Divider()
                // Même bascule que Couper/Copier/Coller : dans un champ de
                // texte, « Tout sélectionner » doit en sélectionner le texte
                // (action native, premier répondant) — pas relancer la
                // sélection des lignes de `VueFeuille`, masquée derrière
                // l'éditeur. Disabled UNIQUEMENT quand l'éditeur est ouvert
                // SANS champ focalisé : rien de sensé à sélectionner alors.
                Button("Tout sélectionner") {
                    if champTexteFocalise {
                        NSApp.sendAction(Selector(("selectAll:")), to: nil, from: nil)
                    } else {
                        signalToutSelectionner += 1
                    }
                }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(editeurOuvert && !champTexteFocalise)
                Button("Supprimer") { signalSupprimer += 1 }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(editeurOuvert || !uneSelectionExiste)

                Divider()

                Button(selectionEstToutFavorite ? "Retirer des favoris" : "Ajouter aux favoris") {
                    signalBasculerFavori += 1
                }
                .disabled(editeurOuvert || !uneSelectionExiste)
            }
            // Commandes d'ouverture / fermeture de l'éditeur, dans le menu « Édition ».
            CommandGroup(after: .pasteboard) {
                Divider()
                if editeurOuvert {
                    // L'éditeur est ouvert : la commande le ferme.
                    Button("Fermer l'éditeur") { signalFermerEditeur += 1 }
                        .keyboardShortcut("e", modifiers: .command)
                } else {
                    // L'éditeur est fermé : la commande l'ouvre sur la sélection
                    // (grisée si rien n'est sélectionné).
                    Button("Ouvrir l'éditeur") { signalOuvrirEditeur += 1 }
                        .keyboardShortcut("e", modifiers: .command)
                        .disabled(!uneSelectionExiste)
                }
            }
            CommandGroup(replacing: .toolbar) {
                // On reconstruit ici le contenu utile du menu « Présentation ».
                // Galerie en tête, même ordre que les boutons de la barre
                // d'outils : c'est la présentation par défaut.
                Toggle("Galerie", isOn: Binding(
                    get: { modeAffichage == "icone" },
                    set: { if $0 { modeAffichage = "icone" } }))
                    .keyboardShortcut("2", modifiers: .command)

                Toggle("Liste", isOn: Binding(
                    get: { modeAffichage == "liste" },
                    set: { if $0 { modeAffichage = "liste" } }))
                    .keyboardShortcut("1", modifiers: .command)

                Divider()

                // Afficher / Masquer l'inspecteur, seulement en mode galerie.
                if modeAffichage == "icone" {
                    Button(inspecteurVisible ? "Masquer l'inspecteur"
                                             : "Afficher l'inspecteur") {
                        inspecteurVisible.toggle()
                    }
                    .keyboardShortcut("i", modifiers: [.command, .option])

                    Divider()
                }

                // Masquer / afficher les prix partout dans l'application.
                // Grisé dans les Dons et la Réserve : ces œuvres n'ont pas de
                // prix, et le bouton correspondant est absent de la toolbar.
                if prixMasques {
                    Button("Afficher les prix") { prixMasques = false }
                        .keyboardShortcut("p", modifiers: [.command, .shift])
                        .disabled(rubriqueSansPrix)
                } else {
                    Button("Masquer les prix") { prixMasques = true }
                        .keyboardShortcut("p", modifiers: [.command, .shift])
                        .disabled(rubriqueSansPrix)
                }
            }
        }
        #endif
    }

    #if os(macOS)
    /// Pose l'action demandée et incrémente le signal pour la déclencher dans
    /// la vue de feuille active.
    private func declencherFichier(_ action: String) {
        actionFichier = action
        actionFichierSignal += 1
    }
    #endif
}
