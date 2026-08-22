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
- Enum `Feuille` : `tableauxVendus`, `dessinsVendus`, `tapisVendus`,
  `oeuvresDonnees`, `reserve`. Le `rawValue` sert de clé d'import CSV
  (ex. « Œuvres données », « Dessins vendus »).
- **Pourquoi une feuille « Réserve ».** Les quatre premières viennent des
  onglets du tableur d'origine et disent DEUX choses à la fois : le genre
  d'objet ET son sort (« Tableaux vendus »). Aucune ne convient donc à une
  œuvre jamais sortie de l'atelier. La cinquième ne dit que le sort ; le genre
  se lit sur `type`. Les deux rubriques de la Réserve s'y rapportent, et c'est
  le **type** qui distingue Dessins du Catalogue.
- **`feuillesSansPrix` et `aUnPrix(_:)`** (`TriEtTotaux.swift`) : dons et
  réserve n'ont pas de prix à montrer. Le test se lit sur l'**ŒUVRE**, jamais
  sur la rubrique — dans les vues agrégées la feuille de la rubrique vaut
  `nil`. Quatre endroits testaient « ce n'est pas un don, donc affiche le
  prix » et auraient affiché « 0 € » sur la réserve : ils passent tous par
  cette fonction, et une future feuille sans prix s'ajoutera à un seul endroit.
- **`typesOeuvre`** (`TriEtTotaux.swift`) : Dessin, Tableau, Tapis. Le champ
  `type` ne contient QUE ces valeurs, jamais une technique — c'est sur cette
  règle que repose le filtre de Réserve › Dessins. L'éditeur propose un menu
  fermé ; une valeur hors liste s'y ajoute telle quelle, pour signaler les
  œuvres restant à corriger au lieu de les écraser en silence.
- Photos stockées **hors base**, sur disque, via `PhotoStore` (dossier « Photos »
  dans Application Support). La base ne contient que le nom de fichier.
- **Champs de suivi** ajoutés à `Oeuvre` : `statut`, `theme`, `emplacement`
  (texte, défaut vide → SwiftData fait une migration légère automatique).
  Présents dans l'éditeur, l'inspecteur, la fiche iOS, le mode Liste et tous
  les exports.
- **Le statut pilote la visibilité.** Les rubriques de « Ventes et dons »
  (Inventaire, Tableaux, Dessins, Tapis, Dons, Ventes) ne recensent que les
  œuvres **sorties du fonds** : statut « Vendu » ou « Donné ». Prédicat unique
  `estVenduOuDonne` (+ `statutsVentesEtDons`) dans `TriEtTotaux.swift`,
  appliqué aussi aux **pastilles de comptage** de la sidebar et à la vue
  **Synthèse**. Les œuvres encore disponibles — celles importées depuis des
  photos — n'apparaissent nulle part tant que la section « Réserve » n'a pas
  ses rubriques. Sans ce filtre sur la Synthèse, une œuvre disponible à 0 €
  tirerait le prix moyen vers le bas et fausserait le prix minimum.
- **Reprises de données ponctuelles** : `RepriseDonnees` (`Oeuvre.swift`),
  exécutées une fois au lancement depuis `ContentView.onAppear`. Elles ne
  remplissent que les champs **vides** (donc rejouables sans risque, et sans
  écraser de saisie). Chaque passe a son propre drapeau `@AppStorage` :
  **une passe déjà consommée ne se redéclenche pas**, il faut un nouveau
  drapeau pour toute reprise supplémentaire.
  Faites à ce jour, **dans cet ordre** : statut « Vendu » hors dons et
  « Donné » pour les dons ; mode de vente « Don » pour les dons ;
  « Inconnu » dans tous les champs texte encore vides ; puis feuille
  « Réserve » sur les œuvres encore détenues.
  **L'ordre compte** : la passe « Inconnu » ne remplit que les champs vides,
  donc toute reprise qui en dépend doit s'exécuter AVANT elle, sinon elle ne
  trouve plus rien à remplir.
  **`remplirFeuilleReserve` est l'exception** : contrairement aux autres, elle
  ÉCRASE une valeur existante — `feuille` n'est jamais vide, elle vaut
  « Tableaux vendus » par défaut. Elle reste rejouable sans danger, le seul
  statut suffisant à décider : une œuvre disponible n'a été ni vendue ni
  donnée. Elle passe après les reprises de statut, dont elle se sert.
