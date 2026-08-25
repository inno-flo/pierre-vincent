import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Catégories affichées dans la barre latérale (sidebar).
/// L'ordre est volontaire : Inventaire en premier, Synthèse en dernier.
/// Note : pas de `CaseIterable`, incompatible avec un cas à valeur associée.
/// `allCases` ne servait qu'à `categoriesData`, qui n'était appelé nulle part.
enum Categorie: Hashable, Identifiable {
    case oeuvres          // vue compilée (agrège les 4 feuilles)
    case tableauxVendus
    case dessinsVendus
    case tapisVendus
    case oeuvresDonnees
    case ventesRealisees  // ventes en exposition ou aux enchères (filtre sur modeVente)
    case reserveInventaire // Réserve : toutes les œuvres encore détenues
    case reserveDessins   // Réserve : dessins encore disponibles
    case reserveTableaux  // Réserve : tableaux encore disponibles
    case reserveCollection // Réserve : œuvres rangées en collection personnelle
    /// Rubrique isolée, sous la Réserve et hors de toute section : les œuvres
    /// mises en favori. **Vide pour l'instant** — le champ qui les marquera
    /// n'existe pas encore, et l'entrée « Ajouter aux favoris » du menu
    /// contextuel iPhone reste inerte.
    case favoris
    /// Sous-catégorie de la Réserve : un thème précis. Même principe que
    /// `modeVente` — la valeur est portée par le cas, ce qui permet un nombre
    /// variable de rubriques déduites des données (voir `themesPresents`).
    case reserveTheme(String)
    /// Sous-catégorie de Ventes : un mode de vente précis. La valeur est
    /// portée par le cas lui-même, ce qui permet un nombre variable de
    /// sous-catégories, déduites des données (voir `modesDeVentePresents`).
    case modeVente(String)
    case synthese         // tableau de bord, en dernier

    var id: Self { self }

    var titre: String {
        switch self {
        case .oeuvres:          return "Catalogue"
        case .tableauxVendus:   return "Tableaux"
        case .dessinsVendus:    return "Dessins"
        case .tapisVendus:      return "Tapis"
        case .oeuvresDonnees:   return "Dons"
        case .ventesRealisees:  return "Ventes"
        case .reserveInventaire: return "Catalogue"
        case .reserveDessins:   return "Dessins"
        case .reserveTableaux:  return "Tableaux"
        case .reserveCollection: return "Collection personnelle"
        case .favoris:          return "Favoris"
        // Rendu au pluriel — et « Portraits » pour « Personnage » — comme les
        // modes de vente plus bas : la valeur STOCKÉE sur l'œuvre ne change
        // pas, c'est elle que voient l'éditeur, l'inspecteur et le filtre.
        // Un thème inédit garde son libellé tel quel.
        case .reserveTheme(let t):
            switch t.lowercased() {
            case "bouquet":      return "Bouquets"
            case "nature morte": return "Natures mortes"
            case "paysage":      return "Paysages"
            case "portrait":     return "Portraits"
            default:             return t
            }
        case .synthese:         return "Synthèse"
        // Forme d'affichage du mode : la rubrique regroupe PLUSIEURS ventes,
        // d'où le pluriel, alors que la valeur stockée sur une œuvre reste au
        // singulier (« Exposition »). Un mode inédit garde son libellé tel
        // quel, faute de forme plurielle connue.
        case .modeVente(let m):
            switch m.lowercased() {
            case "exposition":         return "Expositions"
            case "vente aux enchères": return "Ventes aux enchères"
            default:                   return m
            }
        }
    }

    var symbole: String {
        switch self {
        // Les deux rubriques « Catalogue » partagent le même symbole : elles
        // portent le même nom et jouent le même rôle dans leur section.
        case .oeuvres:          return "photo.artframe"
        case .tableauxVendus:   return "paintpalette"
        case .dessinsVendus:    return "pencil.and.outline"
        case .tapisVendus:      return "square.grid.3x3.square"
        case .oeuvresDonnees:   return "gift"
        case .ventesRealisees:  return "creditcard"
        case .reserveInventaire: return "photo.artframe"
        case .reserveDessins:   return "pencil.and.outline"
        case .reserveTableaux:  return "paintpalette"
        case .reserveCollection: return "person"
        // Même étoile que l'entrée « Ajouter aux favoris » du menu contextuel.
        case .favoris:          return "star"
        case .reserveTheme:     return "paintbrush.pointed"
        case .synthese:         return "chart.bar.doc.horizontal"
        // Les trois sous-rubriques de « Modes de vente » — et tout mode inédit
        // — partagent ce symbole : le cas est à valeur associée, il n'y a
        // qu'une branche pour tous.
        case .modeVente:        return "cart"
        }
    }

    /// La feuille correspondante (nil pour les vues agrégées).
    var feuille: Feuille? {
        switch self {
        case .oeuvres:          return nil
        case .tableauxVendus:   return .tableauxVendus
        case .dessinsVendus:    return .dessinsVendus
        case .tapisVendus:      return .tapisVendus
        case .oeuvresDonnees:   return .oeuvresDonnees
        case .ventesRealisees:  return nil
        // La Réserve a désormais sa propre feuille : les deux rubriques s'y
        // rapportent, et c'est le TYPE qui distingue Dessins du Catalogue.
        case .reserveInventaire: return .reserve
        case .reserveDessins:   return .reserve
        case .reserveTableaux:  return .reserve
        case .reserveCollection: return .reserve
        // `.reserve` **par provision**, pour que la vue soit en tous points
        // celle du Catalogue de la Réserve : pas de récapitulatif, pas de
        // prix, pas de menu de tri — tout cela se déduit de la feuille dans
        // `VueiOS` comme dans `VueFeuille`.
        //
        // À revoir le jour où le champ « favori » existera : un favori pourra
        // alors venir de n'importe quelle feuille, et la rubrique devra
        // devenir une vue agrégée (`nil`) filtrée sur ce champ.
        case .favoris:          return .reserve
        // Même feuille que le reste de la Réserve : c'est le THÈME qui
        // restreint, pas la feuille.
        case .reserveTheme:     return .reserve
        case .synthese:         return nil
        // Vue agrégée, comme Ventes : le filtre porte sur le mode, pas la feuille.
        case .modeVente:        return nil
        }
    }

    /// Filtre sur le mode de vente (vide = aucun filtre supplémentaire).
    ///
    /// `.ventesRealisees` n'impose AUCUN mode : la rubrique recense toutes les
    /// œuvres vendues, quel que soit le canal. Sans quoi un mode inédit aurait
    /// sa sous-catégorie sans figurer dans Ventes — le parent cesserait d'être
    /// la somme de ses enfants. C'est `statuts` qui la restreint aux ventes.
    var modesVente: [String] {
        switch self {
        case .modeVente(let m): return [m]
        default:                return []
        }
    }

    /// Modes de vente de référence, dans leur ordre d'affichage. Les modes
    /// trouvés dans les données mais absents d'ici s'ajoutent à leur suite.
    static let modesDeVenteReference = ["Exposition", "Vente aux enchères", "Vente privée"]

