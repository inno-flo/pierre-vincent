# Pierre-Vincent — Contexte du projet

## Vue d'ensemble

Application native **macOS et iOS** d'inventaire des œuvres d'un artiste (le père de
l'utilisateur) : tableaux, dessins et tapis **vendus**, et œuvres **données**.
L'app gère des images, du texte et des montants en euros, et propose plusieurs vues
(Galerie, Synthèse, Détails, éditeur/inspecteur latéral).

- **Frameworks** : SwiftUI + SwiftData. 100 % technologies Apple, aucune dépendance
  multiplateforme non-Apple. L'app n'a pas vocation à sortir de l'écosystème Apple.
- **Outils** : Xcode 26, cibles iOS 26+ / macOS 26+.
- **Langue de travail** : **français** (commentaires de code, échanges, libellés d'UI).
- **Dépendance externe** : XLKit (export .xlsx avec images incrustées).

## Profil de l'utilisateur (important)

- **Développeur débutant et autodidacte.** Première application. Explications
  accessibles bienvenues, sans jargon inutile.
- **Dispose d'un compte GitHub** qui sert de dépôt pour cette app. → Utiliser Git
  comme filet de sécurité : proposer un commit avant toute modification touchant
  plusieurs fichiers, et permettre de revenir en arrière facilement en cas de
  régression.
- Style de communication attendu : **direct, concret, sans formules creuses**
  (éviter « honnêtement », « pour être transparent », etc.). Faire le travail
  demandé, on verra ensuite si ça marche.

## Conventions de code

- Commenter les **étapes importantes** du code (pas chaque ligne).
- Vues complexes : pour éviter les erreurs de compilation « type-check »,
  **extraire** les blocs toolbar, alertes et raccourcis clavier dans des propriétés
  ou modificateurs séparés.
- Couleurs centralisées dans **`Couleurs.swift`** (thèmes adaptatifs clair/sombre
  construits via `UIColor`/`NSColor` dynamiques).
- La liste iOS affiche `oeuvresGalerie`, pas `oeuvres`.

## Modèle de données

- `@Model final class Oeuvre` : tous les champs possibles sont stockés sur le même
  modèle. Les feuilles de **vente** utilisent prix / vendeur / acheteur / date ;
  la feuille **données** utilise `destinataire`. Champs inutilisés = vides.
- Enum `Feuille` : `tableauxVendus`, `dessinsVendus`, `tapisVendus`, `oeuvresDonnees`.
  Le `rawValue` sert de clé d'import CSV (ex. « Œuvres données », « Dessins vendus »).
- Photos stockées **hors base**, sur disque, via `PhotoStore` (dossier « Photos »
  dans Application Support). La base ne contient que le nom de fichier.

## Thèmes de couleurs

- Thèmes définis dans `Couleurs.swift`. Historiquement 5 thèmes ; **le thème marron
  a été supprimé**. Restent : crème, gris (exposés dans l'UI) + vert, bleu
  (code conservé mais **pastilles masquées** dans l'interface).
- Seules les pastilles **crème** et **gris** sont sélectionnables.
- Accent de marque : orange international `Color(red: 1.0, green: 0.31, blue: 0.0)`,
  réservé aux valeurs chiffrées.

## Import de données depuis PDF (workflow établi)

Deux imports déjà réalisés (Dons, Dessins vendus). Méthode validée :

- Extraire le **texte** des tableaux avec `pdfplumber`, les **images** avec `pypdf`.
- **Alignement photo ↔ ligne : par position verticale** (le centre de l'image doit
  tomber dans l'intervalle vertical de la ligne), PAS par simple ordre séquentiel.
  Certaines lignes n'ont pas de photo → l'ordre seul décale tout.
- Générer un dossier réimportable : `import.csv` (BOM UTF-8) + sous-dossier `Photos`
  avec images numérotées `0001.png`, `0002.png`… référencées dans le CSV.
- **Livrer en `.zip`** (le téléchargement de dossier échoue dans l'interface web).
- Colonne PDF « Acheteur » d'une feuille de don → champ `destinataire` de l'app.
- La colonne « Mode de vente » du PDF n'a pas d'équivalent dans le modèle (non importée
  sauf décision d'étendre le modèle).

## Pièges déjà rencontrés (à ne pas refaire)

- **Animation galerie** : une tentative de recalcul du nombre de colonnes via
  `GeometryReader` + `onChange(largeur)` a **dégradé** le rendu (saccades au
  redimensionnement, vignettes qui se réordonnent de façon chaotique). **Abandonnée
  et fichiers restaurés.** Ne pas réessayer sans une approche fondamentalement
  différente.
- Toute modification d'UI qui dégrade le comportement doit être **revertée
  proprement** depuis les fichiers d'origine.
- `ToolbarSpacer` n'accepte pas `spacing:` et `placement:` simultanément.
- Erreur `_main` à la compilation = un fichier a perdu son appartenance à la cible
  (Target Membership décochée dans Xcode).
- Le blocage de veille de l'iPhone pendant le débogage est **normal** (débogueur
  Xcode attaché), ce n'est pas un bug de l'app.
- **Geste personnalisé sur une ligne de `List(selection:)` contenant un
  `NavigationLink`** : même posé en `simultaneousGesture` (pas `.gesture` ni
  `.onLongPressGesture`, pires), un `DragGesture` ajouté directement sur la
  ligne entre par moments en concurrence avec le tap natif du `NavigationLink`
  et bloque la navigation de façon **aléatoire** (et fait chauffer l'appareil
  à force de réarbitrage). Deux fois rencontré et corrigé sur la sidebar iOS
  (surbrillance de section). **Ne plus attacher de geste personnalisé sur une
  ligne sélectionnable** : piloter l'état visuel via `.onChange` sur la valeur
  de sélection officielle à la place.
- **`NavigationSplitView` (iPhone, colonne « detail »)** : le binding de
  sélection ne repasse pas de façon fiable à `nil` au retour depuis la vue
  detail, et `.onDisappear` sur le contenu de cette colonne ne se déclenche
  pas non plus systématiquement à ce moment-là. Ne pas compter sur ces deux
  mécanismes pour détecter « on est revenu à la liste » — utiliser à la place
  un minuteur auto-extinctible indépendant (déclenché par la sélection elle-même,
  pas par le retour).
- **`.transition(...)` à l'intérieur d'un `ScrollView` sans `ZStack` explicite** :
  SwiftUI ne superpose pas l'ancienne et la nouvelle vue pendant l'animation,
  donc un `.move(edge:)` ne se voit pas (juste un remplacement sec). Toujours
  envelopper le contenu transitionné dans un `ZStack`.
- Le Taptic Engine de l'iPhone est un **moteur unique** : impossible de
  simuler un retour haptique « localisé » selon la zone de l'écran touchée
  (aucune spatialisation possible, contrairement à ce qu'on pourrait imaginer).
- **`onKeyPress` sur un parent de `Table` (NSTableView) ou de la sidebar
  `List` (NSOutlineView)** : SwiftUI intercepte les événements clavier
  *avant* qu'ils arrivent à la vue AppKit sous-jacente. Ajouter
  `.onKeyPress(.upArrow)` / `.onKeyPress(.downArrow)` sur un ancêtre d'un
  `Table` casse la navigation native ↑↓ de NSTableView. Règle : ne jamais
  intercepter ↑↓ sur un parent de `Table` — les laisser à NSTableView natif.
  En revanche, ←→ ne sont pas consommés par NSTableView et peuvent être
  gérés sans danger par un `onKeyPress` parent.
- **`ToolbarItem(placement: .primaryAction)` avec `.inspector(isPresented:)`
  ouvert** : les items avec ce placement s'étalent sur toute la largeur de
  fenêtre, inspecteur inclus. Pour confiner les boutons exclusivement
  au-dessus du panneau de contenu, utiliser des `ToolbarItem {}` et
  `ToolbarSpacer(.flexible/.fixed)` **sans `placement:` explicite** (pattern
  de l'exemple Landmarks d'Apple, validé sur macOS 26).

## Optimisations effectuées

- **Listes iOS en `LazyVStack`** : les listes verticales dans `ScrollView`
  (`VueiOS.liste`, `VueOeuvresStructuree.listeLignes`,
  `VueDonsStructuree.listeLignes`) utilisent `LazyVStack` et non `VStack`,
  pour ne construire que les lignes visibles à l'écran (vignette comprise)
  au lieu de tout construire d'un coup à l'ouverture. Les `LazyVGrid` de la
  galerie et de la Synthèse étaient déjà correctes ; seules ces trois listes
  verticales ne l'étaient pas avant correction.
  
- **`formaterEuros()` — formatter statique** (`TriEtTotaux.swift`) : la
  version initiale recréait un `NumberFormatter` à chaque appel (coûteux :
  chargement de données de locale). La fonction est appelée à chaque ligne
  du tableau macOS, à chaque tuile de la Synthèse, dans `PrixText`, dans
  les fiches iOS. Fix : un seul formatter statique partagé (`private let
  formatteurEuros: NumberFormatter = { … }()`) réutilisé à chaque appel.

## Icône macOS (en cours)

- Cible : format **`.icon`** via **Icon Composer** (livré avec Xcode 26), pour le
  rendu « Liquid Glass » multi-couches. L'ancien AppIcon PNG seul ne suffit pas.
- Illustration source : un kaki (persimmon), détouré sur fond transparent, 1024×1024.

## Détails d'interface déjà en place

- **macOS** : menu Fichier restructuré (sous-menu Exporter, accès au dossier des
  données), navigation Précédent/Suivant dans l'éditeur, sidebar sans bloc d'infos
  (un filet + pastilles de thème), titre de catégorie sélectionnée forcé en blanc.
- **iOS** : navigation liquid glass, swipe latéral fluide, barre de navigation
  transparente (titres en couleur système), défilement auto de la galerie.
- **Vue Synthèse** : cartes (Œuvres, Montants, Enchères) contenant des tuiles.
  Une tuile « Total des ventes » (somme euros tableaux + dessins + tapis) figure
  dans le bloc Œuvres.
- **iOS — Inventaire (sidebar), couleur de contraste sur la section choisie**
  (`ContentView.swift`) : la ligne se teinte (`Color.fondCelluleSidebarSelectionnee`,
  nouvelle couleur adaptative dans `Couleurs.swift`, distincte de l'orange de
  marque réservé aux valeurs chiffrées) au moment de la sélection, reste teintée
  0,4 s puis s'éteint **toute seule** via une tâche asynchrone — sans jamais
  dépendre d'un retour de navigation ni d'un geste personnalisé (voir pièges
  ci-dessous).
- **iOS — photo en plein écran depuis la fiche détail d'une œuvre**
  (`DetailiOS` dans `VueiOS.swift` + nouveau fichier
  `VisionneuseImagePleinEcran.swift`) : tap prolongé sur la photo (0,5 s,
  retour haptique `UIImpactFeedbackGenerator(.medium)`, comme un appui long
  sur une icône d'écran d'accueil) → ouverture en plein écran avec
  pinch-to-zoom (1x-5x), glissement pour se déplacer une fois zoomé,
  double-tap pour réinitialiser, croix en haut à droite pour fermer.
- **iOS — transition de glissement latéral entre œuvres** (`DetailiOS`,
  swipe gauche/droite ou chevrons) : le contenu de la fiche est enveloppé
  dans un `ZStack` (indispensable pour que `.transition(.move(edge:))` se
  voie réellement à l'intérieur d'un `ScrollView`), animation 0,25 s.
- **macOS — sidebar, pastilles de comptage** (`ContentView.swift`) : chaque
  sous-rubrique (Tableaux, Dessins, Tapis, Œuvres données, Ventes) affiche
  une pastille arrondie (fond orange, texte blanc) avec le nombre d'œuvres
  correspondant. Implémenté via `HStack` + `Spacer()` dans la fonction
  `lien()`, calculé par `compteurPourCategorie(_ cat:)`.
- **macOS — toolbar de la vue principale** (`VueFeuille.swift`) : tous les
  `ToolbarItem` et `ToolbarSpacer` sont sans `placement:` explicite pour
  que les boutons restent exclusivement au-dessus du panneau de contenu
  (jamais au-dessus de la colonne Inspecteur). L'icône du menu de tri
  change dynamiquement selon le critère actif (eurosign / person / ruler),
  comme sur iOS.
- **macOS — navigation clavier** (`VueGalerie.swift`, `VueFeuille.swift`,
  `ContentView.swift`) :
  - *Galerie* : après un clic, les 4 touches fléchées naviguent entre les
    vignettes (↑↓ tiennent compte du nombre de colonnes, calculé depuis la
    largeur mesurée par un `GeometryReader` en overlay — sans modifier le
    layout). La touche Entrée ouvre l'éditeur. Focus activé via
    `@FocusState` + `.focusable()` + `.focusEffectDisabled()` sur le
    `ScrollView`.
  - *Liste* : ←→ naviguent prev/next ; ↑↓ laissés à NSTableView natif
    (ne pas intercepter, voir pièges).
  - *Sidebar* : ↑↓ circulent entre les rubriques (liste ordonnée codée en
    dur), → déplace le focus vers le panneau de contenu via
    `NSApp.keyWindow?.selectNextKeyView(nil)`.
- **Filets de sélection orange : 3 px** dans toutes les vues (galerie
  macOS, listes iOS). En galerie macOS le filet non sélectionné reste à
  1 px (`lineWidth: selection.contains(o.id) ? 3 : 1`).
- **iOS — sidebar Inventaire, libellés et regroupement** (`ContentView.swift`,
  enum `Categorie`) : intitulé de page « Inventaire » supprimé (titre vide,
  grand format conservé pour ne pas décaler la mise en page) ; rubrique
  « Œuvres » renommée en **« Inventaire »**, rubrique « Dons » renommée en
  **« Œuvres données »** (`.titre` de `Categorie`, qui pilote aussi le titre
  de la fiche associée) ; les 4 rubriques Tableaux/Dessins/Tapis vendus +
  Œuvres données sont regroupées dans un même bloc, sous un en-tête de
  section **« Ventes et dons »** (3 `Section` au lieu de 4). Par cohérence,
  les titres et libellés internes de `VueOeuvresStructuree` (page + section
  « Dons » → « Œuvres données ») et `VueDonsStructuree` (titre de page
  « Dons » → « Œuvres données ») ont été alignés sur ces nouveaux noms.
  La carte « Œuvres » de la vue Synthèse (bloc statistique, concept
  différent) n'a pas été touchée.