- **Format d'échange `.pvbase`** (`EchangeBase.swift`) : tout champ ajouté au
  modèle doit y être ajouté aussi, **en optionnel**, sinon un transfert
  Mac → iPhone le perd silencieusement. Optionnel car un `Codable` synthétisé
  **n'applique pas les valeurs par défaut aux clés absentes** : un fichier
  exporté avant l'ajout deviendrait illisible.
  - **Une nouvelle VALEUR d'enum se perd tout aussi silencieusement.** La
    feuille voyage en texte et se relit avec un repli
    (`Feuille(rawValue:) ?? .tableauxVendus`) : une version qui ignore
    « Réserve » range les œuvres détenues parmi les tableaux vendus, sans le
    moindre message. **Les deux appareils doivent passer à la même version
    avant tout transfert.**
  - Filet posé à l'import : le **statut fait foi**, une œuvre disponible reçoit
    la feuille Réserve quoi qu'ait dit le fichier. Ce rattrapage ne pouvait pas
    être une passe de `RepriseDonnees` — elles tournent au lancement, donc
    AVANT l'import, et leur drapeau est déjà consommé quand le fichier arrive.
  - L'export part de `toutes`, la requête complète, et non de la rubrique
    affichée : la Réserve y est.

## Import de photos (macOS)

Moteur **séparé** du moteur CSV (`ImportPhotos.swift`), atteint par
Fichier › Importer › « Photos… ». Le CSV garde « Dossier CSV et photos… ».
Les deux n'ont aucune étape commune : entrée, source des données et traitement
diffèrent en tout.

- Une œuvre créée **par photo** choisie (sélection multiple).
- **Les mots-clés IPTC** — pas la légende — alimentent les champs. Les photos
  de test portent p. ex. « Dessin disponible » (statut), « Dessin nature
  morte » (thème), « Natures mortes carton 2 » (emplacement), « Dessin Pierre
  Innocente » (type). Certaines ont aussi une légende, d'autres non.
- Métadonnées lues **AVANT** la compression : la version stockée est
  ré-encodée et ne conserve pas l'IPTC d'origine.
- **Table de correspondance** isolée dans `CorrespondanceMotsCles`, seul point
  à compléter. Tant qu'elle est vide, nom de fichier, légende et mots-clés
  sont recopiés dans les **Remarques** : aucun import ne perd d'information.
- **Compression** (`PhotoStore.importerImageCompressee`) : réduction à
  **2000 px** de côté long, puis HEIC à qualité dégressive jusqu'à passer sous
  **450 Ko**. La boucle s'arrête au premier palier qui tient.
  - Réduire **avant** de compresser : à 450 Ko, 12 Mpx font ~0,03 bit/pixel,
    l'image serait molle.
  - `CGImageSourceCreateThumbnailAtIndex` décode directement à la taille
    voulue, sans jamais charger les 12 Mpx en mémoire.
  - **HEIC et non JPEG** : mesuré sur une photo de test, 325 Ko à qualité 0,42
    contre 344 Ko à 0,35 en JPEG. L'app étant 100 % Apple, aucun souci de
    compatibilité.
  - **Chemin rapide** : un fichier pesant déjà 450 Ko ou moins est recopié
    **tel quel, octet pour octet**. Le ré-encoder ne ferait que dégrader
    l'image sans rien gagner en poids.
  - `importerImageCompressee` sert à TOUTES les entrées : import de photos,
    glisser-déposer sur l'éditeur ou sur la cellule Photo, bouton
    « Choisir… ». L'ancienne `importerImage` ré-encodait en **PNG** — 4,3 Mo
    à partir d'une photo légère — et a été supprimée. Ne pas la réintroduire.

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
- **Pastille de comptage et vue qui divergent.** La rubrique Dessins de la
  Réserve annonçait 9 œuvres au-dessus d'une vue vide : `compteurPourCategorie`
  passait par `correspond(_:statuts:types:)`, qui teste statut et type, tandis
  que `baseRubrique` testait **en plus la feuille**. Le compteur applique
  désormais le filtre de feuille lui aussi. **Règle** : toute pastille doit
  appliquer EXACTEMENT les filtres de la vue qu'elle annonce — un écart ne se
  voit pas à la lecture du code, seulement à l'écran, et se lit comme une
  disparition d'œuvres.