    /// Statuts recensés par la rubrique.
    ///
    /// Par défaut, ceux de « Ventes et dons » — les œuvres sorties du fonds.
    /// Les rubriques de la **Réserve** recensent au contraire les œuvres
    /// encore détenues.
    var statuts: [String] {
        switch self {
        // **Liste VIDE, et c'est délibéré** : `correspond` exige que le statut
        // de l'œuvre figure dans cette liste, donc aucune œuvre ne satisfait
        // une liste vide. C'est ce qui rend la rubrique Favoris vide tant que
        // le champ qui marquera les favoris n'existe pas — plutôt que d'y
        // afficher tout le catalogue en attendant.
        case .favoris:
            return []
        case .reserveInventaire, .reserveDessins, .reserveTableaux,
             .reserveTheme, .reserveCollection:
            return statutsReserve
        // Ventes et ses sous-catégories : les œuvres VENDUES seulement — les
        // dons ont leur propre rubrique.
        case .ventesRealisees, .modeVente:
            return ["Vendu"]
        default:
            return Array(statutsVentesEtDons)
        }
    }

    /// Vrai pour la rubrique qui ne recense que la collection personnelle.
    ///
    /// Le critère est le champ `collectionPersonnelle`, posé à l'import par
    /// les mots-clés « à garder ». Il a remplacé une approximation fondée sur
    /// l'emplacement, faute de champ dédié à l'époque.
    ///
    /// La rubrique restant dans la Réserve, ses `statuts` excluent d'office
    /// les œuvres vendues ou données.
    var collectionSeule: Bool { self == .reserveCollection }

    /// Filtre sur le champ Thème (vide = aucun filtre).
    var themes: [String] {
        switch self {
        case .reserveTheme(let t): return [t]
        default:                   return []
        }
    }

    /// Filtre sur le champ Type (vide = aucun filtre).
    /// Comparaison insensible à la casse et aux espaces de bord.
    var types: [String] {
        switch self {
        case .reserveDessins:  return ["Dessin"]
        case .reserveTableaux: return ["Tableau"]
        default:              return []
        }
    }

    // Toutes les catégories macOS sont éditables (y compris « Œuvres » :
    // Ajouter/Modifier/Supprimer y sont possibles sur chaque entrée, seul le
    // bouton « Ajouter » reste absent faute de feuille cible unique).
    var lectureSeule: Bool { false }

    /// La visionneuse intégrée remplace Quick Look **PARTOUT** : barre
    /// d'espace sur Mac, appui prolongé sur iPhone, en liste comme en galerie,
    /// dans toutes les rubriques. L'essai mené sur la Réserve est concluant.
    ///
    /// Le drapeau est conservé plutôt que supprimé : le code de Quick Look
    /// reste en place derrière lui, et il suffit de renvoyer `false` pour y
    /// revenir sur tout ou partie des rubriques.
    var visionneuseIntegree: Bool { true }

    /// Vrai pour les rubriques de la section « Réserve ».
    ///
    /// Favoris en est EXCLUE : elle est détachée des deux blocs, et n'a donc
    /// pas à suivre les choix visuels de l'un d'eux.
    var estSectionReserve: Bool {
        if case .reserveTheme = self { return true }
        switch self {
        case .reserveInventaire, .reserveDessins, .reserveTableaux,
             .reserveCollection: return true
        default:                 return false
        }
    }

    /// Symbole de l'entrée « Tous » du menu de filtre par type.
    ///
    /// **L'icône de la rubrique elle-même, sans exception** : « Tous » y
    /// désigne la rubrique entière, et son icône le dit mieux qu'une grille
    /// générique. Vaut aussi pour le bouton du menu quand aucun type n'est
    /// retenu, exactement comme l'icône du menu de tri suit le critère actif.
    ///
    /// Les cinq rubriques de Thèmes y reçoivent donc le même
    /// `paintbrush.pointed`, leur cas n'ayant qu'une branche : l'icône ne les
    /// distingue pas entre elles, mais elle dit bien « tous les thèmes ».
    ///
    /// Propriété conservée plutôt qu'un `cat.symbole` posé aux cinq points
    /// d'appel : elle nomme l'intention, et une rubrique qui voudrait un jour
    /// une autre icône pour « Tous » se traiterait ici seulement.
    var symboleFiltreTous: String { symbole }

    /// Pastilles de type proposées par la rubrique — vide = pas de filtre.
    ///
    /// Concerne les rubriques qui **mêlent plusieurs types** sans que la
    /// feuille les distingue. Une rubrique déjà restreinte à un type
    /// (Réserve › Dessins, Tableaux vendus…) n'en a évidemment pas besoin.
    ///
    /// **La Réserve n'en propose que DEUX** : il n'y reste aucun tapis
    /// disponible, et une troisième pastille n'y filtrerait jamais que vers
    /// une liste vide. Le jour où un tapis y entre, c'est ici qu'on l'ajoute.
    ///
    /// Les **sous-rubriques de mode de vente** en ont les trois, comme Ventes
    /// dont elles sont des sous-ensembles. Elles cumulent donc deux filtres :
    /// par vendeur (celles qui l'ont) et par type. Les deux se composent, et
    /// se calculent dans cet ordre — voir `appliquerFiltres` côté Mac,
    /// `ventes` côté iPhone.
    var typesFiltre: [String] {
        if case .reserveTheme = self { return ["tableau", "dessin"] }
        if case .modeVente(let m) = self {
            // **Exposition n'a pas de pastille Tapis** : aucun tapis n'y a
            // été exposé, elle ne filtrerait que vers une liste vide. Le test
            // porte sur la valeur STOCKÉE, au singulier — « Expositions » au
            // pluriel n'est qu'un rendu de `titre`.
            if m.caseInsensitiveCompare("Exposition") == .orderedSame {
                return ["tableau", "dessin"]
            }
            return motsTypesFiltrables
        }
        switch self {
        case .oeuvres, .ventesRealisees, .oeuvresDonnees:
            return motsTypesFiltrables
        case .reserveInventaire, .reserveCollection, .favoris:
            return ["tableau", "dessin"]
        default:
            return []
        }
    }

    /// Modes de vente dont la vignette de galerie n'affiche PAS de ligne de
    /// nom : l'acheteur n'y renseigne pas, seuls le prix et les dimensions
    /// comptent. Ne reste que la maison ou le lieu, porté par le Vendeur.
    ///
    /// Liste distincte de `modesAvecFiltreVendeur` bien qu'elles coïncident
    /// aujourd'hui : l'une décide d'un filtre, l'autre d'un affichage. Les
    /// confondre ferait qu'ajouter un mode à l'une le changerait dans l'autre.
    static let modesSansNomEnGalerie = ["Vente aux enchères", "Exposition"]

    /// Vrai si la vignette de galerie porte une ligne de nom (acheteur,
    /// destinataire ou emplacement selon l'œuvre).
    var nomEnGalerie: Bool {
        guard case .modeVente(let m) = self else { return true }
        return !Categorie.modesSansNomEnGalerie.contains {
            $0.caseInsensitiveCompare(m) == .orderedSame
        }
    }

    /// Modes de vente dont la rubrique propose un bandeau de pastilles
    /// filtrant par vendeur : plusieurs maisons ou lieux s'y partagent les
    /// œuvres. Les pastilles elles-mêmes sont déduites des données, aucune
    /// liste de vendeurs n'est écrite en dur.
    static let modesAvecFiltreVendeur = ["Vente aux enchères", "Exposition"]

    /// Vrai si la rubrique propose un filtre par vendeur — le bandeau de
    /// pastilles sur Mac, le menu de la barre d'outils sur iPhone. L'étendre à
    /// un autre mode se résume à l'ajouter dans `modesAvecFiltreVendeur`.
    ///
    /// Seul réglage restant : les VENDEURS eux-mêmes sont déduits des données
    /// sur les deux plateformes. La liste `filtresVendeur`, qui les nommait en
    /// dur, a disparu — elle proposait des entrées ne filtrant vers rien.
    var filtreParVendeur: Bool {
        guard case .modeVente(let m) = self else { return false }
        return Categorie.modesAvecFiltreVendeur.contains {
            $0.caseInsensitiveCompare(m) == .orderedSame
        }
    }

