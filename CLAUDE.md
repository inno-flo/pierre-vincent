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

- **L'app a un seul thème : crème.** Il n'y a plus de sélecteur de thème —
  les deux pastilles (crème, gris) en bas de la sidebar ont été supprimées,
  sur les deux plateformes.
- Thèmes définis dans `Couleurs.swift`. Historiquement 5 thèmes ; **marron
  puis bleu ont été supprimés**. Restent dans le code : crème (le seul actif)
  + gris et vert, dont les valeurs sont conservées mais que **rien n'active**.
- Conséquence importante : le thème ne change plus à l'exécution, donc
  `ContentView` **n'a plus de `.id(themeApp)`**. Ce modificateur recréait
  toute la hiérarchie pour relire les couleurs, ce qui remettait à zéro
  l'état `@FocusState` — d'où la sélection de la liste qui repassait en bleu
  et la navigation clavier qui se « réparait » au changement de thème.
  Ne pas le réintroduire : si un jour le thème redevient variable, faire
  observer `themeApp` aux vues concernées plutôt que de nuker la hiérarchie.
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
- **Navigation clavier ↑↓ entre sidebar et panneau de contenu (macOS) —
  piège majeur, ~10 correctifs successifs avant d'en sortir.** Ni le focus
  SwiftUI (`@FocusState`, `.focusable()`, `.onKeyPress`) ni le premier
  répondant AppKit ne sont fiables dans ce `NavigationSplitView` :
  - `.onKeyPress(.upArrow/.downArrow)` sur un ancêtre d'un `Table` ou de la
    `List` de la sidebar fait capter la touche par SwiftUI **avant** AppKit,
    mais sans la traiter si la vue n'a pas le focus SwiftUI → **bip système**,
    et la vue AppKit ne devient jamais premier répondant ;
  - le repli inverse (tout laisser au natif) échoue aussi : le comportement
    observé était **inversé** — au lancement la sidebar paraissait focalisée
    mais les flèches pilotaient le panneau central ; après un clic au centre,
    elles pilotaient la sidebar ;
  - forcer `makeFirstResponder` sur l'outline view, rendre `.focusable()`
    conditionnel, reprendre le focus dans `.onAppear` : tout cela déplace le
    symptôme sans le supprimer.
  **Solution retenue, à ne pas défaire** : un état explicite `ZoneClavier`
  (`CaptureEspace.swift`) dit quelle zone reçoit les flèches — `sidebar` ou
  `contenu` — et c'est **le geste de l'utilisateur** qui le fixe (choisir une
  rubrique → `sidebar` ; sélectionner une œuvre → `contenu`). Deux capteurs
  `CaptureFleches` (moniteurs `NSEvent` au niveau fenêtre, même patron que
  `CaptureEspace`) écoutent ↑↓ ; chacun n'agit que dans sa zone et
  **consomme** l'événement (`return nil`), ce qui supprime le bip et empêche
  un scroll view de défiler à la place de naviguer. Ils se désactivent
  pendant une saisie de texte et quand l'éditeur est ouvert.
  **Leçon générale** : sur ce projet, le seul mécanisme clavier fiable est le
  moniteur `NSEvent` local avec un état applicatif explicite. Ne pas essayer
  de déduire « qui a le focus » — le décider.
- **`ScrollViewReader` + `proxy.scrollTo(id, anchor: .center)` autour d'un
  `Table`** : l'ancre est un `UnitPoint`, donc le recentrage s'applique aux
  **deux axes**. Le défilement horizontal parasite décalait tout le tableau
  vers la gauche à chaque changement de sélection (la colonne Photo passait
  sous la sidebar), **uniquement en fenêtre étroite** — en fenêtre large,
  toutes les colonnes tiennent, il n'y a rien à faire défiler
  horizontalement et le bug est invisible. Pour ne défiler que
  verticalement, passer par AppKit : `NSTableView.scrollRowToVisible(_:)`
  (helper `DefilementTableau` dans `VueFeuille.swift`). Attention en
  cherchant le `NSTableView` dans la hiérarchie : la sidebar est un
  `NSOutlineView`, qui **hérite** de `NSTableView` et serait trouvé en
  premier — l'exclure explicitement.
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
  sous-rubrique (Inventaire, Tableaux, Dessins, Tapis, Œuvres données,
  Ventes) affiche une pastille arrondie (fond orange, texte blanc) avec le
  nombre d'œuvres correspondant (Inventaire = total de `toutes`).
  Implémenté via `HStack` + `Spacer()` dans la fonction `lien()`, calculé
  par `compteurPourCategorie(_ cat:)`.
- **macOS — sidebar, typographie** (`ContentView.swift`) : tailles relevées
  sur le système (via `NSFont`, valeurs qui font autorité — les pages HIG
  sont rendues en JavaScript et inexploitables par extraction) :

  | Rôle | Constante | Taille |
  |---|---|---|
  | Libellé de rubrique | `NSFont.systemFontSize` / body | **13 pt** |
  | En-tête de section | `NSFont.smallSystemFontSize` / subheadline | **11 pt** |
  | headline | — | 13 pt, semi-gras (poids 0,40) |
  | footnote / caption | — | 10 pt |

  Règle : **l'en-tête de section doit être plus PETIT que les libellés qu'il
  regroupe** (11 < 13). Le code imposait 14 pt aux en-têtes, donc plus gros
  que les libellés — hiérarchie visuelle inversée par rapport à Mail.
  - *En-têtes* : **ne pas imposer de police**. `listStyle(.sidebar)` fournit
    lui-même l'apparence standard (petit corps, gris). Seule la graisse est
    pilotée, par le bouton « G » (`.fontWeight(intitulesEnGras ? .bold : nil)`).
  - *Libellés* : `.font(.system(size: 13))`, en noir **gras** quand la
    rubrique est sélectionnée (`.fontWeight`), sinon `Color.textePrincipal`.
- **macOS — sidebar, couleur de sélection** (`ContentView.swift`,
  `Couleurs.swift`) : marron clair `Color.fondSelectionSidebarMac`
  (209, 187, 167 en mode clair) au lieu du bleu système.
  **`.tint()` n'a aucun effet** sur la surbrillance d'une `List` en style
  sidebar (essayé, sans résultat). La méthode qui marche : désactiver la
  surbrillance système avec `selectionHighlightStyle = .none` sur le
  `NSOutlineView` (helper `DesactiveSurbrillanceSidebar`), puis peindre le
  fond soi-même via `.listRowBackground` (rectangle arrondi, rayon 6,
  marges latérales 4 px). La valeur du mode sombre reste à ajuster.
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
  - *↑↓ sidebar et liste* : pilotées par l'état explicite `ZoneClavier` +
    les capteurs `CaptureFleches` (voir le piège détaillé plus haut, à lire
    avant toute modification du clavier). `naviguerSidebar` dans
    `ContentView.swift`, `naviguerListe` dans `VueFeuille.swift` ; les deux
    entrent par le haut/bas de la liste si rien n'est sélectionné.
  - *Liste* : défilement vers la ligne sélectionnée géré par le helper
    `DefilementTableau` (AppKit `scrollRowToVisible`), et **surtout pas**
    par un `ScrollViewReader` (voir pièges).
  - *Sidebar* : → déplace le focus vers le panneau de contenu via
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