- **`Table` macOS écrit à la main, pas dérivé de `SchemaFeuille`.** Les
  colonnes de `Colonnes.swift` servent aux EXPORTS ; le tableau de la vue a ses
  `TableColumn` en dur (`tableVente`, `tableDon`, `tableReserve`). Une nouvelle
  feuille demande donc les deux.
- **Vue d'image chargée dans `.onAppear` avec un garde `image == nil`** :
  une vue DÉJÀ à l'écran ne rechargeait jamais. Après remplacement d'une photo
  (éditeur ou glisser-déposer), l'ancienne vignette restait affichée jusqu'à ce
  qu'on quitte la vue et y revienne. `VignetteCachee` et
  `VignetteCacheeFlexible` utilisent désormais **`.task(id: nom)`**, qui se
  rejoue à chaque changement de nom de fichier.
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
- **Isoler le bouton Inspecteur à l'extrême droite (au-dessus de la colonne
  inspecteur), les autres boutons restant au-dessus du panneau de contenu :
  NON RÉSOLU.** Objectif visé : inspecteur fermé → tous les boutons groupés à
  droite ; inspecteur ouvert → seul le bouton Inspecteur file à l'extrême
  droite, les autres ne bougent pas. Quatre approches essayées sur une branche
  dédiée, toutes abandonnées :
  1. `ToolbarItem(placement: .primaryAction)` sur ce seul bouton → **tous** les
     items fusionnent dans le même groupe aligné à droite de la fenêtre, et le
     bouton se retrouve dans la même capsule que son voisin ;
  2. `ToolbarSpacer(.flexible, placement: .primaryAction)` juste avant lui →
     aucun effet visible ;
  3. bouton déclaré dans `ContentView`, sur le `NavigationSplitView` lui-même
     (possible sans rien remonter d'autre, `inspecteurVisible` étant en
     `@AppStorage`) → il passe en **tête** du groupe, donc tout à gauche ;
  4. `.toolbar {}` attachée au **contenu de l'inspecteur**, dans la closure de
     `.inspector` → ne s'affiche pas.
  **Deuxième campagne d'essais** (branche `inspecteur-3e-colonne`), après avoir
  remonté tout l'inspecteur dans `ContentView` — panneau extrait dans un
  `VueInspecteur` recevant les œuvres sélectionnées, sélection remontée depuis
  `VueFeuille` par binding, et `.inspector()` posé **sur le
  `NavigationSplitView` lui-même** :
  5. bouton dans `ContentView` avec `.primaryAction` → **les sections se
     séparent enfin**, mais à l'envers : le bouton Inspecteur reste au-dessus du
     panneau de contenu (et tout à gauche du groupe), tandis que les six autres
     boutons, déclarés dans `VueFeuille`, passent au-dessus de la colonne
     inspecteur ;
  6. le même sans `placement:` → identique. Le `placement:` n'a donc aucune
     influence ; ce qui semblait décider de la section, c'était le **niveau de
     déclaration** (split view → panneau de contenu ; colonne `detail:` →
     colonne inspecteur) ;
  7. inversion complète des déclarations pour exploiter cette règle : les six
     boutons remontés dans `ContentView` (avec trois signaux `@AppStorage`
     `signalAjouter` / `signalSupprimer` / `signalOuvrirEditeur` pour les
     actions touchant l'état interne de `VueFeuille`), le bouton Inspecteur
     redescendu dans `VueFeuille` → **échec** : tous les boutons se regroupent
     de nouveau ensemble. La « règle » du niveau de déclaration ne se vérifie
     donc pas une fois inversée, et n'est pas exploitable.

  **Conclusion générale, après sept essais** : ce placement n'est pas
  atteignable avec l'API publique de SwiftUI sur macOS 26. Aucun `placement:`
  ne vise la zone de toolbar de la colonne inspecteur, une `.toolbar` attachée
  au contenu de l'inspecteur ne se rend pas, et la répartition des sections
  n'obéit pas à une règle stable qu'on puisse piloter. **Ne pas relancer ces
  pistes.** La seule voie non explorée serait une toolbar `NSToolbar` gérée
  en AppKit, ou l'abandon de `.inspector()` au profit d'un panneau latéral
  maison (un `HStack` avec une vue de droite pilotée par un état), qui
  redonnerait la main sur la disposition — au prix de la perte du comportement
  natif de l'inspecteur (redimensionnement, animation, mémorisation).

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

- **Un champ non renseigné vaut « Inconnu », et ce mot est STOCKÉ EN BASE**
  (et non substitué à l'affichage, comme c'était le cas au départ). Mot isolé
  dans `valeurInconnue` (`TriEtTotaux.swift`). Douze champs texte concernés ;
  **`photoNom` est exclu**, son vide signifiant « aucune photo » et non
  « inconnu » — y écrire « Inconnu » casserait le chargement des images.
  - **L'éditeur convertit dans les DEUX SENS** (`pourSaisie` / `pourBase`) :
    « Inconnu » devient un champ vide à la lecture, un champ vide redevient
    « Inconnu » à l'enregistrement. **Ne pas retirer cette conversion** :
    sans elle il faudrait effacer le mot dans chaque champ avant de taper.
  - `afficher(_:)` reste en place dans `ligne` / `ligneInspecteur` comme
    filet de sécurité, pour une œuvre créée hors de ce circuit.
- **Les trois surfaces qui affichent une œuvre doivent proposer les mêmes
  champs, dans le même ordre** : éditeur (boîte de dialogue), inspecteur
  (colonne) et fiche iPhone. Ordre de référence : Prix · Type ·
  Dimensions/Format · Statut/Thème/Emplacement · Vendeur-Acheteur-Mode de
  vente (ou Destinataire-Mode de vente) · Date · Remarques.
- **Le caractère « don » se lit sur l'ŒUVRE (`o.feuille`), jamais sur la
  rubrique affichée.** Dans les vues agrégées (Inventaire, Ventes), la feuille
  de la rubrique vaut `nil` : l'inspecteur affichait donc Prix/Vendeur/
  Acheteur/Date pour une œuvre donnée, et la galerie « 0 € » sous sa vignette,
  alors que l'éditeur et la fiche iOS se fondaient déjà sur l'œuvre. Corrigé
  sur les quatre surfaces ; `VueGalerie` n'a plus de paramètre `estFeuilleDon`.
- **`Table` (SwiftUI, macOS) : 10 colonnes maximum** au premier niveau du
  builder. Au-delà, erreur « extra arguments at positions #11… ». Envelopper
  les colonnes excédentaires dans un `Group`, qui conforme à
  `TableColumnContent` (le tableau des ventes en compte 13).

- **macOS** : menu Fichier restructuré (sous-menu Exporter, accès au dossier des
  données), navigation Précédent/Suivant dans l'éditeur, bas de sidebar vide.
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
- **Sidebar — zone du bas, conservée en commentaire** (`ContentView.swift`,
  les deux plateformes) : le bas de la barre latérale est **vide**. Il a
  successivement porté les pastilles de choix de thème, le bouton « G »
  (mise en gras des en-têtes de section), puis la pastille de comparaison des
  deux marrons de sélection — tous retirés une fois leur question tranchée :
  les en-têtes sont en graisse normale, il n'y a plus de sélecteur de thème, et
  le marron de sélection est arrêté.
  L'emplacement est **gardé en commentaire** pour y poser au besoin des boutons
  temporaires de test : deux blocs qui se renvoient l'un à l'autre, l'appel
  dans la `VStack` de la sidebar (`Divider()` + `barreOutilsBas`) et la
  propriété `barreOutilsBas` près de `lien()`. Les réactiver demande de
  décommenter **les deux**, sinon la compilation échoue.
- **macOS — sidebar, pastilles de comptage** (`ContentView.swift`) : chaque
  rubrique affiche une pastille arrondie avec le nombre d'œuvres
  correspondant. Deux états, alignés sur le libellé qu'elles accompagnent :
  **au repos** contour orange, fond transparent, texte `textePrincipal` en
  graisse normale ; **rubrique sélectionnée** fond orange plein, texte blanc
  et gras. En mode sombre le texte est blanc dans les deux cas, sans règle
  spéciale — `textePrincipal` y vaut déjà blanc. Corps de **11 pt**, et non
  les 13 pt des pastilles du panneau : dans la sidebar, tout ce qui est
  subordonné aux libellés reste à 11. Le compte applique **les mêmes filtres que
  la vue** (statut, et type pour la Réserve) : sans quoi la pastille
  annoncerait un nombre introuvable à l'écran.
  Implémenté via `HStack` + `Spacer()` dans la fonction `lien()`, calculé
  par `compteurPourCategorie(_ cat:)`.
- **Filtre par vendeur — les DEUX plateformes.** `Categorie.filtreParVendeur`
  (booléen, adossé à `modesAvecFiltreVendeur`) dit où le filtre apparaît :
  bandeau de pastilles sur Mac, menu de barre d'outils sur iPhone. Les
  **vendeurs eux-mêmes sont déduits des données partout**.
  - L'ancienne `Categorie.filtresVendeur` nommait quatre vendeurs en dur, dont
    deux n'avaient rien vendu aux enchères : les choisir menait à une liste
    vide. Supprimée, avec `correspondAuCanal` qui testait deux champs pour ce
    menu mêlant vendeurs et modes de vente. **Ne pas les réintroduire.**
  - Conséquence voulue sur iPhone : Ventes et Vente privée n'ont plus le
    filtre et retrouvent le menu de tri standard, comme sur Mac.
  - Sur iPhone, `.modeVente` est servi par **`VueOeuvresStructuree`**, pas par
    `VueiOS` — cette dernière ne sert que les rubriques par type et la Réserve.
    Les deux vues ont leur propre menu à tenir à jour.
- **`modesSansNomEnGalerie` est une liste SÉPARÉE de `modesAvecFiltreVendeur`**,
  bien qu'elles contiennent aujourd'hui les mêmes deux valeurs. L'une décide
  d'un filtre, l'autre d'un affichage. Les fusionner ferait qu'ajouter une
  rubrique au filtre lui retirerait aussi l'acheteur de ses vignettes, sans
  que rien ne le laisse prévoir.
- **Vignettes des enchères et des expositions** : pas de ligne de nom, seuls
  le prix et les dimensions. Deux vignettes distinctes à modifier de front —
  celle de `VueGalerie` (partagée Mac/iPhone) et celle écrite sur place dans
  `VueOeuvresStructuree`.
- **Réserve : la vignette porte l'EMPLACEMENT.** La ligne de nom cherchait un
  acheteur ou un destinataire, qu'une œuvre en réserve n'a ni l'un ni l'autre,
  et restait donc vide. **Ordre : l'intitulé « Emplacement » d'abord, en gris,
  puis sa valeur** — l'inverse se lisait mal, « Natures mortes carton 2 » seul
  ne disant pas de quel champ il relève. Même chose dans la liste iPhone ; le
  mode liste macOS a sa colonne dans `tableReserve`.
- **macOS — bandeau de pastilles filtrant par vendeur** (`VueFeuille.swift`) :
  en haut du panneau des rubriques concernées. Une
  pastille par **vendeur réellement présent** — aucune liste en dur, un lieu
  inédit obtient la sienne d'elle-même — plus un **compteur** des œuvres
  affichées, ancré à droite hors du défilement horizontal. Un clic filtre, un
  second lève le filtre.
  - **`safeAreaInset(edge: .top)` et NON un `VStack`** : le contenu doit
    continuer de défiler SOUS le bandeau et sous la toolbar, condition de leur
    translucidité. Empilé, le bandeau coupe la zone de défilement et les deux
    barres deviennent pleines.
  - **Aucun fond sur le bandeau** : la toolbar applique déjà son effet de
    verre ; un matériau ici s'y ajoute et donne deux couches de flou, donc une
    barre visiblement plus opaque qu'ailleurs.
  - `oeuvres` et `oeuvresGalerie` dérivent d'un `baseRubrique` commun. Les
    vendeurs présents s'y calculent **avant** le filtre : après, retenir une
    pastille ferait disparaître toutes les autres, sans retour possible.
- **Champ « Image »** en fin d'inspecteur et d'éditeur : poids, définition et
  nom du fichier stocké, via `PhotoStore.infosImage`. Sert à vérifier que la
  compression a tenu ses 450 Ko. Dans l'éditeur il est en lecture seule et
  fondé sur le `photoNom` **local**, donc à jour avant même l'enregistrement.
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
  - *En-têtes* : **ne pas imposer de police NI de graisse**.
    `listStyle(.sidebar)` fournit lui-même l'apparence standard (petit corps,
    gris, graisse normale).
  - *Libellés* : `.font(.system(size: 13))`, en noir **gras** quand la
    rubrique est sélectionnée (`.fontWeight`), sinon `Color.textePrincipal`.
  - *Couleur des en-têtes* : `.foregroundStyle(.secondary)` (le gris de Mail,
    et celui des titres de champs de `EditeurEntree`). À poser explicitement :
    `listStyle(.sidebar)` fournit bien ce gris, mais le
    `.foregroundStyle(Color.textePrincipal)` appliqué à toute la hiérarchie de
    `ContentView` l'écrase.