    /// Vrai pour la rubrique Ventes ET ses sous-catégories par mode : elles
    /// partagent la même vue. Un test d'égalité `== .ventesRealisees` ne
    /// couvrirait pas le cas à valeur associée.
    var estVenteRealisee: Bool {
        switch self {
        case .ventesRealisees, .modeVente: return true
        default:                           return false
        }
    }

    /// Accent de la rubrique : **bleu ardoise dans la Réserve**, orange
    /// ailleurs. La couleur dit d'un coup d'œil dans quelle section on se
    /// trouve, sans avoir à lire le titre.
    ///
    /// Descend ensuite par l'environnement (`accentRubrique`) jusqu'aux
    /// vignettes, pastilles, prix et boutons de la visionneuse.
    var accent: Color {
        switch self {
        case .reserveInventaire, .reserveDessins, .reserveTableaux,
             .reserveTheme, .reserveCollection, .favoris: return .bleuArdoise
        default:                 return .orangeInternational
        }
    }

    /// Vrai pour la vue tableau de bord (affichage spécifique).
    var estSynthese: Bool { self == .synthese }
}

/// Vue principale : barre latérale (catégories) + zone de contenu (canvas),
/// selon le principe des Split Views de macOS.
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query private var toutes: [Oeuvre]

    // Catégorie sélectionnée au lancement :
    // - iPhone : aucune (nil) pour afficher d'abord la barre latérale ;
    // - Mac : « Œuvres » pré-sélectionnée (les deux colonnes sont visibles).
    #if os(macOS)
    @State private var categorie: Categorie? = .oeuvres
    #else
    @State private var categorie: Categorie? = nil
    #endif
    // Nombre d'entrées sélectionnées dans la vue courante (remonté par VueFeuille),
    // pour l'afficher dans le bandeau bas de la sidebar.
    @State private var nbSelection: Int = 0
    // Masquage des prix (partagé iOS + Mac).
    @AppStorage("prixMasques") private var prixMasques = false
    // Repères des reprises de données ponctuelles sur le champ Statut.
    // `statutVenduRempli` : première passe, ventes uniquement (déjà exécutée).
    // `statutParDefautRempli` : seconde passe, qui ajoute « Donné » aux dons.
    @AppStorage("statutVenduRempli") private var statutVenduRempli = false
    @AppStorage("statutParDefautRempli") private var statutParDefautRempli = false
    // `modeVenteDonRempli` : troisième passe, Mode de vente « Don » sur les dons.
    @AppStorage("modeVenteDonRempli") private var modeVenteDonRempli = false
    // `champsVidesRemplis` : quatrième passe, « Inconnu » partout où c'est vide.
    @AppStorage("champsVidesRemplis") private var champsVidesRemplis = false
    // `feuilleReserveRemplie` : cinquième passe, feuille « Réserve » sur les
    // œuvres encore détenues. Nouveau drapeau obligatoire — les précédents
    // sont consommés et ne se redéclenchent jamais.
    @AppStorage("feuilleReserveRemplie") private var feuilleReserveRemplie = false
    // `themePortraitRenomme` : sixième passe, « Personnage » → « Portrait ».
    @AppStorage("themePortraitRenomme") private var themePortraitRenomme = false
    // `dimensionsNormalisees` : septième passe, format « 60x50 ».
    @AppStorage("dimensionsNormalisees") private var dimensionsNormalisees = false
    // `statutsVidesRepares` : huitième passe, rattrapage des œuvres importées
    // par photo sans statut, invisibles dans toutes les vues.
    @AppStorage("statutsVidesRepares") private var statutsVidesRepares = false
    // `aGarderConverti` : neuvième passe, « À garder » devient « Disponible ».
    @AppStorage("aGarderConverti") private var aGarderConverti = false
    // `reservePurgee` : purge ponctuelle de la Réserve, pour reprendre l'import
    // de photos à zéro. DESTRUCTIF — voir `RepriseDonnees.purgerReserve`.
    @AppStorage("reservePurgee") private var reservePurgee = false
    // `doublonsImportSupprimes` : suppression des doublons d'un import répété.
    @AppStorage("doublonsImportSupprimes") private var doublonsImportSupprimes = false
    // `collectionNormalisee` : le champ Collection personnelle devient binaire.
    @AppStorage("collectionNormalisee") private var collectionNormalisee = false
    // `tapisDonnesRanges` : les tapis au statut « Donné » rejoignent la
    // feuille des dons, seule façon pour eux d'apparaître dans la rubrique.
    @AppStorage("tapisDonnesRanges") private var tapisDonnesRanges = false
    // Ouverture/fermeture des blocs de la sidebar. Les replis faits à la main
    // valent pour la session : `PierreVincentApp.arrangerSidebar()` réécrit ces
    // clés à chaque lancement — les deux grands blocs dépliés, les quatre
    // sous-groupes repliés. Les valeurs ci-dessous ne servent donc que de
    // garde-fou, et suivent le même arrangement.
    @AppStorage("blocVentesOuvert") private var blocVentesOuvert = true
    @AppStorage("blocStockOuvert") private var blocStockOuvert = true
    @AppStorage("sousBlocCategoriesOuvert") private var sousBlocCategoriesOuvert = false
    @AppStorage("sousBlocModesVenteOuvert") private var sousBlocModesVenteOuvert = false
    @AppStorage("sousBlocReserveCategoriesOuvert") private var sousBlocReserveCategoriesOuvert = false
    @AppStorage("sousBlocReserveThemesOuvert") private var sousBlocReserveThemesOuvert = false
    #if os(iOS)
    // Import de la base sur iPhone (depuis un fichier .pvbase via Fichiers).
    @State private var importerBaseOuvert = false
    @State private var messageImportBase: String?
    // Section qui vient d'être choisie : reste teintée un court instant
    // après la sélection (pour accompagner la transition), puis s'éteint
    // TOUTE SEULE — sans dépendre du retour à cette vue, qui n'est pas
    // fiable à observer avec NavigationSplitView (onDisappear ne se
    // déclenche pas systématiquement sur sa colonne « detail »).
    // Piloté uniquement par le changement officiel de `categorie` (aucun
    // geste personnalisé sur les lignes : un DragGesture, même en
    // simultaneousGesture, entre par moments en concurrence avec le tap
    // natif du NavigationLink et empêche la navigation par intermittence.
    @State private var categorieRecemmentChoisie: Categorie?
    @State private var tacheExtinctionSurbrillance: Task<Void, Never>?
    #endif

    var body: some View {
        NavigationSplitView {
            // --- Barre latérale ---
            VStack(spacing: 0) {
                List(selection: $categorie) {
                    #if os(macOS)
                    // `Section(isExpanded:)` : mécanisme standard des sidebars
                    // macOS (le triangle d'affichage de Finder ou Mail).
                    Section(isExpanded: $blocVentesOuvert) {
                        contenuVentesEtDons
                    } header: {
                        Text("Ventes et dons").font(policeGrandIntitule).fontWeight(.bold)
                    }
                    Section(isExpanded: $blocStockOuvert) {
                        contenuStock
                    } header: {
                        Text("Réserve").font(policeGrandIntitule).fontWeight(.bold)
                    }
                    // Rubrique ISOLÉE : une section sans en-tête et sans
                    // repli, détachée des deux blocs. Elle ne relève ni des
                    // ventes ni de la réserve — un favori peut venir de l'une
                    // comme de l'autre.
                    Section {
                        lien(.favoris)
                    }
                    #endif
                    #if os(iOS)
                    // Sur iOS, `Section(isExpanded:)` n'est honoré qu'avec
                    // `listStyle(.sidebar)` : en `.insetGrouped`, le paramètre
                    // est ignoré et la section n'est pas repliable. On passe
                    // donc par un `DisclosureGroup`, qui l'est toujours.
                    Section {
                        DisclosureGroup(isExpanded: $blocVentesOuvert) {
                            contenuVentesEtDons
                        } label: {
                            Text("Ventes et dons").font(policeGrandIntitule).fontWeight(.bold)
                        }
                    }
                    Section {
                        DisclosureGroup(isExpanded: $blocStockOuvert) {
                            contenuStock
                        } label: {
                            Text("Réserve").font(policeGrandIntitule).fontWeight(.bold)
                        }
                    }
                    // Rubrique ISOLÉE, détachée des deux blocs : elle ne
                    // relève ni des ventes ni de la réserve, un favori pouvant
                    // venir de l'une comme de l'autre. Pas de repliement non
                    // plus — elle n'a qu'une ligne.
                    Section {
                        lien(.favoris)
                    }
                    #endif
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.cremeFond)
                // Déclenché uniquement par la sélection officielle
                // (fiable), jamais par un geste personnalisé sur les
                // lignes : voir la remarque sur categorieRecemmentChoisie.
                .onChange(of: categorie) { _, nouvelle in
                    guard let nouvelle else { return }
                    categorieRecemmentChoisie = nouvelle
                    // Réarme le minuteur d'extinction à chaque sélection.
                    tacheExtinctionSurbrillance?.cancel()
                    tacheExtinctionSurbrillance = Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)   // 0,4 s
                        if !Task.isCancelled { categorieRecemmentChoisie = nil }
                    }
                }
                #else
                .listStyle(.sidebar)
                // Couleur de sélection des rubriques : marron au lieu du bleu.
                // `.tint()` n'a AUCUN effet sur la surbrillance d'une List en
                // style sidebar (essayé, sans résultat) : on désactive la
                // surbrillance système sur le NSOutlineView et on peint le fond
                // nous-mêmes via .listRowBackground dans lien().
                .background(DesactiveSurbrillanceSidebar())
                // ↑↓ : ni onKeyPress (SwiftUI capte avant AppKit sans traiter),
                // ni repli sur le natif (le premier répondant ne suit pas les
                // clics de façon fiable ici). On passe par un capteur NSEvent
                // au niveau fenêtre, actif seulement quand la zone clavier est
                // la sidebar — voir ZoneClavier dans CaptureEspace.swift.
                .background(
                    CaptureFleches(zone: ZoneClavier.sidebar) { delta in
                        naviguerSidebar(delta: delta)
                    }
                )
                // Choisir une rubrique rend la main au clavier à la sidebar.
                .onChange(of: categorie) { _, nouvelle in
                    if nouvelle != nil { ZoneClavier.definir(ZoneClavier.sidebar) }
                }
                // ←→ ne sont pas consommées par NSOutlineView.
                .onKeyPress(.rightArrow) {
                    // Déplace le focus vers la zone de contenu (colonne détail).
                    NSApp.keyWindow?.selectNextKeyView(nil)
                    return .handled
                }
                #endif

                // --- Zone du bas de la sidebar ---
                // Occupée par la progression d'import, et par elle seule :
                // hors import, le bas de la barre latérale reste vide, comme
                // avant. A successivement porté les pastilles de choix de
                // thème, le bouton « G » de mise en gras des en-têtes, puis la
                // pastille de comparaison des deux marrons de sélection.
                #if os(macOS)
                if ProgressionImport.partagee.enCours {
                    Divider()
                    barreProgressionImport
                }
                #endif
            }
            #if os(iOS)
            // Fond de toute la colonne.
            .background(Color.cremeFond)
            #endif
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
            #if os(iOS)
            // Titre général de la colonne sidebar — vue racine de la pile de
            // navigation sur iPhone, le split view s'y repliant en largeur
            // compacte. En grand format, comme le « Feeds » de NetNewsWire.
            .navigationTitle("Inventaire")
            .navigationBarTitleDisplayMode(.large)
            // Bouton d'import de la base (fichier .pvbase reçu du Mac).
            .toolbar {
                // Import en premier, puis œil (masquage des prix).
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        importerBaseOuvert = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        prixMasques.toggle()
                    } label: {
                        Image(systemName: prixMasques ? "eye.slash" : "eye")
                    }
                }
            }
            // Sélecteur de fichier via l'app Fichiers (iCloud Drive inclus).
            .fileImporter(
                isPresented: $importerBaseOuvert,
                allowedContentTypes: [UTType.data],
                allowsMultipleSelection: false
            ) { resultat in
                gererImportBase(resultat)
            }
            .alert("Import de la base", isPresented: Binding(
                get: { messageImportBase != nil },
                set: { if !$0 { messageImportBase = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(messageImportBase ?? "") }
            #endif
        } detail: {
            // --- Zone de contenu (canvas) ---
            if let cat = categorie {
                // Accent posé ICI, une seule fois : il descend ensuite dans
                // toute la colonne — vignettes, pastilles, prix, éditeur,
                // visionneuse — y compris à travers les feuilles et les
                // présentations plein écran, qui héritent de l'environnement.
                Group {
                if cat.estSynthese {
                    VueSynthese(toutes: toutes)
                } else {
                    #if os(macOS)
                    // Interface Mac complète (édition, exports, etc.).
                    VueFeuille(feuille: cat.feuille,
                               lectureSeule: cat.lectureSeule,
                               titre: cat.titre,
                               modesVente: cat.modesVente,
                               statuts: cat.statuts,
                               types: cat.types,
                               themes: cat.themes,
                               collectionSeule: cat.collectionSeule,
                               filtreParVendeur: cat.filtreParVendeur,
                               typesFiltre: cat.typesFiltre,
                               symboleFiltreTous: cat.symboleFiltreTous,
                               nomEnGalerie: cat.nomEnGalerie,
                               visionneuseIntegree: cat.visionneuseIntegree,
                               nbSelection: $nbSelection)
                    // PAS de `.id(cat)` ici. Il détruisait et reconstruisait
                    // toute la vue à chaque changement de rubrique, donc aussi
                    // sa `.toolbar` — et la NSToolbar reconstruite réanimait le
                    // bouton de masquage de la sidebar, qu'on voyait clignoter
                    // (deux icônes superposées) pendant la navigation ↑↓.
                    // La remise à zéro qu'il assurait est faite par
                    // `VueFeuille` elle-même, sur `cleRubrique`.
                    #else
                    // Interface iPhone/iPad de consultation (lecture seule).
                    // La vue « Œuvres » a une présentation structurée
                    // (récapitulatif + sections Ventes et Dons).
                    if cat == .oeuvres {
                        VueOeuvresStructuree(typesFiltre: cat.typesFiltre,
                                             symboleFiltreTous: cat.symboleFiltreTous)
                            .id(cat)
                    } else if cat.estVenteRealisee {
                        // `estVenteRealisee` couvre AUSSI les sous-rubriques
                        // de mode de vente, dont `typesFiltre` est vide : la
                        // même ligne donne trois pastilles à Ventes et aucune
                        // à Expositions ou Vente privée.
                        VueOeuvresStructuree(modesVente: cat.modesVente,
                                             filtreParVendeur: cat.filtreParVendeur,
                                             estModeVentes: true,
                                             titre: cat.titre,
                                             nomEnGalerie: cat.nomEnGalerie,
                                             typesFiltre: cat.typesFiltre,
                                             symboleFiltreTous: cat.symboleFiltreTous)
                            .id(cat)
                    } else if cat == .oeuvresDonnees {
                        VueDonsStructuree(typesFiltre: cat.typesFiltre,
                                          symboleFiltreTous: cat.symboleFiltreTous)
                            .id(cat)
                    } else {
                        VueiOS(feuille: cat.feuille, titre: cat.titre,
                               modesVente: cat.modesVente,
                               filtreParVendeur: cat.filtreParVendeur,
                               statuts: cat.statuts,
                               types: cat.types,
                               themes: cat.themes,
                               collectionSeule: cat.collectionSeule,
                               typesFiltre: cat.typesFiltre,
                               symboleFiltreTous: cat.symboleFiltreTous,
                               visionneuseIntegree: cat.visionneuseIntegree)
                            .id(cat)
                    }
                    #endif
                }
                }
                .environment(\.accentRubrique, cat.accent)
            } else {
                Text("Choisissez une catégorie")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            // Nettoyage des photos orphelines au démarrage : on retire du dossier
            // Photos les fichiers qui ne sont plus liés à aucune entrée (restes
            // de suppressions passées). Sans risque ici car l'historique
            // d'annulation est vide au lancement.
            let nomsUtilises = Set(toutes.map { $0.photoNom }.filter { !$0.isEmpty })
            PhotoStore.nettoyerPhotosOrphelines(nomsUtilises: nomsUtilises)

            // Données de TEST (développement) : remplit la base si elle est
            // vide, pour visualiser l'interface. Ne s'active jamais si des
            // données existent déjà, donc sans risque pour de vraies données.
            DonneesTest.genererSiVide(context: context)

            // Reprise ponctuelle : renseigne le Statut par défaut — « Donné »
            // pour les dons, « Vendu » pour les autres — sur les œuvres dont il
            // est encore vide. Ne s'exécute qu'une fois et n'écrase aucune
            // saisie. Repère distinct de `statutVenduRempli` : cette première
            // reprise a déjà tourné, il faut donc un nouveau déclencheur pour
            // rattraper les dons.
            if !statutParDefautRempli {
                RepriseDonnees.remplirStatutParDefaut(context: context)
                statutParDefautRempli = true
            }

            // Reprise ponctuelle : Mode de vente « Don » sur les dons dont ce
            // champ est vide. Repère distinct, les précédents ayant déjà tourné.
            if !modeVenteDonRempli {
                RepriseDonnees.remplirModeVenteDon(context: context)
                modeVenteDonRempli = true
            }

            // Reprise ponctuelle : « Inconnu » dans tous les champs texte
            // encore vides. À faire APRÈS les reprises de statut ci-dessus,
            // qui ne remplissent que les champs vides — sinon elles ne
            // trouveraient plus rien à remplir.
            if !champsVidesRemplis {
                RepriseDonnees.remplirChampsVides(context: context)
                champsVidesRemplis = true
            }

            // Reprise ponctuelle : feuille « Réserve » sur les œuvres encore
            // détenues. APRÈS les reprises de statut, dont elle se sert pour
            // décider — sinon elle ne trouverait pas les statuts sur lesquels
            // s'appuyer.
            if !feuilleReserveRemplie {
                RepriseDonnees.remplirFeuilleReserve(context: context)
                feuilleReserveRemplie = true
            }

            // Reprise ponctuelle : le thème « Personnage » devient
            // « Portrait », valeur désormais écrite par l'import photos.
            if !themePortraitRenomme {
                RepriseDonnees.renommerThemePortrait(context: context)
                themePortraitRenomme = true
            }

            // Reprise ponctuelle : harmonise le champ Dimensions au modèle
            // « 60x50 » (ni espaces, ni unité).
            if !dimensionsNormalisees {
                RepriseDonnees.normaliserDimensions(context: context)
                dimensionsNormalisees = true
            }

            // Reprise ponctuelle : statut « Disponible » et feuille Réserve sur
            // les œuvres au statut vide, que rien n'affichait.
            if !statutsVidesRepares {
                RepriseDonnees.reparerStatutsVides(context: context)
                statutsVidesRepares = true
            }

            // Reprise ponctuelle : « À garder » devient « Disponible », la
            // table de correspondance ne produisant plus que cette valeur.
            if !aGarderConverti {
                RepriseDonnees.convertirAGarderEnDisponible(context: context)
                aGarderConverti = true
            }

            // Reprise ponctuelle : « Oui » ou « Non », jamais un vide.
            if !collectionNormalisee {
                RepriseDonnees.normaliserCollectionPersonnelle(context: context)
                collectionNormalisee = true
            }

            // Reprise ponctuelle : un tapis donné doit être dans la FEUILLE
            // des dons, la rubrique se définissant par elle et non par le
            // statut. Restreinte aux tapis, voir `rangerTapisDonnes`.
            if !tapisDonnesRanges {
                RepriseDonnees.rangerTapisDonnes(context: context)
                tapisDonnesRanges = true
            }

            // Suppression des doublons d'import : feuille « Tableaux vendus »
            // avec un statut de réserve, combinaison contradictoire qui ne
            // s'affiche nulle part. Voir `supprimerDoublonsImport`.
            if !doublonsImportSupprimes {
                RepriseDonnees.supprimerDoublonsImport(context: context)
                doublonsImportSupprimes = true
            }

            // PURGE DE LA RÉSERVE : DÉBRANCHÉE, elle visait le mauvais lot.
            // L'export a montré que les œuvres de la Réserve sont la BONNE
            // copie, et que les doublons se trouvent ailleurs — feuille
            // « Tableaux vendus » avec un statut « Disponible », donc
            // invisibles partout. Ne pas rebrancher `purgerReserve`.
            // if !reservePurgee {
            //     RepriseDonnees.purgerReserve(context: context)
            //     reservePurgee = true
            // }
        }
        #if os(iOS)
        .detecteSecoussePourPrix()
        // Message éphémère du masquage des prix, rendu par `PastillePrix`
        // dans une FENÊTRE à part : un overlay SwiftUI, même posé ici sur la
        // racine, passerait derrière la fiche de détail, qui est une `.sheet`.
        //
        // Déclenché par la VALEUR et non par le bouton : la secousse doit
        // afficher le même message.
        .onChange(of: prixMasques) { _, masques in
            PastillePrix.shared.afficher(masques: masques)
        }
        #endif
        // Couleur de texte par défaut suivant le thème.
        .foregroundStyle(Color.textePrincipal)
        #if os(iOS)
        // Garde la barre de navigation transparente pour laisser voir le fond
        // coloré du thème derrière ; les titres suivent la couleur système.
        .apparenceTitresNavigation()
        #endif
        // NB : plus de `.id(themeApp)` ici. Ce modificateur ne servait qu'à
        // recréer toute la hiérarchie au changement de thème pour relire les
        // couleurs. Le thème ne changeant plus à l'exécution (sélecteur
        // supprimé), il était inutile — et il remettait à zéro l'état de
        // focus clavier au passage (@FocusState), ce qui faisait repasser la
        // sélection de la liste en bleu et perturbait la navigation ↑↓.
    }

    #if os(macOS)
    // MARK: Navigation clavier de la sidebar (macOS)

    /// Ordre d'affichage des rubriques, pour la navigation ↑↓.
    ///
    /// **Reflet exact de la sidebar, et non une liste figée.** La version
    /// précédente était écrite en dur et datait d'une organisation antérieure :
    /// les flèches sautaient les modes de vente et tout le bloc Réserve, qui
    /// n'y figuraient pas.
    ///
    /// Deux conséquences à préserver :
    /// - les modes de vente sont **déduits des données** (`modesDeVentePresents`),
    ///   donc un mode inédit entre dans la navigation en même temps qu'il
    ///   apparaît dans la sidebar ;
    /// - un bloc **replié** ne fournit aucune rubrique, sinon les flèches
    ///   mèneraient à une ligne invisible à l'écran.
    private var categoriesSidebar: [Categorie] {
        var liste: [Categorie] = []
        if blocVentesOuvert {
            liste += [.oeuvres, .ventesRealisees, .oeuvresDonnees, .synthese]
            if sousBlocModesVenteOuvert {
                liste += modesDeVentePresents.map { Categorie.modeVente($0) }
            }
            if sousBlocCategoriesOuvert {
                liste += [.tableauxVendus, .dessinsVendus, .tapisVendus]
            }
        }
        if blocStockOuvert {
            liste.append(.reserveInventaire)
            liste.append(.reserveCollection)
            // MÊME ORDRE qu'à l'écran, sans quoi ↑↓ sauterait de rubrique en
            // rubrique dans un ordre qui ne correspond à rien de visible.
            if sousBlocReserveThemesOuvert {
                liste += themesPresents.map { Categorie.reserveTheme($0) }
            }
            if sousBlocReserveCategoriesOuvert {
                liste.append(.reserveTableaux)
                liste.append(.reserveDessins)
            }
        }
        // Hors des deux blocs, et donc toujours présente : elle ne dépend
        // d'aucun repli.
        liste.append(.favoris)
        return liste
    }

    /// Déplace la rubrique sélectionnée de `delta` (−1 = ↑, +1 = ↓).
    ///
    /// Si la rubrique courante ne figure pas dans la liste — rien de
    /// sélectionné, ou son bloc vient d'être replié — on entre par le bord
    /// correspondant au sens de la flèche.
    private func naviguerSidebar(delta: Int) {
        guard let courante = categorie,
              let idx = categoriesSidebar.firstIndex(of: courante) else {
            categorie = delta > 0 ? categoriesSidebar.first : categoriesSidebar.last
            return
        }
        let nouveau = idx + delta
        guard nouveau >= 0, nouveau < categoriesSidebar.count else { return }
        categorie = categoriesSidebar[nouveau]
    }
    #endif

    /// Raccourci : l'œuvre relève-t-elle de cette rubrique (statut + type) ?
    private func correspond(_ o: Oeuvre, a cat: Categorie) -> Bool {
        PierreVincent.correspond(o, statuts: cat.statuts, types: cat.types,
                                 themes: cat.themes,
                                 collectionSeule: cat.collectionSeule)
    }

    // MARK: Compteurs pour les pastilles de sous-rubriques (macOS)

    /// Nombre d'œuvres pour une sous-rubrique de la sidebar (nil = pas de
    /// pastille).
    ///
    /// **Une rubrique vide n'a pas de pastille** : un « 0 » n'apprend rien et
    /// alourdit la barre latérale. Le filtre est posé ICI, et non aux deux
    /// points d'affichage — macOS et iOS ne peuvent donc pas diverger sur ce
    /// point, comme ils l'ont déjà fait sur les filtres de comptage.
    private func compteurPourCategorie(_ cat: Categorie) -> Int? {
        guard let n = nombrePourCategorie(cat), n > 0 else { return nil }
        return n
    }

    /// Le compte brut, sans la règle d'affichage ci-dessus.
    private func nombrePourCategorie(_ cat: Categorie) -> Int? {
        // Même filtre que les vues, sinon les pastilles annonceraient des
        // nombres que l'utilisateur ne retrouverait pas à l'écran.
        let recensees = toutes.filter(estVenduOuDonne)
        switch cat {
        case .oeuvres:
            return recensees.count
        case .tableauxVendus:
            return recensees.filter { $0.feuille == .tableauxVendus }.count
        case .dessinsVendus:
            return recensees.filter { $0.feuille == .dessinsVendus }.count
        case .tapisVendus:
            return recensees.filter { $0.feuille == .tapisVendus }.count
        case .oeuvresDonnees:
            return recensees.filter { $0.feuille == .oeuvresDonnees }.count
        // Ventes, ses sous-catégories et la Réserve ont leurs propres statuts :
        // on repart de `toutes`, pas de `recensees`.
        case .ventesRealisees, .modeVente,
             .reserveInventaire, .reserveDessins, .reserveTableaux,
             .reserveTheme, .reserveCollection, .favoris:
            return toutes.filter { o in
                // La FEUILLE aussi, sinon la pastille annonce des œuvres que
                // la vue ne montre pas : c'est précisément ce qui affichait
                // « 9 » au-dessus d'une rubrique Dessins vide.
                if let f = cat.feuille, o.feuille != f { return false }
                guard correspond(o, a: cat) else { return false }
                let modes = cat.modesVente
                return modes.isEmpty || modes.contains(where: {
                    $0.caseInsensitiveCompare(o.modeVente) == .orderedSame
                })
            }.count
        default:
            return nil
        }
    }

    // MARK: Zone du bas de la sidebar

    #if os(macOS)
    /// Progression de l'import de photos, en pied de barre latérale.
    ///
    /// Lue sur `ProgressionImport.partagee` : l'import se déroule dans
    /// `VueFeuille`, à l'autre bout de la hiérarchie, et n'a aucun moyen de
    /// remonter son état jusqu'ici autrement.
    ///
    /// 11 pt, comme tout ce qui est subordonné aux libellés de rubrique.
    private var barreProgressionImport: some View {
        let suivi = ProgressionImport.partagee
        return HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Import \(suivi.traites) / \(suivi.total)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    #endif

    // VIDE. Le squelette est gardé en commentaire pour y reposer un bouton
    // temporaire de test — c'est ce qu'a porté cette zone à chaque fois :
    // pastilles de choix de thème, bouton « G » de mise en gras des en-têtes,
    // puis pastille de comparaison des deux marrons de sélection. Chacun a été
    // retiré une fois sa question tranchée.
    //
    // Le réactiver demande de décommenter LES DEUX blocs : celui-ci et l'appel
    // dans la VStack de la sidebar (`Divider()` + `barreOutilsBas`).
    //
    // #if os(macOS)
    // private var barreOutilsBas: some View {
    //     HStack(spacing: 10) {
    //         // …le bouton du moment…
    //         Spacer()
    //     }
    //     .padding(.horizontal, 20)
    //     .padding(.vertical, 10)
    // }
    // #endif

    // MARK: Lien de catégorie (barre latérale)

    #if os(iOS)
    /// Lit le fichier .pvbase sélectionné et remplace la base locale.
    private func gererImportBase(_ resultat: Result<[URL], Error>) {
        switch resultat {
        case .failure(let e):
            messageImportBase = "Échec : \(e.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            // Accès sécurisé au fichier (hors du bac à sable de l'app).
            let acces = url.startAccessingSecurityScopedResource()
            defer { if acces { url.stopAccessingSecurityScopedResource() } }
            do {
                let donnees = try Data(contentsOf: url)
                let r = EchangeBase.importerEnRemplacant(donnees: donnees, context: context)
                if let err = r.erreur {
                    messageImportBase = "Échec : \(err)"
                } else {
                    messageImportBase = "\(r.importees) œuvre(s) importée(s)."
                }
            } catch {
                messageImportBase = "Impossible de lire le fichier : \(error.localizedDescription)"
            }
        }
    }
    #endif

    // MARK: Contenu des deux grands blocs de la sidebar
    //
    // Trois niveaux de hiérarchie, marqués par la taille ET la graisse :
    //   1. grand intitulé   .title3 + gras   (Ventes et dons, Stock)
    //   2. sous-groupe      corps + semi-gras (Catégories, Expositions…)
    //   3. libellé          corps normal      (Tableaux, Dessins…)

    /// Police des deux grands intitulés (« Ventes et dons », « Stock »).
    /// `.title3` = 15 pt sur macOS, 20 pt sur iOS : plus gros que les libellés
    /// de rubrique (13 / 17 pt) dans les deux cas, ce qui marque la hiérarchie
    /// sans sortir du barème système.
    private var policeGrandIntitule: Font { .title3 }

    @ViewBuilder
    private var contenuVentesEtDons: some View {
        // Ventes et Dons sont au premier niveau, avec Catalogue et Synthèse :
        // ce sont des vues d'ensemble, pas des catégories d'œuvres.
        lien(.oeuvres)
        lien(.ventesRealisees)
        lien(.oeuvresDonnees)
        lien(.synthese)
        // Sous-groupe des modes de vente, construit d'après les données.
        DisclosureGroup(isExpanded: $sousBlocModesVenteOuvert) {
            ForEach(modesDeVentePresents, id: \.self) { mode in
                lien(.modeVente(mode))
            }
        } label: {
            Text("Modes de vente").fontWeight(.semibold)
        }
        // Sous-groupe repliable des catégories d'œuvres. `DisclosureGroup` et
        // non `Section` : une `List` n'accepte pas de Section dans une Section.
        DisclosureGroup(isExpanded: $sousBlocCategoriesOuvert) {
            lien(.tableauxVendus)
            lien(.dessinsVendus)
            lien(.tapisVendus)
        } label: {
            Text("Catégories").fontWeight(.semibold)
        }
    }

    /// Modes de vente réellement présents dans les données, dans l'ordre
    /// d'affichage : d'abord les modes de référence, puis les inédits par ordre
    /// alphabétique.
    ///
    /// C'est ce qui rend les sous-catégories **dynamiques** : un mode encore
    /// jamais vu — une nouvelle exposition, par exemple — crée sa rubrique dès
    /// qu'une œuvre le porte, sans modification du code.
    ///
    /// On écarte les valeurs vides, « Inconnu » et « Don » : la première ne
    /// désigne rien, la deuxième non plus, et les dons ont leur propre rubrique.
    private var modesDeVentePresents: [String] {
        func normal(_ v: String) -> String {
            v.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive],
                         locale: Locale(identifier: "fr_FR"))
        }
        let exclus: Set<String> = [normal(valeurInconnue), normal("Don"), ""]

        // Dédoublonnage sur la forme normalisée, mais on conserve la casse
        // d'origine pour l'affichage.
        var trouves: [String: String] = [:]
        for o in toutes where o.statut.caseInsensitiveCompare("Vendu") == .orderedSame {
            let brut = o.modeVente.trimmingCharacters(in: .whitespacesAndNewlines)
            let cle = normal(brut)
            guard !exclus.contains(cle), trouves[cle] == nil else { continue }
            trouves[cle] = brut
        }

        let reference = Categorie.modesDeVenteReference
        let clesReference = Set(reference.map(normal))
        let inedits = trouves
            .filter { !clesReference.contains($0.key) }
            .values
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        // Les modes de référence ne s'affichent que s'ils sont présents.
        let presentsParmiReference = reference.filter { trouves[normal($0)] != nil }
        return presentsParmiReference + inedits
    }

    /// Contenu du bloc « Réserve » : les œuvres encore détenues.
    @ViewBuilder
    private var contenuStock: some View {
        lien(.reserveInventaire)
        lien(.reserveCollection)
        // Même structure que « Ventes et dons » : un sous-groupe repliable
        // pour les catégories d'œuvres.
        // Thèmes AVANT Catégories, contrairement à « Ventes et dons » : ici
        // le thème est le critère de rangement principal des cartons.
        // Sous-groupe construit d'après les données.
        DisclosureGroup(isExpanded: $sousBlocReserveThemesOuvert) {
            ForEach(themesPresents, id: \.self) { theme in
                lien(.reserveTheme(theme))
            }
        } label: {
            Text("Thèmes").fontWeight(.semibold)
        }
        DisclosureGroup(isExpanded: $sousBlocReserveCategoriesOuvert) {
            lien(.reserveTableaux)
            lien(.reserveDessins)
        } label: {
            Text("Catégories").fontWeight(.semibold)
        }
    }

    /// Thèmes réellement présents dans la Réserve, par ordre alphabétique.
    ///
    /// **Déduits des données, aucune liste en dur** — même principe que
    /// `modesDeVentePresents` : un thème inédit obtient sa rubrique dès qu'une
    /// œuvre le porte, et elle disparaît quand plus aucune ne l'a.
    ///
    /// Ne balaie que les œuvres de la Réserve : un thème qui n'existerait que
    /// sur une œuvre vendue n'a pas de rubrique ici, où elle serait vide.
    /// Les valeurs vides et « Inconnu » sont écartées.
    private var themesPresents: [String] {
        var vus: [String: String] = [:]
        for o in toutes where o.feuille == .reserve && estEnReserve(o) {
            let brut = o.theme.trimmingCharacters(in: .whitespacesAndNewlines)
            let cle = brut.lowercased()
            guard !brut.isEmpty,
                  brut.caseInsensitiveCompare(valeurInconnue) != .orderedSame,
                  vus[cle] == nil else { continue }
            vus[cle] = brut
        }
        return vus.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Un lien de navigation vers une catégorie, avec son icône.
    /// Sur Mac, l'icône passe en blanc quand la catégorie est sélectionnée ;
    /// ailleurs (et sur iPhone), elle reste orange.
    private func lien(_ cat: Categorie) -> some View {
        NavigationLink(value: cat) {
            #if os(macOS)
            // Sur Mac : HStack personnalisé pour pouvoir placer la pastille à droite.
            HStack(spacing: 6) {
                Image(systemName: cat.symbole)
                    .foregroundStyle(categorie == cat
                                     ? Color.texteSelectionSidebarMac
                                     : cat.accent)
                // Rubrique sélectionnée : libellé gras sur le fond marron —
                // noir en mode clair, blanc en mode sombre (le marron y est
                // assombri). Voir Color.texteSelectionSidebarMac.
                // 13 pt = NSFont.systemFontSize, la taille standard d'un
                // libellé de sidebar sur macOS (les en-têtes de section, eux,
                // sont à 11 pt : ils doivent rester PLUS PETITS que les
                // libellés qu'ils regroupent).
                Text(cat.titre)
                    .font(.system(size: 13))
                    .fontWeight(categorie == cat ? .bold : .regular)
                    .foregroundStyle(categorie == cat
                                     ? Color.texteSelectionSidebarMac
                                     : Color.textePrincipal)
                if let n = compteurPourCategorie(cat) {
                    Spacer()
                    // Même traitement que les pastilles de filtre du panneau :
                    // contour orange et fond transparent au repos, fond orange
                    // et texte blanc quand la rubrique est sélectionnée.
                    // `Color.textePrincipal` vaut blanc en mode sombre : le
                    // texte y est donc blanc dans les deux états.
                    Text("\(n)")
                        // Même règle de graisse que le libellé de rubrique :
                        // normale au repos, grasse quand la rubrique est
                        // sélectionnée.
                        // Même règle que tout ce qui est subordonné à un
                        // libellé de sidebar : 11 pt, contre 13 au libellé.
                        // Les essais à 15 puis 13 pt dans la Réserve sont
                        // revenus ici — la taille ne distingue plus les deux
                        // sections, seul le contour le fait.
                        .font(.system(size: 11))
                        .fontWeight(categorie == cat ? .bold : .regular)
                        .foregroundStyle(categorie == cat ? Color.white : Color.textePrincipal)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            if categorie == cat {
                                Capsule().fill(cat.accent)
                            } else if !cat.estSectionReserve {
                                // ESSAI VISUEL : dans la Réserve, le chiffre
                                // reste nu au repos — pas de contour. Le fond
                                // plein de la rubrique sélectionnée, lui, est
                                // conservé partout.
                                Capsule().strokeBorder(cat.accent, lineWidth: 1)
                            }
                        }
                }
            }
            #else
            HStack(spacing: 6) {
                Label {
                    Text(cat.titre)
                } icon: {
                    Image(systemName: cat.symbole)
                        .foregroundStyle(cat.accent)
                }
                if let n = compteurPourCategorie(cat) {
                    Spacer()
                    // Même pastille que sur Mac : contour orange au repos,
                    // fond orange plein et texte blanc sur la rubrique
                    // sélectionnée.
                    // Corps SÉMANTIQUE et non 11 pt comme sur Mac : figer une
                    // taille en points casserait le Dynamic Type. `.caption`
                    // (12 pt) reste plus petit que le libellé (body, 17 pt),
                    // et suit les réglages système.
                    Text("\(n)")
                        // `.subheadline` vaut 15 pt à la taille « Large » —
                        // l'équivalent iOS des 15 pt demandés. Un style
                        // sémantique et NON une taille en points : figer les
                        // points ici casserait le Dynamic Type.
                        .font(cat.estSectionReserve ? .subheadline : .caption)
                        .fontWeight(categorie == cat ? .bold : .regular)
                        .foregroundStyle(categorie == cat ? Color.white : Color.textePrincipal)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            if categorie == cat {
                                Capsule().fill(cat.accent)
                            } else if !cat.estSectionReserve {
                                // ESSAI VISUEL : dans la Réserve, le chiffre
                                // reste nu au repos — pas de contour. Le fond
                                // plein de la rubrique sélectionnée, lui, est
                                // conservé partout.
                                Capsule().strokeBorder(cat.accent, lineWidth: 1)
                            }
                        }
                }
            }
            #endif
        }
        #if os(iOS)
        // Fond de cellule suivant le thème (blanc en clair, gris en sombre),
        // avec une teinte plus soutenue juste après la sélection (voir
        // categorieRecemmentChoisie, piloté par .onChange(of: categorie)
        // sur la liste). Aucun geste personnalisé ici : c'était la source
        // d'un bug de navigation aléatoire (tap sans effet), même avec
        // simultaneousGesture.
        .listRowBackground(
            categorieRecemmentChoisie == cat
                ? Color.fondCelluleSidebarSelectionnee : Color.fondCelluleSidebar)
        .animation(nil, value: categorieRecemmentChoisie)
        #else
        // Surbrillance de la rubrique sélectionnée, peinte par nous : la
        // surbrillance système (bleue) est désactivée sur le NSOutlineView,
        // voir DesactiveSurbrillanceSidebar.
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6)
                .fill(categorie == cat ? Color.fondSelectionSidebarMac : Color.clear)
                .padding(.horizontal, 4)
        )
        #endif
    }
}

