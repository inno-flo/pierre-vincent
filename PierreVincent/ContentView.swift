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
        // singulier (« Exposition »). « Vente privée » suit le même principe
        // — libellé affiché DISSOCIÉ de la valeur stockée — mais pour un
        // renommage complet plutôt qu'un pluriel : « Directe ». Le champ
        // `modeVente` des œuvres, `modesDeVenteReference` et tout ce qui
        // compare sur cette valeur restent inchangés, sans quoi les œuvres
        // existantes cesseraient d'être reconnues comme relevant de ce mode.
        // Un mode inédit garde son libellé tel quel, faute de correspondance
        // connue.
        case .modeVente(let m):
            switch m.lowercased() {
            case "exposition":         return "Expositions"
            case "vente aux enchères": return "Ventes aux enchères"
            case "vente privée":       return "Directe"
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
        // Contour, comme les autres icônes de sidebar (`star.fill` essayé,
        // moins cohérent avec le reste du style).
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
        // Vue AGRÉGÉE, comme Œuvres et Ventes : un favori peut venir de
        // N'IMPORTE QUELLE feuille (vendu, donné, encore en réserve). C'était
        // `.reserve` par provision avant que `favori` existe ; voir
        // `favoriSeul`, qui fait maintenant le tri.
        case .favoris:          return nil
        // Même feuille que le reste de la Réserve : c'est le THÈME qui
        // restreint, pas la feuille.
        case .reserveTheme:     return .reserve
        case .synthese:         return nil
        // Vue agrégée, comme Ventes : le filtre porte sur le mode, pas la feuille.
        case .modeVente:        return nil
        }
    }

    /// Feuille visée par le bouton « Ajouter », ou `nil` = pas de bouton du
    /// tout. **Distincte de `feuille`** : le Catalogue de « Ventes et dons »
    /// n'a PAS de feuille propre (vue agrégée des quatre), mais gagne un
    /// bouton créant dans « Tableaux vendus » — le même repli que celui du
    /// modèle (`Oeuvre.feuilleBrute` vaut ce même défaut). À l'inverse, les
    /// rubriques déjà filtrées par TYPE ou par THÈME n'en ont plus : créer
    /// une œuvre y suppose de choisir un type ou un thème que le bouton ne
    /// demande pas, et l'entrée serait alors invisible juste après création.
    var feuilleAjout: Feuille? {
        switch self {
        case .oeuvres:
            return .tableauxVendus
        case .tableauxVendus, .dessinsVendus, .tapisVendus,
             .reserveDessins, .reserveTableaux, .reserveCollection:
            return nil
        case .reserveTheme:
            return nil
        // Vue agrégée sans feuille propre : créer une œuvre n'aurait aucune
        // feuille cible unique où l'insérer.
        case .favoris:
            return nil
        default:
            return feuille
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
        // Sans effet réel : `favoriSeul` fait court-circuiter ce test dans
        // `correspond` — un favori peut avoir n'importe quel statut. La
        // valeur ici ne sert qu'à satisfaire le type de la propriété.
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

    /// Vrai pour la seule rubrique Favoris. Voir `correspond(favoriSeul:)` :
    /// aucun test de statut, de feuille ni de type ne s'applique alors —
    /// seul `o.favori` décide.
    var favoriSeul: Bool { self == .favoris }

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
        case .reserveInventaire, .reserveCollection:
            return ["tableau", "dessin"]
        // Favoris peut contenir n'importe quel type, tapis compris : les
        // trois pastilles, comme Catalogue/Ventes/Dons.
        case .favoris:
            return motsTypesFiltrables
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
    /// Essai — macOS : pastilles de type dans la TOOLBAR plutôt que dans le
    /// bandeau (`bandeauFiltres`, `VueFeuille.swift`), qui reste posé mais
    /// n'est plus affiché pour cette rubrique. Le bandeau utilise un fond
    /// translucide qui ne s'accorde pas toujours avec la toolbar native
    /// (bug signalé : deux tons visibles, Inspecteur ouvert) ; les pastilles
    /// dans la toolbar elle-même héritent directement de son rendu, sans
    /// recalculer le leur.
    ///
    /// **Restreint au SEUL Catalogue de « Ventes et dons » pour l'instant** —
    /// à la demande explicite, le temps de juger le résultat avant de
    /// l'étendre à d'autres rubriques. Vrai uniquement pour `.oeuvres` :
    /// c'est la seule à n'avoir QUE des pastilles de type (jamais de
    /// vendeur), ce qui simplifie ce premier essai.
    var pastillesTypeDansToolbar: Bool { self == .oeuvres }

    /// Vrai pour toute rubrique du premier grand bloc de la sidebar,
    /// « Ventes et dons » — Catalogue, Ventes, Dons, Synthèse et les
    /// sous-catégories par mode de vente. Faux pour la Réserve et pour
    /// Favoris, rubrique isolée hors des deux sections.
    ///
    /// Sert à `afficherPastillesVentesEtDons` (`TriEtTotaux.swift`), essai
    /// qui désactive les pastilles de filtre et le compteur associé dans
    /// TOUTE cette section d'un seul coup.
    var estSectionVentesEtDons: Bool {
        switch self {
        case .oeuvres, .tableauxVendus, .dessinsVendus, .tapisVendus,
             .oeuvresDonnees, .ventesRealisees, .modeVente, .synthese:
            return true
        default:
            return false
        }
    }

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
             .reserveTheme, .reserveCollection: return .bleuArdoise
        case .favoris:              return .taupeChaud
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
    // `vendeurDonsRenseigne` : « Florian » comme Vendeur sur tous les dons.
    @AppStorage("vendeurDonsRenseigne") private var vendeurDonsRenseigne = false
    // Ouverture/fermeture des blocs de la sidebar. **`@State`, et non
    // `@AppStorage`** : essayé en `@AppStorage` d'abord, avec une réécriture
    // au lancement (`PierreVincentApp.arrangerSidebar()`, depuis supprimée)
    // pour retrouver les mêmes valeurs à chaque démarrage — les replis faits
    // à la main ne valaient déjà que pour la session, l'écriture dans
    // `UserDefaults` ne servait donc à rien au-delà de CETTE session.
    // **Et elle avait un coût réel** : une mutation `@AppStorage` passe par
    // `UserDefaults`, dont la notification de changement n'arrive pas
    // toujours DANS la même transaction qu'un `withAnimation` — l'ouverture
    // et la fermeture des blocs se faisaient alors sans transition, un
    // « on/off » sec au lieu de l'animation native de `DisclosureGroup`.
    // Un `@State` s'anime, lui, de façon fiable — et retombe naturellement à
    // sa valeur par défaut à chaque lancement, exactement l'effet recherché.
    #if os(macOS)
    // Incrémente uniquement lorsqu'une rubrique est choisie : le relais
    // AppKit de la sidebar ne doit pas reprendre le focus lors d'une simple
    // mise à jour du contenu central.
    @State private var demandeFocusSidebar = 0
    #endif
    @State private var blocVentesOuvert = true
    @State private var blocStockOuvert = true
    @State private var sousBlocCategoriesOuvert = false
    @State private var sousBlocModesVenteOuvert = false
    @State private var sousBlocReserveCategoriesOuvert = false
    @State private var sousBlocReserveThemesOuvert = false
    #if os(iOS)
    // Import de la base sur iPhone (depuis un fichier .pvbase via Fichiers).
    @State private var importerBaseOuvert = false
    @State private var messageImportBase: String?
    #endif

    var body: some View {
        NavigationSplitView {
            // --- Barre latérale ---
            VStack(spacing: 0) {
                List(selection: $categorie) {
                    #if os(macOS)
                    // `Section(isExpanded:)` : mécanisme standard des sidebars
                    // macOS (le triangle d'affichage de Finder ou Mail).
                    //
                    // En-têtes SANS police ni graisse imposées : le style
                    // standard Apple d'un en-tête de sidebar (petit corps,
                    // gris, graisse normale) vient de `listStyle(.sidebar)`
                    // lui-même. `.foregroundStyle(.secondary)` doit rester
                    // posé explicitement : le `.foregroundStyle(Color
                    // .textePrincipal)` appliqué à toute la hiérarchie de
                    // `ContentView` écraserait sinon ce gris.
                    Section(isExpanded: $blocVentesOuvert) {
                        contenuVentesEtDons
                    } header: {
                        Text("Ventes et dons").foregroundStyle(.secondary)
                    }
                    Section(isExpanded: $blocStockOuvert) {
                        contenuStock
                    } header: {
                        Text("Réserve").foregroundStyle(.secondary)
                    }
                    // Rubrique ISOLÉE : une section sans en-tête et sans
                    // repli, détachée des deux blocs. Elle ne relève ni des
                    // ventes ni de la réserve — un favori peut venir de l'une
                    // comme de l'autre. Absente s'il n'existe encore aucun
                    // favori.
                    if auMoinsUnFavori {
                        Section {
                            lien(.favoris)
                        }
                    }
                    #endif
                    #if os(iOS)
                    // Sur iOS, `Section(isExpanded:)` n'est honoré qu'avec
                    // `listStyle(.sidebar)` : en `.insetGrouped`, le paramètre
                    // est ignoré et la section n'est pas repliable.
                    //
                    // **DEUXIÈME ESSAI** de sortir l'en-tête de sa carte, une
                    // fois `blocVentesOuvert`/`blocStockOuvert` passés en
                    // `@State` (voir leur déclaration) : le premier essai
                    // combinait DEUX causes possibles de la transition « on/
                    // off » — l'état en `@AppStorage`, ET un `if` brut plutôt
                    // que `DisclosureGroup`. La première est corrigée ; celui-
                    // ci teste si la seconde suffisait à elle seule à casser
                    // l'animation, ou si elle n'y était pour rien.
                    Section {
                        if blocVentesOuvert {
                            contenuVentesEtDons
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    } header: {
                        boutonEnTeteBloc("Ventes et dons", ouvert: $blocVentesOuvert)
                    }
                    Section {
                        if blocStockOuvert {
                            contenuStock
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    } header: {
                        boutonEnTeteBloc("Réserve", ouvert: $blocStockOuvert)
                    }
                    // Rubrique ISOLÉE, détachée des deux blocs : elle ne
                    // relève ni des ventes ni de la réserve, un favori pouvant
                    // venir de l'une comme de l'autre. Pas de repliement non
                    // plus — elle n'a qu'une ligne. Absente s'il n'existe
                    // encore aucun favori.
                    if auMoinsUnFavori {
                        Section {
                            lien(.favoris)
                        }
                    }
                    #endif
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                // `.scrollContentBackground(.hidden)` + fond peint à la
                // main : repeint la PAGE de la liste en crème, sans toucher
                // aux blocs (`secondarySystemGroupedBackground`, blancs, non
                // concernés — cet override ne vise que le fond de la vue).
                //
                // **Un override identique avait été retiré ici** à une
                // époque où `cremeFond` valait `systemBackground`, donc
                // BLANC : repeindre avec alignait la page sur la couleur des
                // blocs, et toute la sidebar devenait uniformément blanche.
                // Depuis, `cremeFond` a sa propre valeur crème fixe sur iOS
                // (voir sa définition), distincte du blanc des blocs — cette
                // condition dangereuse n'est plus réunie, l'override peut
                // revenir en toute sécurité.
                .scrollContentBackground(.hidden)
                .background(Color.cremeFond)
            #else
                .listStyle(.sidebar)
                // La sélection native devient grise lorsque le contenu
                // central est le premier répondant. Ce relais rend à la
                // sidebar son statut actif après un choix de rubrique, sans
                // imposer de couleur personnalisée.
                .background(ActiveSidebarSelection(demande: demandeFocusSidebar))
                // La couleur de sélection reste entièrement gérée par macOS.
                // Le relais ActiveSidebarSelection veille seulement à ce que
                // la sidebar soit active au moment du choix d'une rubrique.
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
                    if nouvelle != nil {
                        ZoneClavier.definir(ZoneClavier.sidebar)
                        demandeFocusSidebar += 1
                    }
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
            // Fond de la colonne, hors de la liste : le MÊME que celui d'une
            // liste groupée, sans quoi la zone du bas trancherait sur elle.
            // `cremeFond` EST ce fond groupé sur iOS (voir `Couleurs.swift`).
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
                               feuilleAjout: cat.feuilleAjout,
                               lectureSeule: cat.lectureSeule,
                               titre: cat.titre,
                               modesVente: cat.modesVente,
                               statuts: cat.statuts,
                               types: cat.types,
                               themes: cat.themes,
                               collectionSeule: cat.collectionSeule,
                               favoriSeul: cat.favoriSeul,
                               filtreParVendeur: cat.filtreParVendeur,
                               typesFiltre: cat.typesFiltre,
                               symboleFiltreTous: cat.symboleFiltreTous,
                               nomEnGalerie: cat.nomEnGalerie,
                               visionneuseIntegree: cat.visionneuseIntegree,
                               pastillesTypeDansToolbar: cat.pastillesTypeDansToolbar,
                               estSectionVentesEtDons: cat.estSectionVentesEtDons,
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
                        // de mode de vente : la même ligne s'applique aux
                        // trois, chacune recevant les pastilles que dit
                        // `Categorie.typesFiltre` — trois pour Ventes et
                        // Vente privée (affichée « Directe »), deux pour
                        // Exposition.
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
                               statuts: cat.statuts,
                               types: cat.types,
                               themes: cat.themes,
                               collectionSeule: cat.collectionSeule,
                               favoriSeul: cat.favoriSeul,
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

            // Reprise ponctuelle : « Florian » comme Vendeur sur tous les
            // dons — le champ vient d'être ajouté à l'affichage de cette
            // feuille. Voir `renseignerVendeurDons`.
            if !vendeurDonsRenseigne {
                RepriseDonnees.renseignerVendeurDons(context: context)
                vendeurDonsRenseigne = true
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

    /// Vrai dès qu'au moins une œuvre est marquée favorite, tous statuts et
    /// toutes feuilles confondus. Gouverne l'affichage de la rubrique
    /// « Favoris » dans la sidebar : une rubrique vide n'apprend rien et
    /// n'a rien à montrer, sur les deux plateformes. Partagé (pas de
    /// `#if os`) : utilisé aussi bien par `categoriesSidebar` (macOS) que
    /// par les deux `Section` de la sidebar (macOS ET iOS).
    private var auMoinsUnFavori: Bool {
        toutes.contains { $0.favori }
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
            // MÊME ORDRE qu'à l'écran, sans quoi ↑↓ sauterait de rubrique en
            // rubrique dans un ordre qui ne correspond à rien de visible :
            // Catalogue, Supports, Ventes, Modes de vente, Dons, Synthèse.
            liste.append(.oeuvres)
            if afficherSupportsSidebar && sousBlocCategoriesOuvert {
                liste += [.tableauxVendus, .dessinsVendus, .tapisVendus]
            }
            liste.append(.ventesRealisees)
            if sousBlocModesVenteOuvert {
                liste += modesDeVentePresents.map { Categorie.modeVente($0) }
            }
            liste.append(.oeuvresDonnees)
            liste.append(.synthese)
        }
        if blocStockOuvert {
            liste.append(.reserveInventaire)
            liste.append(.reserveCollection)
            // MÊME ORDRE qu'à l'écran, sans quoi ↑↓ sauterait de rubrique en
            // rubrique dans un ordre qui ne correspond à rien de visible.
            if afficherSupportsSidebar && sousBlocReserveCategoriesOuvert {
                liste.append(.reserveTableaux)
                liste.append(.reserveDessins)
            }
            if sousBlocReserveThemesOuvert {
                liste += themesPresents.map { Categorie.reserveTheme($0) }
            }
        }
        // Hors des deux blocs, et donc jamais dépendante d'un repli — mais
        // absente s'il n'existe encore aucun favori, voir `auMoinsUnFavori`.
        if auMoinsUnFavori {
            liste.append(.favoris)
        }
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
                                 collectionSeule: cat.collectionSeule,
                                 favoriSeul: cat.favoriSeul)
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
                // L'import fait désormais son gros travail — décodage JSON,
                // base64 et écriture des images — hors du fil principal, qui
                // ne garde que les mutations SwiftData. Le `Task` suffit donc :
                // le report d'un tour de boucle (`DispatchQueue.main.async`)
                // n'a plus lieu d'être, la pastille se peint pendant l'attente.
                PastilleImportBase.shared.afficher()
                Task { @MainActor in
                    let r = await EchangeBase.importerEnRemplacant(donnees: donnees,
                                                                   context: context)
                    PastilleImportBase.shared.masquer()
                    if let err = r.erreur {
                        messageImportBase = "Échec : \(err)"
                    } else {
                        messageImportBase = "\(r.importees) œuvre(s) importée(s)."
                    }
                }
            } catch {
                messageImportBase = "Impossible de lire le fichier : \(error.localizedDescription)"
            }
        }
    }
    #endif

    // MARK: Contenu des deux grands blocs de la sidebar
    //
    // Trois niveaux de hiérarchie, marqués par la seule INDENTATION native de
    // la liste — plus par la graisse. Les en-têtes (grand intitulé ET
    // sous-groupe) partagent désormais le même style gris sans gras, celui
    // qu'un en-tête de sidebar a nativement ; les sous-groupes étaient en
    // semi-gras, donc plus voyants que le grand intitulé qu'ils surplombent
    // depuis que celui-ci a perdu sa graisse — hiérarchie inversée, corrigée.
    //   1. grand intitulé   gris, sans gras (Ventes et dons, Réserve)
    //   2. sous-groupe      gris, sans gras (Catégories, Modes de vente…)
    //   3. libellé          corps normal, en couleur (Tableaux, Dessins…)

    #if os(iOS)
    /// En-tête d'un grand bloc de la sidebar, posé dans le `header:` d'une
    /// `Section` — la vraie zone d'en-tête, rendue par le système EN DEHORS
    /// de la carte groupée, contrairement à un `DisclosureGroup` posé en
    /// contenu, qui reste DANS le bloc.
    ///
    /// Le bouton fait à la main ce que `DisclosureGroup` offrait : basculer
    /// `ouvert` avec une petite flèche qui pivote. Style identique à macOS :
    /// aucune police ni graisse imposée, `.foregroundStyle(.secondary)`
    /// explicite.
    private func boutonEnTeteBloc(_ titre: String, ouvert: Binding<Bool>) -> some View {
        Button {
            withAnimation { ouvert.wrappedValue.toggle() }
        } label: {
            HStack {
                Text(titre)
                Spacer()
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(ouvert.wrappedValue ? 90 : 0))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
    #endif

    @ViewBuilder
    private var contenuVentesEtDons: some View {
        // Ordre d'affichage : Catalogue, Supports, Ventes, Modes de vente,
        // Dons, Synthèse. Les deux sous-groupes repliables (Supports, Modes
        // de vente) s'intercalent donc entre les rubriques de premier niveau
        // au lieu d'être regroupés à la fin.
        lien(.oeuvres)
        // Sous-groupe repliable des catégories d'œuvres, ex-« Catégories ».
        // `DisclosureGroup` et non `Section` : une `List` n'accepte pas de
        // Section dans une Section.
        //
        // Essai : masqué, voir `afficherSupportsSidebar`.
        if afficherSupportsSidebar {
            DisclosureGroup(isExpanded: $sousBlocCategoriesOuvert) {
                lien(.tableauxVendus)
                lien(.dessinsVendus)
                lien(.tapisVendus)
            } label: {
                Text("Supports").foregroundStyle(.secondary)
            }
        }
        lien(.ventesRealisees)
        // Sous-groupe des modes de vente, construit d'après les données.
        DisclosureGroup(isExpanded: $sousBlocModesVenteOuvert) {
            ForEach(modesDeVentePresents, id: \.self) { mode in
                lien(.modeVente(mode))
            }
        } label: {
            Text("Modes de vente").foregroundStyle(.secondary)
        }
        lien(.oeuvresDonnees)
        lien(.synthese)
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
        //
        // Essai : masqué, voir `afficherSupportsSidebar`.
        if afficherSupportsSidebar {
            DisclosureGroup(isExpanded: $sousBlocReserveCategoriesOuvert) {
                lien(.reserveTableaux)
                lien(.reserveDessins)
            } label: {
                // Ex-« Catégories ».
                Text("Supports").foregroundStyle(.secondary)
            }
        }
        // Sous-groupe des thèmes, construit d'après les données.
        DisclosureGroup(isExpanded: $sousBlocReserveThemesOuvert) {
            ForEach(themesPresents, id: \.self) { theme in
                lien(.reserveTheme(theme))
            }
        } label: {
            // Ex-« Thèmes ». Le champ sous-jacent (`theme`, `themesPresents`)
            // garde son nom — seul CE libellé de sidebar est renommé.
            Text("Genres").foregroundStyle(.secondary)
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
            // Une œuvre peut porter PLUSIEURS thèmes (voir `themesDeOeuvre`) :
            // chacun obtient sa propre sous-rubrique, pas seulement le premier.
            for brut in themesDeOeuvre(o) {
                let cle = brut.lowercased()
                guard brut.caseInsensitiveCompare(valeurInconnue) != .orderedSame,
                      vus[cle] == nil else { continue }
                vus[cle] = brut
            }
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
                    // Favoris garde SA teinte même sélectionnée, là où les
                    // autres rubriques passent au blanc de la sélection : sa
                    // couleur propre est ce qui la signale comme rubrique
                    // isolée. `cat.accent` et non la couleur en dur — la
                    // teinte se change alors à un seul endroit.
                    .foregroundStyle(cat == .favoris ? cat.accent : categorie == cat
                                     ? Color.texteSelectionSidebarMac
                                     : cat.accent)
                // Rubrique sélectionnée : libellé blanc et gras, conformément
                // au contraste de la sélection native affichée par macOS.
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
                        // ESSAI VISUEL, aux DEUX sections : 13 pt, à égalité
                        // avec le libellé qu'il accompagne — et non plus
                        // au-dessus (15 pt) ni en dessous (11 pt, la valeur
                        // d'origine).
                        .font(.system(size: 13))
                        .fontWeight(categorie == cat ? .bold : .regular)
                        .foregroundStyle(categorie == cat ? Color.white : Color.textePrincipal)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            // ESSAI VISUEL, désormais harmonisé aux DEUX
                            // sections : le chiffre reste nu au repos, sans
                            // contour. Le fond plein de la rubrique
                            // sélectionnée, lui, est conservé partout.
                            if categorie == cat {
                                Capsule().fill(cat.accent)
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
                        // ESSAI VISUEL, aux DEUX sections : `.subheadline`
                        // vaut 15 pt à la taille de texte « Large », pendant
                        // iOS des 15 pt fixés sur macOS. Style sémantique et
                        // non une taille en points : figer 15 casserait le
                        // Dynamic Type.
                        .font(.subheadline)
                        .fontWeight(categorie == cat ? .bold : .regular)
                        .foregroundStyle(categorie == cat ? Color.white : Color.textePrincipal)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            // ESSAI VISUEL, désormais harmonisé aux DEUX
                            // sections : le chiffre reste nu au repos, sans
                            // contour. Le fond plein de la rubrique
                            // sélectionnée, lui, est conservé partout.
                            if categorie == cat {
                                Capsule().fill(cat.accent)
                            }
                        }
                }
            }
            #endif
        }
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
/// Rend le `NSOutlineView` de la sidebar premier répondant après une nouvelle
/// sélection. Sans cela, le tableau central peut conserver le statut actif et
/// macOS affiche la sélection de la sidebar en gris, qui est sa teinte native
/// pour une sélection inactive.
private struct ActiveSidebarSelection: NSViewRepresentable {
    let demande: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard context.coordinator.derniereDemande != demande else { return }
        context.coordinator.derniereDemande = demande

        DispatchQueue.main.async {
            guard let outline = Self.outlineViewProche(de: nsView),
                  let fenetre = outline.window else { return }
            outline.selectionHighlightStyle = .regular
            fenetre.makeFirstResponder(outline)
        }
    }

    final class Coordinator {
        var derniereDemande = -1
    }

    private static func outlineViewProche(de vue: NSView) -> NSOutlineView? {
        var courant: NSView? = vue.superview
        while let ancetre = courant {
            if let outline = outlineView(dans: ancetre) { return outline }
            courant = ancetre.superview
        }
        return nil
    }

    private static func outlineView(dans vue: NSView) -> NSOutlineView? {
        if let outline = vue as? NSOutlineView, outline.numberOfColumns <= 1 {
            return outline
        }
        for sousVue in vue.subviews {
            if let outline = outlineView(dans: sousVue) { return outline }
        }
        return nil
    }
}

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