- **iOS — sidebar, typographie** (`ContentView.swift`) : tailles relevées via
  `UIFont` (taille de texte « Large ») — body **17 pt**, headline 17 pt
  semi-gras, subheadline 15 pt, **footnote 13 pt**, caption 12/11 pt.
  Même règle que sur macOS : l'en-tête de section doit être plus PETIT que les
  libellés. Le code imposait 18 pt aux en-têtes contre 17 pt aux libellés.
  - *En-têtes* : aucune taille ni graisse imposée (`listStyle(.insetGrouped)`
    fournit footnote/gris), plus `.foregroundStyle(.secondary)` pour rétablir
    le gris écrasé par `Color.textePrincipal`.
  - *Libellés* : laissés au corps par défaut (body, 17 pt).
  - **Ne jamais figer une taille en points sur iOS** : cela casse le
    **Dynamic Type** (réglage système de taille de texte). C'est la différence
    de méthode avec macOS, où les libellés sont fixés à 13 pt.

## Typographie générale (inventaire mené sur les deux plateformes)

Barèmes système, relevés via `NSFont` / `UIFont` (les pages HIG sont rendues en
JavaScript, inexploitables par extraction) :

| | macOS | iOS |
|---|---|---|
| Valeurs du barème | 10, 11, 12, 13, 15, 17, 22, 26 | 11, 12, 13, 15, 16, 17, 20, 22, 28, 34 |
| body | 13 | 17 |
| headline | 13 semi-gras | 17 semi-gras |
| callout / subheadline | 12 / 11 | 16 / 15 |
| footnote / caption | 10 / 10 | 13 / 12 |
| title3 / title2 | 15 / 17 | 20 / 22 |