#if os(iOS)
import UIKit

/// Modificateur qui garde la barre de navigation iOS transparente (pour laisser
/// voir le fond coloré du thème) tout en laissant les titres suivre la couleur
/// système (noir en mode Clair, blanc en mode Sombre — automatique).
private struct ApparenceTitresNavigation: ViewModifier {
    func body(content: Content) -> some View {
        content.onAppear { appliquer() }
    }

    private func appliquer() {
        let apparence = UINavigationBarAppearance()
        // Fond transparent : on laisse voir le fond coloré de l'app derrière.
        apparence.configureWithTransparentBackground()
        // Titres en couleur système (label = noir en Clair, blanc en Sombre).
        apparence.titleTextAttributes = [.foregroundColor: UIColor.label]
        apparence.largeTitleTextAttributes = [.foregroundColor: UIColor.label]

        // On applique aux trois états de la barre pour couvrir tous les cas.
        UINavigationBar.appearance().standardAppearance = apparence
        UINavigationBar.appearance().scrollEdgeAppearance = apparence
        UINavigationBar.appearance().compactAppearance = apparence
    }
}

extension View {
    /// Garde la barre de navigation transparente, titres en couleur système.
    func apparenceTitresNavigation() -> some View {
        modifier(ApparenceTitresNavigation())
    }
}
#endif