**Règles retenues :**

- **macOS tourne autour de 13 pt** (libellés de sidebar, cellules du tableau,
  inspecteur, éditeur, légende de galerie), 11 pt pour le subordonné
  (en-têtes de section, pastilles de comptage).
- **Les prix sont à 13 pt PARTOUT sur macOS** — cellule Prix du tableau,
  inspecteur, légende de galerie, Synthèse (`policePrix` dans
  `VueSynthese.swift`) et éditeur. Ne pas les remettre à une autre taille.
- **Ne jamais figer une taille en points sur iOS** (Dynamic Type). Sur macOS
  c'est toléré, mais préférer un style sémantique quand il existe.
- **Vues partagées iOS/macOS** (`VueSynthese`, `VueGalerie`) : un style
  sémantique n'y vaut PAS la même chose selon la plateforme (`.callout` = 16 pt
  sur iOS mais 12 sur Mac). Passer par une propriété `Font` avec `#if os(macOS)`
  — patron `policeLegende` (`VueGalerie`), `policeLibelle` / `policeValeur` /
  `policeTitre` / `policePrix` (`VueSynthese`). **Ne pas convertir une vue
  partagée d'un seul geste** sans vérifier l'effet sur l'autre plateforme.
- `VueSynthese` utilisait 16/18/20 pt sur les deux plateformes — des valeurs
  pensées pour iPhone, hors barème macOS. Corrigé des deux côtés.