#if os(macOS)
/// Désactive la surbrillance de sélection **système** (le bleu) sur le
/// `NSOutlineView` de la sidebar, pour que la teinte marron peinte par
/// `.listRowBackground` soit seule visible.
///
/// Nécessaire parce que `.tint()` sur une `List` en style sidebar n'a aucun
/// effet sur cette surbrillance (essayé, sans résultat).
struct DesactiveSurbrillanceSidebar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Différé : au moment de la mise à jour SwiftUI, la vue n'est pas
        // forcément encore rattachée à sa fenêtre.
        DispatchQueue.main.async {
            guard let outline = Self.outlineViewProche(de: nsView) else { return }
            if outline.selectionHighlightStyle != .none {
                outline.selectionHighlightStyle = .none
            }
        }
    }

    /// Cherche l'`NSOutlineView` de la sidebar **de proche en proche**, en
    /// remontant depuis la vue du représentable — posée en `.background` de la
    /// `List`, donc juste à côté d'elle.
    ///
    /// **Ne PAS repartir de la racine de la fenêtre.** Le `Table` du panneau
    /// de contenu peut lui aussi être adossé à un `NSOutlineView` : la
    /// recherche depuis la racine tombait alors sur LUI, et c'est la sélection
    /// de la LISTE qui devenait invisible, la sidebar gardant son bleu.
    private static func outlineViewProche(de vue: NSView) -> NSOutlineView? {
        var courant: NSView? = vue.superview
        while let ancetre = courant {
            if let o = outlineView(dans: ancetre) { return o }
            courant = ancetre.superview
        }
        return nil
    }

    private static func outlineView(dans vue: NSView) -> NSOutlineView? {
        if let o = vue as? NSOutlineView, estLaSidebar(o) { return o }
        for sous in vue.subviews {
            if let o = outlineView(dans: sous) { return o }
        }
        return nil
    }

    /// Distingue la barre latérale du `Table` du panneau, qui peut être adossé
    /// à un `NSOutlineView` lui aussi.
    ///
    /// **Critère : le nombre de COLONNES.** La sidebar n'en a qu'une ; les
    /// tableaux du panneau en comptent huit à treize. Se fier à la classe
    /// seule faisait poser `selectionHighlightStyle = .none` sur le tableau du
    /// contenu — sa sélection passait au gris, et le réglage y RESTAIT : depuis
    /// le retrait du `.id(cat)`, la vue n'est plus recréée en changeant de
    /// rubrique, donc le même tableau sert partout.
    private static func estLaSidebar(_ o: NSOutlineView) -> Bool {
        o.numberOfColumns <= 1
    }
}
#endif