- Les tailles en points restant dans le code sont des **glyphes** SF Symbols
  (icônes décoratives : 26, 30, 40, 48 pt), pas du texte : c'est légitime.
  - *Légende des vignettes de galerie* (`VueGalerie.swift`) : prix et
    dimensions à 13 pt sur macOS via la propriété `policeLegende`. Ils
    héritaient de `.subheadline`, qui ne vaut que 11 pt sur macOS. Le fichier
    étant partagé, iOS conserve `.subheadline` (15 pt) : y écrire 13 pt
    rapetisserait le texte au lieu de l'agrandir.
- **macOS — sidebar, couleur de sélection** (`ContentView.swift`,
  `Couleurs.swift`) : `Color.fondSelectionSidebarMac`, marron
  **(142, 134, 127)** en mode clair et (89, 67, 47) en mode sombre, au lieu du
  bleu système. Le libellé est en blanc dans les deux modes.
  Deux nuances claires ont été comparées à l'écran via une pastille temporaire
  en pied de sidebar ; la plus foncée l'a emporté, le texte blanc contrastant
  mal sur (209, 187, 167). **Le choix est arrêté** : la pastille, le réglage
  `selectionFoncee` et la fonction `nuanceSelectionSidebar(foncee:)` ont été
  supprimés, ainsi que le typealias `RVBPublic` qui n'existait que pour cette
  signature.
  **`.tint()` n'a aucun effet** sur la surbrillance d'une `List` en style
  sidebar (essayé, sans résultat). La méthode qui marche : désactiver la
  surbrillance système avec `selectionHighlightStyle = .none` sur le
  `NSOutlineView` (helper `DesactiveSurbrillanceSidebar`), puis peindre le
  fond soi-même via `.listRowBackground` (rectangle arrondi, rayon 6,
  marges latérales 4 px).
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
- **Structure de la sidebar** (`ContentView.swift`, enum `Categorie`),
  identique sur les deux plateformes :

  ```
  ▼ VENTES ET DONS               ▼ RÉSERVE
       Catalogue                      Catalogue
       Ventes                       ▼ Catégories
       Dons                              Dessins
       Synthèse
     ▼ Modes de vente
          Expositions
          Ventes aux enchères
          Vente privée
          …tout mode inédit
     ▼ Catégories
          Tableaux · Dessins · Tapis
  ```

  - Deux grands blocs **repliables**, avec leurs sous-groupes. Le premier
    niveau réunit les **vues d'ensemble**, les sous-groupes les **types
    d'œuvres** et les **canaux de vente** — d'où Dons au premier niveau, qui
    désigne un mode de sortie et non un type.
  - `Categorie.titre` pilote à la fois le libellé de sidebar ET le titre de la
    page associée : renommer une rubrique se fait à un seul endroit. Attention
    aux titres codés en dur ailleurs (`VueOeuvresStructuree` en avait un).
  - **iOS** : la colonne sidebar porte le titre général « **Inventaire** » en
    grand format. C'est la vue racine de la pile de navigation en largeur
    compacte, le `NavigationSplitView` s'y repliant.
  - Les deux rubriques agrégées s'appellent « **Catalogue** » (une par
    section), pour ne pas se confondre avec ce titre de page.
  - La section « Expositions et enchères » a été supprimée : son unique
    rubrique, Ventes, est remontée au premier niveau.
  - La carte « Œuvres » de la vue Synthèse (bloc statistique, concept
    différent) n'a jamais été concernée par ces renommages.

- **Sous-catégories dynamiques par mode de vente** (`ContentView.swift`) :
  le groupe « Modes de vente » n'est **pas déclaré** — il est déduit des
  données par `modesDeVentePresents`. Un mode inédit crée sa rubrique dès
  qu'une œuvre le porte, et elle disparaît quand plus aucune ne l'a. Les modes
  de `modesDeVenteReference` gardent leur ordre, les inédits suivent par ordre
  alphabétique ; les valeurs vides, « Inconnu » et « Don » sont écartées.
  - Rendu possible par `case modeVente(String)`, un cas **à valeur associée**.
    `Categorie` a donc dû perdre `CaseIterable`, incompatible — sans
    conséquence, `allCases` ne servait qu'à du code mort.
  - **`.ventesRealisees.modesVente` renvoie `[]` volontairement** : Ventes
    recense TOUTES les œuvres vendues quel que soit le canal, et c'est son
    `statuts` (« Vendu ») qui la restreint. Y remettre une liste en dur
    ferait qu'un mode inédit aurait sa sous-catégorie **sans figurer dans
    Ventes** — le parent cesserait d'être la somme de ses enfants.
  - Corollaire : **ne pas déduire le rôle d'une vue de `modesVente`**.
    `VueOeuvresStructuree` calculait `estModeVentes = !modesVente.isEmpty` ;
    la liste devenue vide, la vue Ventes s'est mise à afficher le titre
    « Catalogue » et la section des dons. Le rôle et le titre lui sont
    désormais **passés en paramètre**.
  - Aiguillage par `Categorie.estVenteRealisee` : un test `== .ventesRealisees`
    ne couvrirait pas le cas à valeur associée.
  - Les libellés « Expositions » et « Ventes aux enchères » sont un **rendu
    au pluriel** dans `titre` ; la valeur stockée sur l'œuvre reste au
    singulier, et c'est elle que voient l'éditeur, l'inspecteur et le filtre.

- **iOS — le récapitulatif défile avec le contenu** dans toutes les vues.
  Placé au-dessus du `ScrollView` (ce qu'il était dans `VueiOS`), il restait
  ancré et la barre de navigation ne prenait pas sa transparence. En mode
  galerie, `VueGalerie` étant partagée avec macOS et ayant son propre
  `ScrollView`, elle reçoit un paramètre `entete` **optionnel** rendu dans la
  zone de défilement — nul côté Mac, où rien ne change.

- **Piège : `init` explicite et initialiseur mémberwise.** `VueiOS` et
  `VueOeuvresStructuree` en déclarent un ; ajouter une propriété ne suffit
  donc PAS à pouvoir la passer à l'appel, il faut aussi étendre l'`init`.
  Rencontré deux fois.
