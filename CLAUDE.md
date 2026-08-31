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
  règle que reposent le filtre de Réserve › Dessins et les pastilles des Dons.
  L'éditeur propose un menu fermé ; une valeur hors liste s'y ajoute telle
  quelle, pour signaler les œuvres restant à corriger au lieu de les écraser
  en silence.
  **Le menu ne propose PAS « Inconnu »** : ce serait entériner l'état qu'on
  cherche à corriger. Une œuvre encore dans cet état ouvre un menu sans
  sélection — c'est le signe qu'un choix reste à faire.
- Photos stockées **hors base**, sur disque, via `PhotoStore` (dossier « Photos »
  dans Application Support). La base ne contient que le nom de fichier.
- **Champs de suivi** ajoutés à `Oeuvre` : `statut`, `theme`,
  `collectionPersonnelle`, `lieuStockage`, `emplacement` (texte, défaut vide
  → SwiftData fait une migration légère automatique). Présents dans l'éditeur,
  l'inspecteur, la fiche iOS, le mode Liste et tous les exports.
  - **`collectionPersonnelle` est BINAIRE** : « Oui » ou « Non », jamais vide.
    `normaliserCollectionPersonnelle(_:)` (`TriEtTotaux.swift`) applique la
    règle, et elle est appelée aux QUATRE entrées possibles — import,
    ouverture de l'éditeur, enregistrement de l'éditeur, et une passe de
    reprise. Un champ vide y ferait un troisième état, que le `Picker` à deux
    entrées ne saurait pas représenter. C'est pourquoi il est **exclu de
    `remplirChampsVides`** : « Inconnu » n'y a pas de sens.
  - `estEnCollectionPersonnelle(_:)` sert au filtre de la rubrique dédiée. Il
    a remplacé une approximation fondée sur l'emplacement, faute de champ à
    l'époque.
  - **`lieuStockage` et `emplacement` ne se recouvrent pas** : le premier dit
    la maison (« Bourg-de-Péage », « Domicile »), le second le rangement fin
    (« Natures mortes carton 2 »). `rangementVignette(_:)` (`TriEtTotaux.swift`)
    choisit lequel montrer sur une vignette de Réserve — le lieu de stockage
    pour un **Tableau**, l'emplacement sinon, les cartons étant un rangement
    de dessins. Fonction PARTAGÉE par `VueGalerie` et `VueiOS` : le test écrit
    dans chaque vignette aurait divergé, comme les rendus l'ont déjà fait.
  - **`favori`** (`Bool`, défaut `false`) : indépendant de la feuille et du
    statut — un favori peut venir de n'importe où, et y reste ; il apparaît
    EN PLUS dans la rubrique Favoris, jamais déplacé ni dupliqué. Bascule
    par le menu contextuel des vignettes sur iOS (voir plus bas, section
    « Favoris »), pas encore de UI sur macOS.
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
  « Inconnu » dans tous les champs texte encore vides ; feuille
  « Réserve » sur les œuvres encore détenues ; thème « Personnage »
  renommé en « Portrait » ; statut vide réparé ; « À garder » converti en
  « Disponible » ; puis suppression des doublons d'un import répété.
  **L'ordre compte** : la passe « Inconnu » ne remplit que les champs vides,
  donc toute reprise qui en dépend doit s'exécuter AVANT elle, sinon elle ne
  trouve plus rien à remplir.
  **Plusieurs passes font exception et ÉCRASENT une valeur existante** :
  - `remplirFeuilleReserve` — `feuille` n'est jamais vide, elle vaut
    « Tableaux vendus » par défaut. Rejouable sans danger, le seul statut
    suffisant à décider : une œuvre disponible n'a été ni vendue ni donnée.
    Passe après les reprises de statut, dont elle se sert.
  - `renommerThemePortrait` — « Personnage » devient « Portrait », valeur que
    la table de correspondance de l'import photos écrit désormais (mot-clé
    « dessin portrait »). Sans elle les deux valeurs coexisteraient et la
    sidebar afficherait DEUX rubriques « Portraits », une par valeur stockée,
    sans rien qui l'explique à l'écran.
  - `convertirAGarderEnDisponible` — la table de l'import fait converger les
    six mots-clés vers « Disponible » ; sans cette passe la base porterait
    deux statuts pour une même réalité, selon la date d'import.
  - `supprimerDoublonsImport` — **elle SUPPRIME**, elle ne répare pas.
    Critère : feuille « Tableaux vendus » ET statut de réserve, combinaison
    contradictoire qu'aucune œuvre légitime ne peut porter et qui ne s'affiche
    nulle part. Une photo n'est effacée que si aucune œuvre conservée ne s'en
    sert.
  - `rangerTapisDonnes` — **la rubrique Dons se définit par la FEUILLE, pas
    par le statut.** Un tapis resté en « Tapis vendus » avec un statut
    « Donné » n'y entrait donc jamais, et le filtre par type ne pouvait pas le
    montrer faute de l'avoir dans sa liste ; l'éditeur ne propose aucun champ
    pour changer de feuille, le correctif ne pouvait pas se faire à la main.
    **Volontairement restreinte aux TAPIS**, alors que la contradiction
    « statut Donné + feuille de vente » peut toucher n'importe quel type : un
    balayage large aurait déplacé un nombre inconnu de tableaux et de dessins,
    donc fait bouger plusieurs compteurs et le contenu des exports. Élargir la
    portée demande une NOUVELLE passe, celle-ci ayant consommé son drapeau.
  - `purgerReserve` a existé, **DÉBRANCHÉE**, le temps qu'un export confirme
    qu'elle visait le mauvais lot : écrite avant l'analyse, elle ciblait la
    feuille `.reserve`, qui s'est révélée être la BONNE copie — les vrais
    doublons étaient ailleurs (`supprimerDoublonsImport`, au-dessus).
    **Supprimée depuis** (audit de code, 30 août 2026), avec le bloc appelant
    resté en commentaire dans `ContentView.swift` et le drapeau
    `reservePurgee` qui le gardait : aucun appelant vivant, et une fonction
    qui détruit toute la Réserve n'a pas sa place en dur dans le code une
    fois son unique raison d'être révolue. L'historique reste ici ; le code
    est dans Git si jamais besoin.
  **Une reprise ne rattrape pas un import ultérieur** : son drapeau est
  consommé au lancement. Un fichier réimporté doit donc déjà porter les
  bonnes valeurs.
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
  - **Les DEUX sens sont `async`, et le gros du travail sort de `MainActor`.**
    Un modèle SwiftData ne se lit que sur l'acteur principal : l'export en
    prend donc d'abord un instantané `Sendable` **images exclues**, puis part
    en tâche détachée pour lire les fichiers, encoder en base64 et produire le
    JSON. L'import fait l'inverse en trois temps — décodage JSON, puis
    écriture de TOUTES les images en une passe, tous deux hors `MainActor`,
    qui ne garde que les mutations SwiftData.
    - `OeuvreExport` et `Fichier` sont marqués `Sendable` pour franchir la
      frontière. **Sans effet sur le format du fichier** : le JSON produit est
      identique, les `.pvbase` existants restent lisibles.
    - La pastille « Import en cours » (iOS) n'a plus besoin du report d'un
      tour de boucle (`DispatchQueue.main.async`) qui lui laissait le temps de
      se peindre : un simple `Task` suffit, le fil principal restant libre
      pendant l'import.
    - **Limite connue, inchangée** : le fichier entier est construit en
      mémoire, images comprises. Sur une grosse base cela reste lourd — le
      corriger demanderait une écriture en flux, un autre chantier.
    - **Ordre de grandeur au 28 août 2026** : 479,9 Mo de photos donnent un
      `.pvbase` d'environ **640 Mo**, le base64 gonflant de 33 %. Export comme
      import le construisent entièrement en mémoire ; sur iPhone c'est au bord
      de ce qu'iOS tolère avant de tuer l'app.
      **Le critère de décision n'est PAS la croissance de la base** — elle
      n'augmente quasiment plus — **mais sa taille absolue** : tant que les
      transferts Mac → iPhone aboutissent, ne rien changer. Si l'app se ferme
      seule pendant un import `.pvbase`, c'est ce plafond, et l'écriture en
      flux devient alors un vrai chantier à ouvrir.
    - Deux leviers permettraient d'alléger davantage — abaisser le seuil de
      450 Ko, ou le côté long de 2000 px — mais **tous deux dégradent la
      qualité de TOUTES les photos**, y compris celles qui vont bien. 2000 px
      est déjà le minimum confortable pour un affichage plein écran sur un
      catalogue d'œuvres d'art : à ne considérer qu'en dernier recours.

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
  - Les six mots-clés de statut — « disponible », « à garder », « à garder
    absolument », pour tableaux comme pour dessins — donnent tous
    **« Disponible »** : la nuance dit une intention, pas le sort de l'œuvre.
    Rien pour les tapis, il n'en reste aucun de disponible.
  - **Un mot-clé peut dire DEUX choses.** Les quatre « à garder » fixent le
    statut ET rangent l'œuvre en collection personnelle : la collection est
    donc testée **avant** l'aiguillage `else if`, et non comme une de ses
    branches — sinon la seconde information serait perdue.
  - **Chaque thème a DEUX clés**, « dessin … » et « tableau … », pour une
    seule et même valeur (`tableau nature morte` → « Nature morte »). Le
    mot-clé nomme le genre d'objet ET le sujet, quand le champ `theme` ne
    retient que le sujet — le genre se lit sur `type`. Les clés « tableau »
    manquaient au départ : les tableaux importés n'obtenaient aucun thème et
    n'apparaissaient dans **AUCUNE** sous-rubrique de Thèmes, leur mot-clé
    finissant en « non reconnu » dans les Remarques. Rien n'était perdu, rien
    n'était exploitable — c'est exactement ce que le repli en Remarques est
    là pour garantir.
  - **Une œuvre peut porter PLUSIEURS thèmes** (« Dessin bouquet » ET
    « Dessin nature morte » sur la même photo) : `theme` reste un simple
    texte, plusieurs valeurs y cohabitent séparées par `separateurThemes`
    (`", "`, défini dans `TriEtTotaux.swift`). `ecrireTheme` — et non
    `ecrire` — les AJOUTE au lieu d'écraser : `ecrire` n'écrit que si le
    champ est vide, donc le second mot-clé de thème d'une même œuvre était
    silencieusement ignoré, sans même passer par le repli en Remarques
    (contrairement à un mot-clé non reconnu). L'œuvre n'apparaissait alors
    que dans une seule des deux sous-rubriques.
    - `themesDeOeuvre(_:)` (`TriEtTotaux.swift`) découpe le champ en thèmes
      individuels ; `correspond(themes:)` et `themesPresents` (sidebar)
      passent tous deux par elle plutôt que de comparer le champ entier —
      sans quoi une œuvre à deux thèmes ne correspondrait à aucune
      sous-rubrique.
    - Éditeur, inspecteur, fiche iPhone et exports n'ont rien à changer :
      ils affichent le champ tel quel, et « Bouquet, Nature morte » s'y lit
      très bien — l'éditeur permet même de corriger la liste à la main.
    - **Angle mort connu** : `renommerThemePortrait` (reprise consommée, voir
      plus bas) testait une égalité EXACTE sur tout le champ ; un thème déjà
      combiné contenant « Personnage » n'aurait pas été renommé en
      « Portrait ». Sans effet sur les imports futurs, son drapeau étant
      consommé.
  - `lieuxStockage` : « Stockage Bourg-de-Péage » → « Bourg-de-Péage »,
    « Stockage domicile » → « Domicile ». Attention aux traits d'union du
    mot-clé source, une clé mal orthographiée passe en « non reconnu » sans
    autre signe.
  - `dimensions` : un mot-clé par dimension (« dim100x65 » → « 100x65 »),
    écrit directement au format harmonisé de l'app — sans conversion,
    contrairement à `normaliserDimensions`, qui recorrige une saisie libre.
    Vingt-trois entrées à ce jour ; chaque clé doit rester au format
    « dimAxB » → « AxB », **A et B identiques dans les deux moitiés** — une
    faute de frappe à cet endroit (constatée une fois, corrigée avant
    d'être ajoutée) donnerait une dimension fausse plutôt qu'un rejet visible
    en Remarques.
- **Deux filets, sans lesquels une œuvre importée devient INVISIBLE** :
  - `statutParDefautImport` quand aucun mot-clé ne dit le sort. Un statut vide
    ne satisfait ni `estVenduOuDonne` ni `estEnReserve` : l'œuvre tombe entre
    les deux prédicats, bien en base et comptée à l'export, montrée par aucune
    rubrique. **630 œuvres ont disparu ainsi.**
  - **la feuille suit le statut** (`estEnReserve` → `.reserve`), comme à
    l'import `.pvbase`. La rubrique d'où part l'import ne dit rien de l'œuvre,
    et le repli `.tableauxVendus` produit sinon la même invisibilité.
- **`DernierImport`** retient les identifiants du dernier lot importé, pour
  Fichier › Importer › « Annuler l'importation ». **Les DEUX moteurs
  l'alimentent** : si seul l'import de photos mémorisait, un import CSV suivi
  d'une annulation supprimerait le lot de photos précédent. Un seul import est
  mémorisé à la fois.
- **Un DOSSIER peut être choisi** : l'import y prend toutes les images,
  sous-dossiers compris, dans un ordre alphabétique stable
  (`imagesContenues(dans:)`). Fichiers et dossiers peuvent être mélangés dans
  la même sélection.
  - **Les autorisations d'accès sont ouvertes AVANT la boucle et tenues
    jusqu'à la fin.** Un fichier trouvé dans un dossier n'a pas
    d'autorisation propre : il dépend de celle du dossier qui le contient.
    Les fermer par fichier, comme avant, ferait échouer la lecture.
- **`ImportPhotos.importer` est `async`** et rend la main entre deux fichiers
  (`await Task.yield()`). Sans cela la boucle monopolise le fil principal du
  premier au dernier fichier : l'interface ne se redessine qu'à la fin, et un
  compteur y resterait figé avant de sauter d'un coup.
  - La progression s'affiche **en pied de sidebar macOS**, via l'objet
    `@Observable` partagé `ProgressionImport.partagee` — l'import se déroule
    dans `VueFeuille`, à l'autre bout de la hiérarchie. Même patron que
    `PastillePrix`. La zone du bas ne montre rien hors import.
  - **Réserve connue** : la compression reste synchrone sur le fil principal.
    Le compteur avance à chaque fichier, mais l'interface est peu réactive
    pendant le traitement de chacun. La sortir du fil principal est un autre
    chantier.
- **`NSOpenPanel.message` impose une largeur minimale au panneau** — il
  s'affiche dans un bandeau en tête. Un texte long y plaque le panneau à sa
  largeur plancher : élargir la barre latérale exigerait de rétrécir la zone
  des fichiers sous SON minimum, et le glissement est refusé, **alors que le
  curseur change bien de forme** — symptôme trompeur, qui ne désigne pas la
  cause. Le panneau des photos n'a donc PAS de `message` : ne pas en
  réintroduire un, c'est exactement ce qu'on rajoute en voulant bien faire.
  Celui du CSV en garde un, plus court, qui dit la structure attendue du
  dossier ; ne pas l'allonger.
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
    - **L'import CSV y avait échappé** (`Import.swift`) : il appelait encore
      `PhotoStore.enregistrer(image:)`, qui ré-encode en PNG, après un
      `NSImage(contentsOf:)` inutile. Toute photo entrée par cette voie pesait
      donc plusieurs mégaoctets au lieu de 450 Ko, et alourdissait ensuite le
      cache, les exports et les transferts `.pvbase`. Corrigé : cette voie
      passe par `importerImageCompressee` comme les autres.
    - `enregistrer(image:)` **et son helper `pngData(de:)` ont été
      supprimés** (audit de code, 30 août 2026) : plus aucun appelant depuis
      ce correctif. C'était le seul chemin PNG de l'app ; `enregistrerDonnees`
      et `jpegData(de:)`, eux, restent et sont toujours utilisés.
    - **Les photos DÉJÀ entrées par cette voie restent lourdes** : corriger
      l'import ne réécrit pas le disque. D'où `RecompressionPhotos.swift`
      (macOS), Fichier › « Recompresser les photos… ».
- **`RecompressionPhotos` (macOS)** : rattrape les photos entrées avant que
  toutes les voies d'import passent par `importerImageCompressee`. Mesuré sur
  un PNG hérité de 19 Mo : **441 Ko après recompression, facteur 43**.
  - **Passe exécutée le 28 août 2026 sur la vraie base : 591,1 Mo → 479,9 Mo**,
    soit 111,2 Mo libérés (19 %). L'écart avec le facteur 43 est normal et ne
    signale aucun défaut : ce facteur vaut pour le PIRE cas, un PNG hérité de
    l'import CSV. La grande majorité des photos venaient de l'import IPTC, qui
    compressait déjà — elles étaient à ~450 Ko et le filtre les a ignorées.
  - **La commande reste utile après coup** : elle est rejouable sans risque
    (une photo déjà sous le seuil n'est pas touchée) et rattrapera toute photo
    lourde entrée par une voie encore inconnue.
  - **Ce n'est PAS une passe de `RepriseDonnees`, et ça ne doit pas le
    devenir.** Les reprises tournent au lancement sur le fil principal :
    recompresser des centaines d'images à ce moment-là gèlerait l'app à chaque
    démarrage — exactement le défaut qu'on cherche à supprimer. C'est une
    commande de menu, déclenchée quand l'utilisateur le décide.
  - **L'ordre des quatre étapes est ce qui rend l'opération sûre** : peser,
    fabriquer un NOUVEAU fichier (nom UUID distinct), n'écrire `photoNom`
    qu'une fois ce fichier en place, supprimer l'ancien seulement après. Une
    panne à n'importe quel moment laisse l'œuvre pointant sur un fichier
    valide ; le pire résidu est un orphelin, que le nettoyage au lancement
    efface.
  - **Garde-fou** : si le fichier recompressé n'est pas plus léger que
    l'original, il est jeté et l'original conservé. Une photo illisible est
    laissée telle quelle et comptée en échec — jamais perdue.
  - `analyser(oeuvres:)` pèse le dossier AVANT de poser la question : la
    confirmation annonce des chiffres réels (nombre de photos concernées,
    poids cumulé, poids total) au lieu d'une promesse vague.
  - **L'opération n'est PAS annulable** — `Annuler` ne la défait pas, elle
    réécrit des fichiers. L'alerte le dit en toutes lettres et invite à
    exporter la base d'abord.
  - Le balayage part des **œuvres**, pas du contenu du dossier : une photo
    orpheline n'a pas à être recompressée, elle a vocation à disparaître.

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
- **DEUX accents, selon la section** : orange dans « Ventes et dons »,
  **bleu ardoise** (`Color.bleuArdoise`, 70/100/135 en clair, éclairci en
  sombre) dans la Réserve. La couleur dit d'un coup d'œil où l'on se trouve,
  sans lire le titre.
  - `Categorie.accent` donne la teinte, et `ContentView` la pose **une seule
    fois** sur la colonne de contenu, via l'environnement
    (`\.accentRubrique`, défini en fin de `Couleurs.swift`).
  - **Pourquoi l'environnement et non un paramètre** : l'accent sert dans une
    dizaine de vues imbriquées — vignettes, pastilles, prix, boutons de la
    visionneuse, éditeur —, dont plusieurs sont partagées par les deux
    sections. Le passer de main en main aurait demandé un paramètre à chaque
    étage ; posé une fois, il descend seul, y compris à travers les feuilles
    et les présentations plein écran.
  - Valeur par défaut : l'orange. Une vue qui ne déclare rien reste donc dans
    la teinte de « Ventes et dons ».
- **`cremeFond` (macOS) : PREMIER essai fixe (242,242,247) ESSAYÉ PUIS
  REVERTÉ, SECOND essai fixe (250,245,235, la même crème qu'iOS) EN COURS
  depuis le 30 août 2026, à la demande explicite malgré le risque
  documenté.** Sur macOS 26, `.windowBackgroundColor` résout en BLANC PUR
  (255,255,255) — identique à `fondLegende`/`controlBackgroundColor` — au
  lieu du gris de fenêtre traditionnel de macOS. Vérifié en rendant réellement
  la couleur dans une `NSWindow` (pas seulement `resolvedColor` hors contexte,
  qui peut tromper sur une couleur dynamique).
  - **Premier essai** : une valeur FIXE (242,242,247, calée sur le gris de
    page iOS mesuré pour `systemGroupedBackground`), pour une page à la même
    teinte sur les deux plateformes.
  - **RÉGRESSION CONSTATÉE À L'USAGE, revertée** : la barre de titre et la
    toolbar natives de macOS suivent, elles, `.windowBackgroundColor` — une
    couleur système dynamique dont la valeur réelle importe peu tant que le
    contenu la reprend À L'IDENTIQUE, ce qui garantit leur synchronisation
    PAR CONSTRUCTION, quelle que soit cette valeur. En la remplaçant par une
    constante indépendante, le contenu a cessé de suivre ce que fait la
    toolbar : ça a produit une VRAIE couture entre la barre de titre
    (blanche, nativement) et le panneau de contenu (gris fixe) — un défaut
    qui **n'existait pas avant ce changement**. `cremeFond` est donc revenu
    sur `.windowBackgroundColor`, tel quel.
  - **La conclusion qui suivait ici (« ne plus fixer de valeur ») reste
    valable en théorie** : aucun moyen de forcer la toolbar native à suivre
    une teinte personnalisée n'est apparu depuis. **Second essai lancé
    quand même, sciemment, à la demande explicite de l'utilisateur** — même
    mécanisme dynamique (`NSColor(name:)`, clair/sombre), mais une couleur
    fixe en clair (250,245,235, celle d'iOS) au lieu de suivre
    `.windowBackgroundColor` dans les deux modes. Le mode sombre, lui, reste
    sur `.windowBackgroundColor` — non concerné par la demande, comme sur
    iOS où seul le clair change. **Si la même couture titre/contenu
    réapparaît à l'usage, revenir au premier réflexe : reverter sur
    `.windowBackgroundColor` pur, comme la première fois.** Ne pas
    s'obstiner sur d'autres variantes de cette piste sans nouvel élément —
    la cause structurelle (toolbar hors de portée de l'API publique) n'a pas
    changé, voir la campagne « NON RÉSOLU » sur l'isolement du bouton
    Inspecteur, plus bas.
  - **`fondTuile` reste sur `underPageBackgroundColor` (246,246,246), PAS
    calée sur `cremeFond`.** Un essai bref les avait alignées quand
    `cremeFond` avait sa valeur fixe (242,242,247) : `cremeFond` étant
    revenu sur `.windowBackgroundColor`, qui vaut EXACTEMENT
    `.controlBackgroundColor` (celui de la carte, `fondLegende`), une tuile
    qui la suivrait redeviendrait invisible sur sa carte — exactement le bug
    déjà corrigé une première fois pour la Synthèse.
    `underPageBackgroundColor` reste le seul système à s'en distinguer
    réellement, SANS avoir à suivre la toolbar : une tuile n'est jamais
    visible depuis la barre de titre, rien ne l'y oblige.
  - **Bug corrigé — deux tons entre la barre de titre/outils et le bandeau
    de pastilles de tri**, visible Inspecteur ouvert (`bandeauFiltres`,
    `VueFeuille.swift`). Trois pistes tentées avant de trouver la vraie
    cause :
    1. aligner `cremeFond` sur le gris iOS (ci-dessus) — n'a pas suffi ;
    2. `.background(.bar)` sur le bandeau au lieu de `.ultraThinMaterial` —
       n'a pas suffi seul non plus, la cause n'étant pas le bandeau ;
    3. fond opaque de diagnostic (`Color.cremeFond` sans transparence) sur
       le bandeau — a permis de confirmer que le bandeau matchait déjà le
       panneau de contenu, et que la VRAIE couture était ailleurs : entre la
       toolbar native et CE panneau, à cause du `cremeFond` fixe (piste 1).
    **Cause réelle et correctif** : la régression `cremeFond` décrite
    plus haut. Une fois revertée, plus aucune divergence entre le contenu et
    la toolbar native, donc plus de couture — quel que soit le matériau du
    bandeau. `.bar` est néanmoins CONSERVÉ sur le bandeau plutôt que
    revenir à `.ultraThinMaterial` : plus robuste par construction, il
    s'aligne sur le rendu natif d'une barre système sans dépendre de ce qui
    défile derrière lui.
  - **Persistant malgré tout ça** : la couture reste visible à l'usage. La
    piste `cremeFond`/`.bar` n'était donc pas la bonne, ou pas la seule —
    non résolue à ce stade. **À surveiller en particulier avec le SECOND
    essai `cremeFond` fixe lancé le 30 août 2026** (ci-dessus) : si une
    couture réapparaît maintenant, elle peut venir de LÀ, en plus ou à la
    place de la cause jamais identifiée ici.
  - **Contournement essayé, RESTREINT au Catalogue de « Ventes et dons »
    seulement** (`Categorie.pastillesTypeDansToolbar`, `ContentView.swift` +
    `VueFeuille.swift`) : plutôt que de continuer à chercher pourquoi le
    bandeau ne s'accorde pas avec la toolbar, ses pastilles de type sont
    posées DIRECTEMENT dans la toolbar (nouveaux `ToolbarItem`), et le
    bandeau lui-même disparaît pour cette rubrique — plus de bandeau, plus
    de couture possible avec lui.
    - Restreint à `.oeuvres` : seule rubrique n'ayant JAMAIS de filtre par
      vendeur, ce qui simplifie ce premier essai à un seul jeu de pastilles
      (`pastillesTypeDansToolbar`, réutilise `pastilleType(libelle:mot:)` —
      pas de deuxième version à tenir d'accord).
    - **Toutes les autres rubriques à bandeau gardent l'ancien
      comportement inchangé** (Ventes, Dons, Réserve, Favoris, sous-modes de
      vente) : à étendre ailleurs seulement si ce premier essai convient à
      l'usage.
    - **Disposition** : chaque pastille est son PROPRE `ToolbarItem`, et le
      compteur (`pastilleCompteur`) un autre — regroupés dans un seul
      `ToolbarItem` avec un `HStack`, macOS les rendait comme un unique
      bouton englobant toute la rangée (bordure système autour du bloc
      entier). L'ensemble est placé AVANT le `ToolbarSpacer(.flexible)` en
      tête de `contenuBarreOutils`, ce qui l'aligne à GAUCHE pendant que ce
      spacer pousse le reste de la toolbar à droite.
    - **SUPPRIMÉ depuis (audit de code, 30 août 2026), pas seulement
      masqué.** Quand `menuFiltreTypeToolbar` (voir plus bas, « RÉTABLI
      depuis ») a été étendu à `.oeuvres`, `pastillesVisibles` a appris à
      s'éteindre pour toute rubrique qui a ce menu — or `.oeuvres` a
      TOUJOURS les deux à `true`, donc ce bloc ne pouvait plus jamais
      s'afficher. Code mort de façon certaine (pas un essai qu'on hésite
      encore à trancher) : supprimé avec la propriété
      `Categorie.pastillesTypeDansToolbar` et le paramètre qui la portait
      dans `VueFeuille`. `pastilleType`/`pastilleCompteur` restent, toujours
      utilisées par `bandeauFiltres`.
  - **ESSAI — pastilles et compteur DÉSACTIVÉS dans toute la section
    « Ventes et dons »** (`afficherPastillesVentesEtDons` dans
    `TriEtTotaux.swift`, `false`) : couvre à la fois le bloc toolbar de
    Catalogue ci-dessus et l'ancien bandeau de Ventes/Dons/modes de vente.
    `Categorie.estSectionVentesEtDons` dit quelles rubriques sont concernées
    (tout le premier bloc de la sidebar) ; la Réserve et Favoris n'y entrent
    jamais. `VueFeuille.pastillesVisibles` combine les deux. Code conservé,
    `true` restaure tout d'un coup dans toute la section.

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

- **Préchauffage des vignettes au lancement : ESSAYÉ, ABANDONNÉ.** Un cache de
  vignettes sur disque (dossier « Vignettes », 640 px en HEIC) préparé en tâche
  de fond dès l'ouverture, avec compteur et temps restant en pied de barre
  latérale. Jugé à l'usage « plus de mal que de bien » et **entièrement
  reverté** ; `CacheVignettes.swift` et `PhotoStore.swift` sont revenus à
  l'identique. Ne pas le refaire sans une approche différente.
  - Fait mesuré à retenir de l'essai : **un préchauffage en MÉMOIRE est hors
    de portée.** Une vignette de galerie pèse près d'un mégaoctet une fois
    décodée, et la base en compte plus d'un millier — plus d'un gigaoctet. Le
    cache de `CacheVignettes` est un dictionnaire **sans borne** : il ne rend
    jamais la mémoire, et parcourir un grand catalogue l'accumule déjà en
    entier. C'est un point à traiter pour lui-même, indépendamment de tout
    préchauffage.
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
- **« The executable is not codesigned » / « No code signature found »** — sur
  Mac comme sur iPhone. **Ce n'est PAS un problème de certificat ni de profil**
  (la piste où l'on perd le plus de temps) : une compilation incrémentale saute
  l'étape `CodeSign` quand elle juge le binaire à jour. Le remède est un
  **`clean build`**, rien d'autre.
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
- **`NSUndoManager.setActionName(_:)` exige un groupe d'annulation OUVERT.**
  `dupliquerSelection()` l'appelait sans `beginUndoGrouping()` au préalable :
  l'exception Objective-C levée interrompait la commande sans le moindre
  message dans l'interface — « la commande ne fait rien » comme seul
  symptôme. `supprimerSelection()`, juste à côté dans le même fichier, avait
  déjà le bon garde-fou (`beginUndoGrouping()` / `processPendingChanges()` /
  `endUndoGrouping()`) ; `dupliquerSelection()` ne l'avait jamais reçu.
  Vérifier ce garde-fou sur TOUTE future action de `VueFeuille` qui pose un
  nom d'action d'annulation.
- **Marge portée par un élément VOISIN plutôt que par celui qui en a besoin.**
  Rencontré plusieurs fois, dernièrement dans `VueDonsStructuree` : le
  récapitulatif s'est retrouvé collé à la première rangée de vignettes après
  la suppression du découpage par type, car c'était le titre de section
  (`padding(.top, 24)`) qui tenait l'espace — pas le récapitulatif. **Toute
  cellule doit porter sa propre marge**, indépendamment de ce qui l'entoure.
  Barème du projet : 8 pt sous le récapitulatif, 16 pt au-dessus du contenu,
  soit les 24 pt de `VueiOS` (où les 16 viennent du `padding(16)` de
  `VueGalerie`).
- **Un découpage par test d'appartenance doit prévoir LE RESTE.**
  `VueDonsStructuree` séparait « Tableaux » et « Dessins » en cherchant ces
  mots dans le champ `type` : une œuvre au type disant autre chose — une
  technique, « Inconnu » — n'entrait dans aucune section et **disparaissait**,
  9 dons affichés sur 53. Ne découper ainsi qu'une fois le champ garanti
  fermé (voir `typesOeuvre`), ou prévoir explicitement le reliquat.
- **Choisir un champ sur son VIDE ne marche plus** depuis la reprise
  « Inconnu » : `acheteur` n'est jamais vide sur un don, il contient ce mot.
  Les vignettes affichaient donc « Inconnu » à la place du destinataire
  (`ligneGras`, `ligneNom`). Le champ à lire se décide sur `o.feuille`.
- **`clipped()` ne découpe que le DESSIN, pas la zone sensible aux clics.**
  Une image en `scaleEffect(5)` restait cliquable bien au-delà de son cadre et
  interceptait le bouton de fermeture posé au-dessus, qui devenait inopérant
  dès qu'on avait zoomé. Ajouter `.contentShape(Rectangle())` après la découpe.
- **Un fond avec `ignoresSafeArea()` déborde sous les colonnes translucides.**
  La sidebar et l'inspecteur échantillonnent ce qui se trouve derrière eux
  dans la fenêtre : un fond noir qui dépasse les fait virer au gris foncé. Le
  symptôme — « la sidebar change de couleur » — ne désigne pas sa cause.
- **Un moniteur `NSEvent` local capte AUSSI pendant un panneau système.**
  `NSOpenPanel` s'exécute hors processus en bac à sable, ce qui laisse croire
  qu'il est hors d'atteinte — il ne l'est pas : ⌘A sélectionnait le contenu du
  panneau de la vue EN ARRIÈRE-PLAN au lieu des fichiers affichés devant. Les
  cinq capteurs testent donc `window?.isKeyWindow` avant d'agir.
- **Un moniteur `NSEvent` local est appelé AVANT la chaîne de répondants**,
  donc avant `.onKeyPress`. Renvoyer `nil` suffit à reprendre la main sur un
  raccourci posé ailleurs : c'est ainsi que ← et → pilotent la visionneuse au
  lieu de la galerie qui les capte en temps normal.
- **Référence de méthode dans un ternaire à résultat optionnel** :
  `condition ? maMethode : nil` fait échouer la vérification de types de TOUTE
  la vue, avec « failed to produce diagnostic » — message inexploitable.
  Écrire `guard condition else { return nil }` puis une closure explicite.
- **Un `overlay` SwiftUI passe TOUJOURS derrière une `.sheet`.** Celle-ci se
  présente au-dessus de toute la hiérarchie qui l'ouvre : remonter l'overlay à
  la racine n'y change rien. C'est ce qui cachait la pastille « Prix masqués »
  derrière l'éditeur. Deux réponses selon la plateforme :
  - **macOS** : la même pastille est posée AUSSI sur le contenu de l'éditeur,
    les deux partageant `messagePrix` ;
  - **iOS** : `PastillePrix.swift` la rend dans une **`UIWindow` à part**
    (`windowLevel = .alert + 1`), seule façon de passer devant n'importe
    quelle feuille de n'importe quel écran.
    **Le `hitTest` qui renvoie `nil` n'est pas du code mort** : cette fenêtre
    recouvre l'écran en permanence et intercepterait tous les touchers sans
    lui — l'app deviendrait impilotable. La scène est cherchée au premier
    affichage, pas à l'`init`, où elle n'existe pas encore.
- **Un premier répondant sans vue de saisie fait remonter le CLAVIER.**
  Sur iPhone, un appui prolongé sur une vignette ouvrait le clavier système en
  même temps que l'aperçu du menu contextuel — alors que l'app ne contient
  AUCUN champ de saisie. En cause, `ControleurSecousse` (`MasquagePrix.swift`),
  seul premier répondant de l'app iOS : un `UIViewController` de taille nulle
  qui prend le focus au seul titre de recevoir `motionEnded`. Le menu
  contextuel présente son aperçu dans sa PROPRE fenêtre, le système réévalue
  alors le premier répondant, et un contrôleur qui ne vend aucune vue de
  saisie fait apparaître le clavier par défaut.
  **Première correction, qui a AGGRAVÉ le mal** : suspendre l'écoute le temps
  du menu, puis la reprendre. Rétablir le premier répondant après chaque menu
  le rendait actif bien plus souvent qu'avant, et le clavier s'est mis à
  surgir à l'ouverture de **n'importe quel menu de barre d'outils** — un
  défaut qui n'existait pas. Toute présentation fait réévaluer le premier
  répondant, pas seulement un menu contextuel.
  **Correctif retenu** : la détection ne passe plus par la chaîne des
  répondants du tout. `DetecteurSecousse` (`MasquagePrix.swift`) lit
  l'accéléromètre via **CoreMotion** — seuil 2,2 g, une bascule par seconde au
  plus — et l'app n'a désormais **AUCUN premier répondant**, ce qui supprime
  la cause au lieu de la contourner. Ne pas réintroduire de `UIViewController`
  premier répondant pour capter un événement : c'est le montage qui a produit
  les deux défauts.
- **`ObservableObject` et `@Published` réclament `import Combine`** depuis
  Swift 6 (`MemberImportVisibility`). Préférer le macro `@Observable`, qui
  n'en a pas besoin.
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
  (helper `DefilementTableau` dans `VueFeuille.swift`).
- **Chercher une vue AppKit par sa CLASSE depuis la racine de la fenêtre : à
  ne plus jamais faire.** Cette consigne a longtemps figuré ici sous la forme
  « la sidebar est un `NSOutlineView`, l'exclure explicitement » — et c'est
  elle qui a fini par tout casser.
  - Le `Table` de SwiftUI peut lui aussi être adossé à un `NSOutlineView`
    selon la version de macOS. `DefilementTableau`, qui excluait cette classe,
    ne trouvait alors plus le tableau du panneau : **plus AUCUNE liste de
    l'app ne défilait**. Et `DesactiveSurbrillanceSidebar`, qui prenait le
    premier `NSOutlineView` venu, coupait la surbrillance DU TABLEAU au lieu
    de celle de la sidebar — les lignes paraissaient non sélectionnables au
    lancement, et le défaut se « réparait » en changeant de rubrique.
  - **Remonter DE PROCHE EN PROCHE depuis la vue du représentable**, posée en
    `.background` de la vue visée, donc juste à côté d'elle
    (`tableauProche(de:)`, `outlineViewProche(de:)`). Le voisinage est un
    critère stable ; la classe ne l'est pas.
  - Symptôme trompeur au passage : la panne touchait TOUTE l'app alors qu'elle
    a été signalée sur une seule rubrique. Une fonction partagée qui lâche se
    remarque d'abord là où l'on travaille.
- **Sélection bleue ou grise dans un `Table` : ce n'est pas un réglage.**
  AppKit dessine la sélection en bleu quand le tableau a le focus clavier, en
  gris sinon — comportement système. La surbrillance neutralisée par
  `DesactiveSurbrillanceSidebar` ne concerne QUE la barre latérale.
- **Capsule commune à plusieurs boutons de toolbar macOS — CINQ essais,
  TOUS ABANDONNÉS, code revenu à l'état d'origine.** Objectif : grouper le
  menu de tri et le bouton de sens (`VueFeuille.swift`) dans une capsule
  commune, comme le sont Galerie et Liste juste à côté. Chaque essai vérifié
  à l'écran (captures fournies par l'utilisateur, la mienne restant bloquée
  dans cet environnement) :
  1. `ToolbarItemGroup` — chaque bouton dans son propre cercle séparé.
  2. Deux `ToolbarItem` nus et adjacents, sans wrapper ni spacer — marche
     pour Galerie/Liste, pas ici. Piste explorée (Galerie/Liste hors de tout
     `if`, la paire tri+sens nichée sous `if modeAffichage`) **réfutée** :
     le bouton Inspecteur, sous ce même `if`, se rend pourtant très bien
     comme groupe isolé.
  3. `ControlGroup`, le composant pourtant documenté pour ça — toujours deux
     cercles séparés. Hypothèse retenue : `menuTri` est un `Menu`, pas un
     `Button`, et garde son fond natif quel que soit le conteneur.
  4. Capsule dessinée à la main (`.buttonStyle(.plain)` +
     `.menuStyle(.borderlessButton)` sur chaque contrôle, fond retiré puis
     laissé au système) — capsule présente mais plus étroite que
     Galerie/Liste, icônes réduites.
  5. `.imageScale(.large)` sur les icônes (une `Image` nue rend plus petite
     qu'une icône de `Label`) + espacement à 8 pt — **toujours pas
     satisfaisant**.
  **Décision : abandonné.** Tout le code de cette campagne a été reverté au
  commit `d044ca1` (`ToolbarItemGroup`, deux boutons visuellement séparés) —
  c'est la présentation retenue, malgré son nom qui suggère un groupage
  qu'elle ne produit pas sur ce système. Ne pas retenter ces cinq pistes
  sans un nouvel élément.
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
  
- **Vignettes : une file SÉRIELLE, pas une tâche par image**
  (`CacheVignettes.swift`). Un `Task.detached` par vignette saturait le pool
  coopératif de Swift Concurrency et Xcode signalait un **« Hang Risk »**
  (inversion de priorité). Une `DispatchQueue` sérielle en `.userInitiated`
  sérialise le décodage : les vignettes arrivent l'une après l'autre au lieu
  de se disputer les fils.
- **Préchargement de l'image pleine taille** (`PhotoStore.prechargerImage` +
  `cacheImages`, un `NSCache` à 6 entrées) : lancé dès le contact du doigt, il
  dispose du délai d'appui pour décoder. `UIImage.preparingForDisplay()` force
  le décodage **hors** du chemin d'animation, sans quoi la première ouverture
  saccade là où les suivantes sont fluides.

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

## Mentions des bibliothèques tierces et nom de l'app

- **Trois dépendances SwiftPM** (`XLKit`, `ZIPFoundation`, `swift-textfile`,
  toutes sous licence MIT) sont citées dans les deux plateformes — un endroit
  à tenir à jour à chaque ajout ou retrait d'une bibliothèque, la liste étant
  dupliquée deux fois (macOS et iOS n'ont aucun mécanisme commun ici).
  - **macOS** (`APropos.swift`) : `NSApp.orderFrontStandardAboutPanel(options:
    [.credits: …])`, le mécanisme standard Apple pour ajouter un texte enrichi
    sous le nom et la version dans le panneau « À propos » système — le reste
    du panneau (icône, version, copyright) reste géré par le système. Rangé
    dans un `CommandGroup(replacing: .appInfo)` (`PierreVincentApp.swift`),
    qui remplace l'entrée par défaut du menu pomme (grisée sinon, faute de
    contenu personnalisé).
  - **iOS** : pas de panneau « À propos » dans l'app elle-même — l'information
    est déposée dans **Réglages système › PierreVincent**, via
    `Settings.bundle/Root.plist` (quatre `PSGroupSpecifier`, chacun avec
    `Title` et `FooterText`). C'est le mécanisme standard Apple pour ajouter
    des préférences à une app dans les Réglages iOS ; ce fichier n'apparaît
    dans le bundle .app qu'une fois compilé pour iOS, jamais pour macOS.
    - La ligne de titre au-dessus de ce contenu (bouton retour + nom de la
      page) est la barre de navigation SYSTÈME des Réglages iOS — un élément
      non personnalisable par une app tierce, à ne pas confondre avec du
      contenu de `Root.plist`.
- **Nom affiché de l'app : « PierreVincent », sans tiret, PARTOUT** où
  l'utilisateur le voit — décision prise après avoir constaté une divergence
  entre plateformes (« Pierre-Vincent » sur l'écran d'accueil iOS et dans les
  Réglages, « PierreVincent » dans la barre de menus macOS).
  - **Cause de la divergence** : le nom de menu bar macOS vient de
    `PRODUCT_NAME = "$(TARGET_NAME)"`, et la target Xcode s'appelle
    `PierreVincent` (sans tiret) — donc déjà correct sans rien y toucher.
    `INFOPLIST_KEY_CFBundleDisplayName` valait « Pierre-Vincent », AVEC
    tiret : c'est cette clé, utilisée par iOS (écran d'accueil, Réglages) et
    lue par macOS en dernier recours si elle diffère du nom du produit, qui
    portait le mauvais nom. Corrigée dans `project.pbxproj`, Debug et
    Release.
  - Corrigés avec elle, les deux seuls autres textes AFFICHÉS portant le
    tiret : le libellé du menu « À propos de PierreVincent »
    (`PierreVincentApp.swift`) et le pied de page des Réglages iOS
    (`Settings.bundle/Root.plist`).
  - **Volontairement laissés tels quels** : les commentaires de code en
    français mentionnant « Pierre-Vincent » (CLAUDE.md, en-têtes de
    fichiers) — texte interne, jamais vu par l'utilisateur, sans rapport
    avec le nom affiché.
  - **Volontairement NON touché, et à traiter avec prudence si un jour
    demandé** : `PhotoStore.swift` crée le dossier de stockage réel sur
    disque dans `Application Support/Pierre-Vincent` (AVEC tiret). Ce n'est
    pas un texte affiché mais un CHEMIN — le renommer déplacerait le dossier
    et romprait l'accès à la base et aux photos déjà présentes sur toute
    machine ayant déjà lancé l'app, sans une migration explicite (copier
    l'ancien dossier vers le nouveau nom au lancement). Un simple
    renommage de la chaîne serait une régression silencieuse des données.

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
  (colonne) et fiche iPhone. Ordre de référence : Prix · Type/Thème ·
  Dimensions/Format · Statut/Collection personnelle/Lieu de stockage/
  Emplacement · Vendeur-Acheteur-Mode de vente (ou Vendeur-Destinataire-Mode
  de vente) · Date · Remarques.
  - **Vendeur figure aussi sur un don**, depuis peu, AVANT Destinataire :
    Vendeur dit qui a donné l'œuvre, Destinataire qui l'a reçue. Le champ
    existait déjà sur le modèle (utilisé pour les ventes) ; seul son
    affichage manquait pour cette feuille, aux trois surfaces à la fois.
    Une reprise ponctuelle, `renseignerVendeurDons`, a inscrit « Florian »
    sur tous les dons existants — en ÉCRASANT, le champ n'ayant jamais été
    saisi nulle part pour cette feuille jusque-là.
  - **Type et Thème partagent le même encadré, CÔTE À CÔTE** — le genre
    d'objet et son sujet se lisent ensemble. Thème n'est donc plus dans
    l'encadré Statut. Même présentation que Dimensions/Format, déjà côte à
    côte : les deux paires utilisent une `HStack` à l'intérieur de la
    cellule, au lieu de piler les champs. La fiche iPhone avait encore
    Dimensions/Format superposés — corrigée pour rejoindre les deux autres
    surfaces, qui doivent rester identiques.
  - **Libellés affichés « Support » et « Genre »**, aux TROIS surfaces —
    ex-« Type » et « Thème ». Les champs sous-jacents (`type`, `theme`,
    `choixType`, `typesOeuvre`) gardent leur ancien nom ; seul le texte
    montré à l'écran change (`champType()`/`champTexte` dans l'éditeur,
    `ligneInspecteur` dans l'inspecteur, `ligne` dans la fiche iPhone).
    **Étendu depuis aux colonnes du tableau macOS** (mode Liste) : les six
    `TableColumn("Type"…)`/`TableColumn("Thème"…)` des trois tableaux
    (Ventes, Dons, Réserve) dans `VueFeuille.swift` affichent maintenant
    « Support »/« Genre » elles aussi. Seul le PREMIER argument change (le
    titre affiché) ; le second (`value: \Oeuvre.type`) reste le vrai
    chemin de données, sans rapport avec ce texte.
    - **`Colonnes.swift` (exports CSV/XLS/PDF/dossier) N'A PAS été touché,
      délibérément.** Son `titre` de colonne est aussi ce que `Import.swift`
      cherche à la relecture d'un CSV (`val("Type")`, comparaison EXACTE sur
      l'en-tête de colonne). Renommer l'un sans l'autre casserait le
      réimport d'un fichier exporté par cette version : une colonne
      « Support » ne serait plus reconnue, `type` resterait vide. Même
      risque que déjà rencontré et évité pour « Vente privée » et
      « Artenchères » — libellé affiché et clé de correspondance doivent
      être dissociés avant de renommer l'un des deux, pas changés ensemble
      sans y penser. À faire seulement sur demande explicite, avec
      `Import.swift` mis à jour dans le même geste.
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
- **Vue Synthèse** : cartes (**Dons**, Ventes, Prix de vente, Enchères) contenant
  des tuiles. Une tuile « Total » (somme euros tableaux + dessins + tapis)
  figure dans le bloc Ventes. **Carte Dons remontée en TÊTE**, avant Ventes,
  à la demande — l'ordre était Ventes/Prix de vente/Dons/Enchères au départ.
  - **Carte « Ventes »**, ex-« Œuvres » : les trois tuiles de comptage n'ont
    plus le mot « vendus » dans leur intitulé (« Tableaux », « Dessins »,
    « Tapis ») — la carte elle-même le dit désormais. Les deux tuiles de dons
    qui y vivaient (« Tableaux donnés », « Dessins donnés ») en sont sorties.
  - **Carte « Prix de vente »**, ex-« Montants » : ses deux premières tuiles
    perdent le préfixe « Prix des » (« Tableaux », « Dessins ») — la carte le
    dit désormais. Sa troisième tuile, **« Catégories », a été SUPPRIMÉE** :
    le total par type qu'elle donnait figure déjà en détail sous chaque tuile
    de la carte « Ventes ».
  - **Nouvelle carte « Dons »** (à l'origine entre Prix de vente et Enchères,
    depuis remontée en tête de la vue) : les deux tuiles qui viennent d'en
    être extraites, renommées « Tableaux » et « Dessins » — plus besoin de
    les distinguer de leurs pendants vendus, la carte s'en charge. Aucune n'a
    de prix (comme partout pour les dons), et elles n'ont donc plus besoin de
    réserver la ligne de prix vide de `tuileNombre` (`reserverEspace`), qui
    ne servait qu'à aligner leur hauteur sur des tuiles à prix dans
    l'ancienne grille commune.
    - **Sous-section « Destinataires »** : TOUTES les personnes ayant reçu au
      moins un don, nom + nombre d'œuvres. `destinatairesTries`
      (`VueSynthese.swift`, ex-`topDestinataires` — renommée après le retrait
      de la limite à cinq, qui ne correspondait plus à ce qu'elle renvoie)
      groupe `oeuvresDonnees` par champ `destinataire`, écarte les valeurs
      vides et « Inconnu » (un destinataire non identifié ne désigne personne
      à classer), trie par nombre décroissant. Présentation proche de la
      carte « Enchères et expositions » (nom à gauche, valeur orange à
      droite) : `tuileDestinataire` est le pendant de `tuileVendeur`, sans
      mise en forme monétaire — un COMPTE d'œuvres, pas un montant. Absente
      si aucun don n'a de destinataire identifié.
      - **Sur DEUX colonnes fixes** (`colonnesDestinataires`,
        `GridItem(.flexible())` × 2 — pas `.adaptive` comme `colonnesTuiles`,
        pour ne jamais retomber à une seule colonne), pour gagner de la
        hauteur sur une liste qui peut compter beaucoup de destinataires. Le
        nom porte `.lineLimit(1)` : une colonne deux fois plus étroite
        qu'avant tronque plus vite un nom long.
        - **Numéro de position devant chaque nom (1, 2, 3…) : ajouté puis
          RETIRÉ**, dans la même session. Le rang venait de l'index dans
          `destinatairesTries` (déjà trié par nombre décroissant), pas d'un
          champ stocké — rien à défaire côté données si on le rajoute un jour.
        - **Nom ABRÉGÉ sur iOS seulement** : « Florian Innocente » s'affiche
          « F. Innocente » — initiale du prénom (premier mot du champ
          `destinataire`) suivie du reste tel quel. `nomAffiche(_:)` fait
          l'aiguillage par `#if os(iOS)` DANS cette vue partagée ; macOS
          affiche le nom complet, sans y toucher. Purement un rendu :
          `destinataire` n'est jamais modifié en base. Un nom sans espace (un
          seul mot, y compris « Inconnu ») n'a rien à abréger et reste
          inchangé (`nomAbrege(_:)`, garde-fou sur `mots.count > 1`).
  - **Le récapitulatif iOS « Vendues / Données »**, en tête de la carte
    Ventes, a été RETIRÉ : la carte Ventes a désormais un contenu IDENTIQUE
    sur les deux plateformes. Il faisait doublon avec la nouvelle carte
    « Dons », qui détaille les mêmes dons par type.
  - **Carte « Enchères et expositions »** : les trois libellés portent
    désormais un millésime (« Artenchères 2024 », « Drôme Enchères 2025 »,
    « RempART 2026 »). **Le libellé affiché et le nom cherché sont
    DISSOCIÉS** : `sommeVendeur` continue de chercher le nom écrit sur les
    œuvres (champ `vendeur`, sans millésime) — lui changer le libellé sans
    ce garde-fou aurait mis tous les montants à 0 €, faute d'œuvre dont le
    vendeur porterait littéralement l'année.
- **iOS — Inventaire (sidebar), couleur de contraste sur la section choisie**
  (`ContentView.swift`) : la ligne se teinte (`Color.fondCelluleSidebarSelectionnee`,
  nouvelle couleur adaptative dans `Couleurs.swift`, distincte de l'orange de
  marque réservé aux valeurs chiffrées) au moment de la sélection, reste teintée
  0,4 s puis s'éteint **toute seule** via une tâche asynchrone — sans jamais
  dépendre d'un retour de navigation ni d'un geste personnalisé (voir pièges
  ci-dessous).
- **Visionneuses d'images — en place PARTOUT** (`Categorie.visionneuseIntegree`,
  qui renvoie désormais `true`). Elles remplacent Quick Look dans toutes les
  rubriques, sur les deux plateformes.
  - Le drapeau `visionneuseIntegree` (paramètre) est **conservé** — renvoyer
    `false` sur `Categorie.visionneuseIntegree` suffirait à revenir en
    arrière. **Le code de Quick Look, lui, a été supprimé** (audit de code,
    30 août 2026) : `QuickLook.swift` en entier, `apercuURL` et
    `.apercuQuickLook` dans `VueFeuille.swift`, et la branche de repli de
    `declencherApercu()`. `Categorie.visionneuseIntegree` étant fixée à
    `true` depuis un moment, cette branche n'était plus jamais atteinte par
    AUCUNE rubrique — pas un essai à trancher, du code mort constaté. Pour
    revenir à Quick Look sur une rubrique, il faudrait réécrire ce pont
    (l'ancien code reste dans l'historique Git).
  - Sur iPhone, trois vues ont dû recevoir le geste — `VueiOS`,
    `VueOeuvresStructuree` et `VueDonsStructuree` — chacune ayant son propre
    rendu de vignettes. Sur Mac, `VueFeuille` sert toutes les rubriques : une
    seule ligne a suffi.
  - **macOS** (`VisionneusePanneau.swift`) : la barre d'espace l'ouvre à la
    place de Quick Look. Posée en `overlay` sur le panneau et NON en `.sheet`,
    qui couvrirait toute la fenêtre, sidebar et barre d'outils comprises.
    Échap ferme, le pincement du trackpad agrandit de 1× à 5×, le glissement
    déplace l'image agrandie.
    - **Le champ sous l'image (emplacement + dimensions) est remplacé par un
      bouton favori** (étoile pleine/vide selon `oeuvre.favori`), au même
      style que les boutons de navigation Précédent/Suivant. Bascule via
      `basculerFavori(_:contexte:)`, le même point de passage que partout
      ailleurs — `ModelContext` récupéré via `@Environment(\.modelContext)`.
      Nécessite `import SwiftData` explicite dans ce fichier (jusque-là sans),
      sinon erreur de compilation `MemberImportVisibility` sur `\.modelContext`.
  - **iOS** (`VisionneuseOeuvres.swift`) : appui prolongé sur une vignette,
    le tap continuant d'ouvrir la fiche. Plein écran en portrait comme en
    paysage. Balayage latéral pour changer d'image — **inerte tant qu'on est
    zoomé**, le glissement y servant alors à se déplacer. **Glissement
    vertical vers le bas pour fermer** (seuil 120 pt), lui aussi inerte une
    fois zoomé ; le contenu suit le doigt et le fond s'estompe, sans quoi on
    ne saurait pas que le geste est engagé.
  - **iOS — l'ouverture passe par un MENU CONTEXTUEL à aperçu, façon Photos**
    (`TransitionVisionneuse.swift`). L'appui prolongé fait grossir un aperçu
    de la photo ; **taper l'aperçu** ouvre la visionneuse.
    - **Écrit en UIKit** (`InteractionApercu`, `UIContextMenuInteraction`).
      `.contextMenu(menuItems:preview:)` de SwiftUI affiche bien l'aperçu mais
      **ne prévient pas quand on le TAPE** : il fallait alors une commande
      « Afficher en grand » dans le menu, là où Photos ouvre d'un simple tap.
      UIKit expose ce rappel (`willPerformPreviewActionForMenuWith`), SwiftUI
      non. La vue posée en overlay prend AUSSI le tap simple, faute de quoi
      elle le confisquerait à la carte SwiftUI en dessous.
    - Le menu porte une entrée **« Ajouter aux favoris »**, devenue « Retirer
      des favoris » une fois l'œuvre favorite — voir la section Favoris plus
      bas pour le mécanisme complet, apparu depuis.
    - `preferredContentSize` est **obligatoire** sur l'aperçu : sans elle il
      prend la dimension intrinsèque de l'image, soit des milliers de points.
      `TransitionVisionneuse.taillePreview` (320 × 420) sert DEUX fois — à
      dimensionner l'aperçu, et à donner à la visionneuse son point de départ.
      Les deux doivent rester d'accord.
    - **Le retour haptique est fourni par le système** : ne pas en ajouter un
      second.
  - **La transition d'ouverture part de l'APERÇU, pas de la vignette.**
    `.zoom(sourceID:in:)` repart toujours de la vignette : il rejouait donc un
    agrandissement que le menu venait déjà de jouer, d'où **deux mouvements
    superposés** — le défaut signalé comme « disgracieux ». La méthode en
    vigueur est le **ressort maison** (`TransitionVisionneuse.choisie =
    .ressortMaison`), qui part de la taille de l'aperçu et va au plein écran :
    un seul mouvement, dans la continuité de ce que le doigt vient de faire.
    - `TransitionOuverture` n'applique **rien** aujourd'hui, et c'est voulu :
      c'est le menu qui porte le mouvement. Les deux méthodes restent décrites
      dans l'enum, utiles le jour où la visionneuse s'ouvrira autrement.
    - `presenter(_:)` enveloppe le changement d'état dans une `Transaction`
      sans animation. Neutraliser sur le contenu présenté ne suffirait pas :
      c'est le changement d'état qui déclenche la présentation.
  - **`VisionneuseOeuvres` est distincte de `VisionneuseImagePleinEcran`**,
    qui montre UNE photo depuis la fiche de détail. Les deux coexistent.
  - Boutons au style des pastilles de comptage : cercle opaque cerclé
    d'orange, glyphe blanc, contour atténué en bout de série.
  - **`RetourAppuiLong`** (iOS) réunit vibration et son du geste. Centralisé
    parce que le retour existait dans QUATRE vues et allait diverger.
    **Usage désormais réduit** : les vignettes de galerie sont passées au menu
    contextuel, qui fournit son propre retour — y ajouter celui-ci ferait
    double emploi. Il ne sert plus qu'à l'appui prolongé sur la photo de la
    fiche de détail. Conservé tel quel : tout geste d'appui prolongé qu'on
    rajouterait devra s'y raccorder plutôt que d'en refaire un.
    - `duree` vaut **0,07 s**, descendu par paliers depuis 0,5 s. À ce niveau
      le geste se distingue à peine d'un tap appuyé, et le tap ouvre la FICHE
      quand l'appui ouvre la VISIONNEUSE : si des fiches deviennent difficiles
      à ouvrir, c'est cette valeur qu'il faut remonter. Effet secondaire moins
      visible : le préchargement de l'image dispose de ce délai pour décoder,
      donc plus il raccourcit, plus la première ouverture risque de saccader.
    - Haptique `.heavy` à pleine intensité, générateur **conservé et préparé
      dès le contact** : un générateur neuf déclenche à froid, ce qui se
      ressent comme un choc mou.
    - Son : le « tock » de clavier. **Son identifiant n'est pas une constante
      publiée par Apple** — il fonctionne de longue date, sans garantie — et
      il est **muet en mode silencieux**. La vibration reste donc le signal
      principal, le son un supplément.
  - **Appui prolongé désormais RÉSOLU sur les lignes de LISTE iPhone**
    (`VueiOS`, `VueDonsStructuree`, `VueOeuvresStructuree`) — même menu
    contextuel « Ajouter aux favoris » et même appui prolongé qu'en galerie.
    Deux tentatives avaient échoué avant d'y arriver :
    - `.onLongPressGesture` n'aboutissait jamais — la ligne était un
      `Button`, qui captait le geste ;
    - `simultaneousGesture` avait causé d'autres problèmes, comme il l'avait
      déjà fait sur les lignes de sidebar (voir les pièges).
    **Solution retenue** : abandonner le `Button` de la ligne, exactement
    comme pour les vignettes de galerie — `.contentShape(Rectangle())` +
    `.overlay(InteractionApercu(...))` / `MenuApercuSiDemande(...)`, la même
    vue UIKit qui gère déjà tap simple, appui prolongé et menu contextuel en
    galerie. Le double-tap tenté juste avant sur ces mêmes lignes (voir
    plus bas, section Favoris) avait échoué pour une raison DIFFÉRENTE — deux
    reconnaisseurs de TAP se disputent le même geste — qui ne s'applique pas
    à l'appui prolongé, un geste que sa durée distingue nativement d'un tap.
- **NON RÉSOLU — couleur de sélection des listes macOS.** Après un passage par
  une rubrique de la Réserve, la sélection passe du bleu au gris et **y reste**,
  dans toutes les rubriques, jusqu'à la relance. Le défaut est récent.
  Deux hypothèses réfutées par l'observation : ce n'est pas le focus clavier
  (le comportement est stable et lié à la rubrique), et ce n'est pas
  `DesactiveSurbrillanceSidebar` visant le mauvais tableau (la sidebar garde
  son marron, et restreindre sa recherche au nombre de colonnes n'a rien
  changé). Piste : depuis le retrait du `.id(cat)`, le MÊME `NSTableView` sert
  dans toutes les rubriques — un réglage posé une fois y demeure.
- **`.statusBarHidden()` n'obtient pas fiablement la main sur la barre système
  — et PAS seulement dans une présentation imbriquée.**
  Le défaut a fini par se produire aussi dans `VisionneuseOeuvres`, qui
  s'ouvre pourtant depuis la racine : `.ignoresSafeArea()` était posé sur le
  `GeometryReader`, donc sur TOUT le contenu, commandes comprises. La croix,
  placée à 20 pt du bord PHYSIQUE, venait cogner contre l'heure et la
  batterie. **Ne pas compter sur `.statusBarHidden()` pour positionner une
  commande**, quelle que soit la façon dont la vue est présentée.
  - Les deux visionneuses plein écran partagent désormais la MÊME règle :
    seul le **fond** ignore la zone sûre (il doit couvrir l'encoche), les
    **commandes** restent mesurées depuis elle. C'était déjà la règle de
    `VisionneuseImagePleinEcran` ; `VisionneuseOeuvres` l'a rejointe, ce qui
    aligne enfin leur position de croix — l'intention affichée de longue date.
  - Effet secondaire assumé : `ouvertureDepuisVignette(ecran:)` reçoit
    maintenant la taille de la zone sûre et non celle de l'écran entier. Le
    ressort d'ouverture part donc d'un facteur très légèrement différent,
    invisible à l'œil.
- **Le cas d'origine, toujours valable** : `.statusBarHidden()` dans une
  présentation MODALE IMBRIQUÉE. `VisionneuseImagePleinEcran`
  s'ouvre en `.fullScreenCover` DEPUIS un `.sheet` (`DetailiOS`) —
  contrairement à `VisionneuseOeuvres`, qui s'ouvre directement depuis la
  racine. Faire ignorer la zone sûre à TOUTE la vue (comme le fait
  `VisionneuseOeuvres`, via `.ignoresSafeArea()` sur l'ensemble) suppose que
  la barre système est bien masquée ; dans le cas imbriqué elle ne l'est pas
  fiablement, et la croix — positionnée en le croyant — venait cogner contre
  l'affichage réel de la batterie. **Correctif** : seul le FOND ignore la
  zone sûre (il doit couvrir l'encoche) ; la croix reste mesurée depuis la
  zone sûre, comme avant. Conséquence acceptée : sa position n'est plus
  pixel pour pixel identique à celle de `VisionneuseOeuvres`. Piste non
  explorée pour un alignement parfait : forcer le masquage de la barre
  autrement pour une présentation imbriquée (le délégué de fenêtre plutôt que
  le modificateur SwiftUI).
- **iOS — photo en plein écran depuis la fiche détail d'une œuvre**
  (`DetailiOS` dans `VueiOS.swift` + `VisionneuseImagePleinEcran.swift`) :
  appui prolongé sur la photo — un « Long Press Gesture » dans la
  terminologie Apple, retour haptique `UIImpactFeedbackGenerator(.medium)` —
  → ouverture en plein écran avec pinch-to-zoom (1x-5x), glissement pour se
  déplacer une fois zoomé, double-tap pour réinitialiser.
  **Croix et fermeture par glissement calquées sur `VisionneuseOeuvres`** :
  même pastille (cercle sombre cerclé de l'accent de la rubrique, et non plus
  un disque blanc uni), même seuil de fermeture par glissement vertical
  (120 pt), neutralisé pendant le zoom.
  **La position de la croix N'EST PAS pixel pour pixel identique**, et c'est
  volontaire — voir le piège ci-dessous sur les présentations imbriquées.
  Les deux visionneuses plein écran d'une photo doivent se manipuler et se refermer de
  façon identique.
- **iOS — transition de glissement latéral entre œuvres** (`DetailiOS`,
  swipe gauche/droite ou chevrons) : le contenu de la fiche est enveloppé
  dans un `ZStack` (indispensable pour que `.transition(.move(edge:))` se
  voie réellement à l'intérieur d'un `ScrollView`), animation 0,25 s.
  - **`.disabled()` seul ne grise pas visuellement un bouton de toolbar en
    `.topBarLeading`.** Les chevrons Précédent/Suivant restaient tapables à
    l'œil (sans effet réel, `naviguer()` garde son propre garde-fou) même en
    bout de liste. Un `.foregroundStyle` explicite, conditionné sur la même
    règle que `.disabled`, est posé en plus sur chaque `Image`.
- **Sidebar — zone du bas** (`ContentView.swift`, les deux plateformes) : le
  bas de la barre latérale est **vide**. Il a successivement porté les
  pastilles de choix de thème, le bouton « G » (mise en gras des en-têtes de
  section), puis la pastille de comparaison des deux marrons de sélection —
  tous retirés une fois leur question tranchée : les en-têtes sont en
  graisse normale, il n'y a plus de sélecteur de thème, et le marron de
  sélection est arrêté.
  Le squelette `barreOutilsBas` qui restait en commentaire pour y reposer un
  futur bouton de test a été **retiré** (audit de code, 30 août 2026) : du
  texte-code inerte, pas un essai à bascule — Git garde l'historique si un
  nouveau bouton de test est un jour utile ici.
  - **Occupée depuis par un nouveau bouton de test, sur les DEUX
    plateformes** (30 août 2026) : des pastilles pour comparer des fonds de
    PAGE candidats — `TestFondPage` (`Couleurs.swift`), `pastillesTestFondPage`
    / `pastilleTestFond` (`ContentView.swift`). Un clic change
    `@AppStorage(TestFondPage.cle)` ; `Color.cremeFond` lit cette valeur pour
    sa teinte CLAIRE (le sombre n'est jamais concerné, comme pour `cremeFond`
    lui-même). **Trois choix** (cinq au départ, « Sauge » et « Ivoire»
    retirées le jour même), dans l'ordre d'affichage : gris (242,242,247, le
    gris de page iOS déjà mesuré), ardoise (distincte du bleu ardoise
    d'accent de la Réserve), puis crème (250,245,235, la valeur actuelle de
    l'app, défaut) — RGB centralisés dans `TestFondPage.options`, source
    unique lue à la fois par les boutons et par `cremeFond`. Le repli de
    `rvbClair` (valeur inconnue ou absente) se fait par IDENTIFIANT
    (« creme »), pas par position dans la liste — sans quoi réordonner les
    options aurait changé la valeur par défaut.
    - **Rafraîchissement SANS `.id()` sur `ContentView`** — règle absolue de
      ce fichier, voir plus haut (« NB : plus de `.id(themeApp)` »). Chacune
      des HUIT vues qui affichent `Color.cremeFond` (`ContentView`,
      `EditeurEntree`, `VueFeuille`, `VueDonsStructuree`, `VueGalerie`,
      `VueiOS`, `VueSynthese`, `VueOeuvresStructuree`) déclare son propre
      `@AppStorage(TestFondPage.cle) private var testFondPage`, MÊME QUAND
      elle ne s'en sert pas ailleurs dans son code : c'est ce qui la fait
      observer la clé et redessiner son fond à jour dès qu'un bouton change
      la valeur, sans reconstruire toute la hiérarchie ni perdre le focus
      clavier — exactement la méthode que la note sur `.id(themeApp)`
      recommandait sans l'avoir encore mise en pratique.
    - **ESSAI TEMPORAIRE, à retirer une fois le choix tranché** : les cinq
      boutons et leurs deux fonctions dans `ContentView.swift`, l'enum
      `TestFondPage` dans `Couleurs.swift`, la ligne qui lit `rvbClair` dans
      `cremeFond`, et les HUIT `@AppStorage(TestFondPage.cle)` ajoutés
      seulement pour observer le changement.
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
  - **ESSAI VISUEL en cours** : dans la section Réserve (Favoris exclue), le
    contour au repos est retiré — seul le fond plein de la sélection reste.
    Piloté par `Categorie.estSectionReserve`, testé explicitement plutôt que
    déduit de la feuille ou de l'accent : Favoris partage `.reserve` et le
    bleu ardoise sans faire partie de la section, un test sur l'un ou l'autre
    l'aurait donc incluse par erreur.
    Même essai, même critère, sur le **compteur du bandeau de pastilles**
    (`pastilleCompteur` dans `VueFeuille.swift`, `BandeauTypes` sur iOS) : les
    pastilles de filtre gardent leur contour, qui dit qu'on peut cliquer
    dessus — seul le chiffre en perd un.
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
  - **« Toutes » (ex-« Tout ») porte `person.3`, PAS l'icône de la rubrique**
    — seule EXCEPTION à la règle générale du menu de type, qui veut que
    l'entrée sans filtre porte l'icône de la rubrique entière (voir plus
    bas). L'icône de rubrique d'un mode de vente est `cart`, qui ne dit rien
    du critère « vendeur » ; `person.3` rejoint la famille déjà utilisée par
    `iconeMenu` pour le bouton lui-même (`person.3` sans filtre,
    `person` un vendeur retenu) et par les entrées de vendeur
    (`person`) — toute la famille « personne » raconte le même critère.
  - **Le bouton du menu affiche TOUJOURS l'icône de l'élément retenu**
    (`iconeMenu`) : `person.3` tant qu'aucun vendeur n'est choisi, sinon
    `person` un vendeur retenu.
    - **Bug corrigé** : le bouton affichait `person.fill` une fois un
      vendeur retenu, alors que ce vendeur est listé avec `person` dans
      le menu — l'icône du bouton et celle de l'entrée sélectionnée
      divergeaient, un signal trompeur. `iconeMenu` reprend désormais
      `person`, l'icône EXACTE de l'entrée, plutôt qu'une variante
      `.fill` de la même famille.
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
- **Filtre par TYPE — trois pastilles, Tableaux · Dessins · Tapis**, sur les
  deux plateformes. En place dans Catalogue, Ventes, Dons, et dans la Réserve.
  - **La rubrique dit lesquelles elle propose** : `Categorie.typesFiltre`,
    une LISTE de mots, qui a remplacé le booléen `filtreParType`. Une liste
    vide = pas de filtre du tout.
    - La **Réserve** n'en affiche que deux : il n'y reste aucun tapis
      disponible, et une troisième pastille n'y filtrerait jamais que vers une
      liste vide.
    - **Expositions** non plus, pour la même raison — aucun tapis n'y a été
      exposé. Le test porte sur la valeur STOCKÉE, au singulier
      (« Exposition ») ; « Expositions » n'est qu'un rendu de `titre`, et
      comparer dessus ne retiendrait jamais rien.
    - Les **modes de vente** ont les trois, comme Ventes dont ils sont des
      sous-ensembles, et cumulent donc DEUX filtres — vendeur puis type. Les
      vendeurs se calculent toujours AVANT, sinon en retenir un ferait
      disparaître les autres.
  - **Libellés, symboles et filtrage sont dans `TriEtTotaux.swift`**
    (`motsTypesFiltrables`, `libelleTypeFiltrable`, `symboleTypeFiltrable`,
    `filtrerParType`). Ils ont existé en DEUX exemplaires — un enum côté iOS,
    une propriété privée dans `VueFeuille` — qui auraient divergé au premier
    ajout : c'est exactement ce qui est arrivé au filet de sélection.
  - **Fixes, et non déduites des données** — contrairement aux pastilles de
    vendeur. Le champ `type` porte encore des libellés composés
    (« Tableau — huile sur toile ») : collecter les valeurs distinctes
    donnerait des dizaines de pastilles, pas trois.
  - Filtrage par **inclusion** du mot. Corollaire à garder en tête : une œuvre
    dont le type n'en nomme aucun n'est retenue par AUCUNE pastille, et les
    comptes ne totalisent alors pas la rubrique. Sans filtre elle reste
    visible, ce qui est l'état par défaut.
  - *macOS* : bandeau de pastilles, même apparence et même `safeAreaInset` que
    celui des vendeurs, avec lequel il partage `bandeauFiltres`.
  - *iOS* (`BandeauTypes.swift`) : `BandeauTypes` (les pastilles) et
    `MenuFiltreTypes` (le menu de barre d'outils) pilotent le **MÊME** état —
    il n'y a pas deux filtres à tenir d'accord. Corps **sémantiques**
    (`.subheadline`, `.caption`) et non des points, contrairement au bandeau
    macOS : figer une taille casserait le Dynamic Type.
  - *iOS, trois vues à servir* : `VueiOS` (Réserve), `VueDonsStructuree`
    (Dons) et `VueOeuvresStructuree` (Catalogue et Ventes), chacune ayant son
    propre rendu de vignettes.
    **Dans `VueOeuvresStructuree`, le filtre s'applique APRÈS `baseVentes`**,
    d'où se déduisent les vendeurs du menu : les calculer sur une liste déjà
    filtrée par type ferait disparaître des entrées, sans retour possible.
    Même précaution que pour le filtre par vendeur.
  - **Le libellé de l'entrée sans filtre est « Tout »**, dans le menu de type
    comme dans celui des vendeurs : les deux menus d'une même barre d'outils
    l'annonçaient avec deux mots différents. Les identifiants gardent leur nom
    (`symboleFiltreTous`), qui désigne l'icône et non le libellé.
  - **L'icône du menu dit le CRITÈRE ACTIF**, exactement comme celle du menu
    de tri : le type retenu quand il y en a un, et sinon celle de l'entrée
    « Tout ». Cette dernière est **l'icône de la rubrique elle-même**
    (`Categorie.symboleFiltreTous`) pour CE menu-ci — « Tous » y désigne la
    rubrique entière. Les cinq rubriques de Thèmes reçoivent donc le même
    `paintbrush.pointed` : il ne les distingue pas entre elles, mais il dit
    bien « tous les thèmes ». **Le menu de filtre par vendeur fait
    exception** à cette règle, voir plus bas : son entrée « Toutes » porte
    `person.3`, pas l'icône de la rubrique.
  - **Ce menu a d'abord été RETIRÉ de la barre d'outils, sur les DEUX
    plateformes** — `menuFiltreType` (macOS), `MenuFiltreTypes` dans les
    trois vues iOS — gouvernés par un même drapeau
    `afficherMenuFiltreTypeToolbar` (`TriEtTotaux.swift`), le bandeau ou la
    rangée de pastilles restant seul moyen de filtrer par type.
  - **RÉTABLI depuis, mais SEULEMENT sur macOS** (`Categorie.menuFiltreTypeToolbar`,
    `ContentView.swift` + `VueFeuille.swift`) : posé dans la toolbar juste
    APRÈS la capsule Galerie/Liste. Chaque entrée garde sa propre icône
    (`symboleTypeFiltrable`), et l'icône du bouton suit toujours le critère
    actif (`iconeMenu`, inchangé).
    - **`MenuFiltreTypes` (les 3 menus iOS) et `afficherMenuFiltreTypeToolbar`
      SUPPRIMÉS depuis** (audit de code, 30 août 2026) : macOS a désormais son
      propre mécanisme, indépendant, et iOS n'a jamais eu de suite prévue
      pour eux — le bandeau de pastilles y suffit déjà. Le drapeau n'avait
      plus aucun `if` à gouverner une fois les trois menus retirés, et la
      struct `MenuFiltreTypes` plus aucun appelant. Les propriétés
      `symboleFiltreTous` qui n'alimentaient qu'eux dans `VueiOS`,
      `VueDonsStructuree` et `VueOeuvresStructuree` sont parties avec —
      `BandeauTypes` (les pastilles) ne les utilisait pas, elle garde sa
      propre icône « Tous » par défaut.
    - **D'abord restreint à Catalogue et Ventes**, puis **étendu à la
      Réserve et à Favoris** : Catalogue et Collection personnelle de la
      Réserve, toute sous-rubrique de Genres (`.reserveTheme`), et Favoris —
      même présentation que Catalogue/Ventes, bandeau remplacé par ce menu.
      `VueFeuille.pastillesVisibles` (essai `afficherPastillesVentesEtDons`,
      voir plus haut) a dû apprendre une deuxième raison de masquer le
      bandeau : `!menuFiltreTypeToolbar && (...)` — bandeau et menu font
      double emploi, une rubrique n'a jamais les deux à la fois. **Pas les
      sous-rubriques de Supports de la Réserve**
      (`.reserveTableaux`/`.reserveDessins`) : leur `typesFiltre` est déjà
      vide, filtrer par type une rubrique déjà filtrée par type n'aurait
      aucun sens. Le menu de tri par critère (`menuTri`) reste absent de
      toutes ces rubriques, sans rien à changer : `feuille != .reserve` et
      `favoriSeul` l'excluaient déjà. Les modes de vente restent seuls à
      garder leur bandeau de pastilles.
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
  - **Fond du bandeau : `.ultraThinMaterial`, et rien d'autre.** Réglé par
    tâtonnement, les deux excès ayant été observés à l'écran :
    - **aucun fond** — le contenu qui défile passe NET derrière les pastilles,
      alors qu'il est flouté sous la toolbar juste au-dessus ;
    - **un matériau plus épais** (`regularMaterial`) — la toolbar et le
      bandeau se lisent comme une seule barre lourde, visiblement plus opaque
      que dans les rubriques sans pastilles.
    Le matériau le plus fin prolonge le verre de la toolbar sans l'épaissir.
    En dessous, le catalogue n'offre plus rien : il faudrait une couleur
    semi-transparente, réglable finement mais qui ne floute pas.
    **Vérifier tout changement sur Ventes aux enchères**, la vue où le défaut
    d'opacité s'était manifesté, et pas seulement sur Dons.
  - `oeuvres` et `oeuvresGalerie` dérivent d'un `baseRubrique` commun. Les
    vendeurs présents s'y calculent **avant** le filtre : après, retenir une
    pastille ferait disparaître toutes les autres, sans retour possible.
  - **Sur iPhone, une SEULE vue le sert : `VueOeuvresStructuree`.**
    `Categorie.filtreParVendeur` n'est vrai que pour un mode de vente, et ce
    cas part vers elle par `estVenteRealisee`. `VueiOS` en avait une seconde
    copie, qui ne s'affichait donc JAMAIS — et divergeait déjà de celle qui
    vit, faute d'être vue. Supprimée, avec le paramètre `filtreParVendeur` de
    cette vue ; un commentaire dit sur place pourquoi il n'y en a pas, sans
    quoi la prochaine lecture y verra un oubli.
  - **ESSAI VISUEL — le compteur perd son fond plein et son contour**, sur les
    DEUX plateformes : `pastilleCompteur` (macOS, `VueFeuille.swift`) et
    `compteur` (iOS, `BandeauTypes.swift`). Un simple texte dans l'accent de la
    section, sans `Capsule`, pour qu'il ne se lise plus comme un bouton — il
    n'en est pas un, contrairement aux pastilles de filtre à côté de lui.
    **Ce composant est PARTAGÉ entre Galerie et Liste** (même instance,
    au-dessus du contenu quel que soit le mode affiché) : il n'existe aucun
    moyen de le styler différemment selon la présentation sans dupliquer le
    code — le changement touche donc les deux modes à la fois, sur les deux
    plateformes.
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
  - **Règle étendue aux DEUX grands en-têtes de bloc**, « Ventes et dons » et
    « Réserve » : ils portaient `.title3` en gras (`policeGrandIntitule`,
    supprimée depuis, plus aucun appelant), bien plus voyant que les en-têtes
    de sous-groupe (« Catégories », « Modes de vente »…) qu'ils surplombent —
    hiérarchie visuelle inversée par rapport à la règle ci-dessus. Corrigé
    d'abord sur macOS : même style natif que tous les autres en-têtes de la
    sidebar, sans police ni graisse imposées, `.foregroundStyle(.secondary)`
    explicite.
  - **iOS — en-têtes SORTIS de leur bloc, confirmé fluide à l'écran.** Posés
    comme `label:` d'un `DisclosureGroup`, ils restaient une ligne DU bloc
    groupé — même carte blanche que son contenu — au lieu d'un en-tête
    flottant au-dessus, comme sur macOS. `boutonEnTeteBloc(_:ouvert:)` les
    sort dans le vrai `header:` d'une `Section` (rendu par le système EN
    DEHORS de la carte), avec un bouton qui bascule l'ouverture et une
    flèche pivotante à la place du chevron natif ; le contenu du bloc est un
    `if ouvert { … }` portant un `.transition()`.
    - **Deux tentatives ont été nécessaires.** La première combinait DEUX
      causes possibles à une transition « on/off » constatée à l'usage :
      `blocVentesOuvert`/`blocStockOuvert` en `@AppStorage` (voir plus bas,
      section sidebar, pour ce défaut en détail) ET ce même `if` brut,
      qu'une `List` sur iOS n'anime de façon fiable que via un mécanisme de
      diff qu'elle reconnaît (`ForEach` + `onDelete`/`onMove`, ou
      `DisclosureGroup`). Sans savoir laquelle des deux dominait, la première
      tentative avait reverté vers `DisclosureGroup`.
    - **Conclusion établie** : une fois l'état passé en `@State`
      (voir plus bas), le MÊME `header:` + `if` a été retesté et s'anime
      correctement. **`@AppStorage` était bien l'unique cause** — le `if` brut
      n'a jamais posé de problème en lui-même. Ne pas réintroduire
      `DisclosureGroup` ici en le confondant avec cette étape transitoire.
  - **Incohérence corrigée** : les en-têtes de SOUS-groupe (« Catégories »,
    « Modes de vente », « Thèmes ») portaient `.fontWeight(.semibold)`, plus
    lourd que les deux grands en-têtes ci-dessus depuis que ceux-ci ont perdu
    leur graisse — hiérarchie inversée. Alignés sur le même style plat : gris
    (`.foregroundStyle(.secondary)`), sans graisse imposée. Code PARTAGÉ entre
    les deux plateformes (`contenuVentesEtDons`/`contenuStock`, utilisés par
    le `Section(isExpanded:)` macOS ET le `DisclosureGroup` iOS) : le
    correctif s'applique donc aux deux d'un coup, sans code à dupliquer.
    Les trois niveaux de la sidebar se distinguent désormais par
    l'INDENTATION native de la liste, plus par la graisse.
- **iOS — l'app suit PARTOUT la sémantique GROUPÉE : page grise, cartes
  blanches.** Deux couleurs, et deux seulement, portent tous les fonds des
  vues ; elles forment une PAIRE et doivent rester du même jeu.

  | | macOS | iOS (clair) | iOS (sombre) |
  |---|---|---|---|
  | `cremeFond` — la PAGE | `windowBackgroundColor` | **crème fixe** (250,245,235) | noir (`systemGroupedBackground`) |
  | `fondLegende` — la CARTE | `controlBackgroundColor` | `secondarySystemGroupedBackground` (255,255,255) | (28,28,30) |
  | `fondTuile` — la TUILE | `underPageBackgroundColor` | **même crème** (250,245,235) | (44,44,46) (`tertiarySystemGroupedBackground`) |

  - Auparavant, iOS avait l'inverse : page **blanche** (`systemBackground`) et
    cartes **grises** (`secondarySystemBackground`). Les deux valeurs ont été
    strictement échangées, sur le modèle de la sidebar.
  - **Le mode sombre n'a pas bougé** — page noire, cartes gris foncé — les
    variantes groupées et non groupées y ayant les mêmes valeurs. L'inversion
    ne se voit donc qu'en mode clair.
  - **Ne jamais mélanger les deux jeux** : un fond groupé sous une carte non
    groupée (ou l'inverse) donne deux teintes IDENTIQUES, donc une carte
    invisible. C'est exactement ce qui avait rendu la sidebar entièrement
    blanche.
  - Aucune vue ne pose de fond en dur : tout passe par ces deux couleurs, et
    l'inversion s'est donc faite à un seul endroit. Garder cette discipline.
  - `fondGroupe`, créée un temps pour la seule sidebar, a été **absorbée par
    `cremeFond`** : les deux désignaient la même couleur, et deux noms pour une
    même teinte finissent par diverger.
  - **`cremeFond` et `fondTuile` REPASSÉS en crème fixe sur iOS, à la
    demande** (250,245,235 — la teinte du thème d'origine, avant l'adoption
    des couleurs système). Remplace le gris système en mode CLAIR
    uniquement ; le mode sombre garde le fond système (noir / gris foncé
    progressif), non concerné par la demande. `fondLegende` (la carte, en
    blanc) n'est PAS touchée : ce n'est pas un « gris clair », la demande ne
    la visait pas.
    - **Le piège du fond fixe rencontré sur macOS ne s'applique pas ici** :
      il venait de la nécessité de suivre `.windowBackgroundColor` pour
      rester synchronisé avec la toolbar native, une contrainte propre à
      macOS. iOS n'a pas de barre système dont le fond doive suivre
      dynamiquement `systemGroupedBackground` de cette façon.
  - **TROIS niveaux, pas deux** : une tuile posée DANS une carte a son propre
    fond, `fondTuile`. Sans lui, les tuiles de la **Synthèse** étaient
    INVISIBLES : elles utilisaient `fondLegende`, exactement comme la carte qui
    les contient. Le défaut **ne datait pas de l'inversion** — c'était gris sur
    gris avant, blanc sur blanc après ; seule sa couleur a changé.
    - iOS : page (`systemGrouped`, 242) → carte (`secondarySystemGrouped`,
      255) → tuile (`tertiarySystemGrouped`, 242). L'alternance
      clair/blanc/clair est voulue par Apple ; en sombre elle est progressive
      (0 → 28 → 44).
    - **macOS : `windowBackgroundColor` ne convient PAS pour une tuile** — il
      vaut EXACTEMENT `controlBackgroundColor`, celui des cartes (255,255,255
      en clair comme 30,30,30 en sombre). D'où `underPageBackgroundColor`.
    - **Corollaire à connaître** : sur macOS, la page et les cartes ont donc la
      même couleur, et c'est la **bordure orange** de `carte(titre:)` qui les
      sépare — pas un écart de teinte. Retirer cette bordure y ferait
      disparaître les cartes.
    - **CE N'EST PAS UN CAS ISOLÉ À LA SYNTHÈSE — c'est vrai de TOUTE l'app
      sur macOS.** `cremeFond` (`windowBackgroundColor`) et `fondLegende`
      (`controlBackgroundColor`) résolvent **tous deux en BLANC PUR
      (255,255,255)** en mode clair sur macOS 26 — vérifié en rendant
      réellement les deux couleurs dans une `NSWindow` et en lisant le pixel
      obtenu, pas seulement via `resolvedColor` hors contexte de fenêtre (qui
      peut donner une valeur par défaut trompeuse pour une couleur dynamique).
      **Ce n'est pas un bug de l'app, c'est la valeur système actuelle** :
      contrairement aux versions antérieures de macOS, où `windowBackgroundColor`
      était un gris clair distinct des zones de contenu, le langage visuel
      « Liquid Glass » de macOS 26 lui donne un blanc identique.
      - Conséquence : le panneau de contenu (Galerie comprise) paraît
        entièrement blanc, sans le gris de fenêtre traditionnel de macOS. **Ce
        n'est pas une régression** — `cremeFond` fait exactement ce qu'il a
        toujours fait, c'est la couleur système sous-jacente qui a changé.
      - **La Galerie n'est PAS invisible pour autant** : ses vignettes ont
        leur propre filet (`Color.filetVignette`, 1 px) et une ombre portée
        (`shadow`), qui les séparent de la page sans dépendre d'un écart de
        teinte. C'est cette technique — bordure ou ombre, jamais la seule
        couleur — qu'il faut reprendre pour toute future carte macOS, la
        Synthèse le faisant déjà avec sa bordure orange.
      - **Vérifié uniquement sur iOS** que `fondLegende` posé directement sur
        la page donne un contraste réel (blanc sur gris 242) : c'est vrai côté
        iOS, PAS sur macOS, où les deux teintes coïncident. Ne pas généraliser
        l'un à l'autre.
      - **Un essai de valeur FIXE sur `cremeFond` (242,242,247, calée sur le
        gris de page iOS) a été tenté puis REVERTÉ** — voir plus bas, section
        Couleurs : ça cassait la synchronisation avec la toolbar native,
        seule protection contre une VRAIE couture entre barre de titre et
        contenu. `cremeFond` reste donc sur `.windowBackgroundColor`, et le
        blanc sur blanc que ce paragraphe décrit **reste valable**.
- **iOS — sidebar : repeindre le fond d'une liste groupée est DANGEREUX si la
  couleur de repeint peut un jour coïncider avec celle des blocs.**
  `.insetGrouped` distingue DEUX fonds — la vue en `systemGroupedBackground`,
  les blocs en `secondarySystemGroupedBackground` (blanc en clair) — et c'est
  cet écart, et lui seul, qui détache visuellement les blocs.
  - **Épisode 1 — RETIRÉ.** La sidebar portait `.scrollContentBackground
    (.hidden)` + `.background(Color.cremeFond)`, hérité du thème crème.
    Après le passage aux couleurs système, `cremeFond` valait
    `systemBackground`, donc BLANC — identique aux blocs. **Toute la sidebar
    devenait uniformément blanche.** Retiré, style natif laissé faire.
  - **Épisode 2 — REVENU, volontairement.** `cremeFond` a désormais sa propre
    valeur crème fixe sur iOS (250,245,235 en clair — voir sa définition,
    section Couleurs), genuinement distincte du blanc des blocs. La
    condition dangereuse de l'épisode 1 n'est plus réunie : l'override peut
    revenir sans risque, et sert désormais à donner à la PAGE de la sidebar
    la même teinte crème que le reste de l'app, au lieu du gris système.
  - **Leçon générale** : ce n'est pas l'override en lui-même qui est fautif,
    c'est de repeindre avec une couleur dont la valeur peut, à l'insu de
    cette vue, finir par coïncider avec celle des blocs. Avant de repeindre
    le fond d'une liste groupée, vérifier que la couleur utilisée reste
    structurellement distincte de `fondLegende` (la carte) — pas seulement
    au moment où le code est écrit.
  - Le fond de la COLONNE (hors liste) utilise directement `Color.cremeFond`
    depuis que `fondGroupe`, qui portait cette valeur avant, en a été
    absorbée — les deux étaient devenues la même couleur.
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
  - **Tooltips (`.help(...)`)** : Galerie, Liste et Ajouter (« Ajouter une
    œuvre ») en ont désormais un, comme les autres boutons de la toolbar —
    ils n'affichent qu'une icône, sans info-bulle rien ne disait leur nom au
    survol. Le menu de filtre par Support (`menuFiltreType`) avait le sien
    depuis le début, mais disait encore « Filtrer par type » ; renommé
    « Filtrer par support » pour suivre le libellé affiché partout ailleurs
    (Type → Support). Seul CE texte change — le champ `type` et les noms de
    fonctions (`filtrerParType`…) gardent leur ancien nom, comme pour le
    reste du renommage Type/Thème → Support/Genre.
  - **Bouton Galerie AVANT Liste**, dans les cinq endroits qui proposent ce
    choix (toolbar macOS, menu Présentation, et les trois barres d'outils
    iOS) : Galerie est la présentation par défaut à la première ouverture
    d'une rubrique (`modeAffichage = "icone"`, une seule clé partagée par
    toute l'app). Une fois changé, le choix reste mémorisé jusqu'au prochain
    changement — comme avant, seul le défaut et l'ordre d'affichage bougent.
  - **Bouton de corbeille retiré de la toolbar** (essai devenu définitif) :
    la commande « Supprimer » du menu Édition déclenche la même
    confirmation, et est seule voie pour supprimer depuis Galerie et Liste.
    Le drapeau `afficherBoutonCorbeilleToolbar` et son `if`, qui gardaient le
    bouton en réserve, sont **supprimés** (audit de code, 30 août 2026) —
    `labelSupprimer`, qui ne servait qu'à son libellé (« Supprimer (3) »),
    est parti avec.
  - **Bouton de masquage des prix retiré de la toolbar** (même sort, même
    date) : la commande « Masquer les prix » / « Afficher les prix » du menu
    Présentation reste seule voie de bascule, elle pilote le MÊME
    `prixMasques` et n'était pas concernée par le drapeau
    `afficherBoutonPrixToolbar`, supprimé avec son `if`.
  - **Bouton « Ajouter » piloté par `Categorie.feuilleAjout`, distinct de
    `feuille`.** `feuille` filtre les données ; `feuilleAjout` dit dans
    quelle feuille créer une œuvre, et vaut `nil` = pas de bouton. Une
    rubrique déjà filtrée par type ou par thème (Supports de Ventes et dons,
    Collection personnelle, Genres, Supports de Réserve, Favoris)
    n'en a plus : une œuvre créée sans ce critère y serait invisible
    aussitôt. Catalogue de « Ventes et dons » en gagne un — vue agrégée
    sans feuille propre, il cible « Tableaux vendus », le défaut du modèle
    lui-même (`Oeuvre.feuilleBrute`).
  - **ESSAI VISUEL — le libellé d'une pastille de filtre retenue reste en
    graisse normale**, sur les deux plateformes (pastille de type, de
    vendeur, `BandeauTypes` iOS) : seuls le fond plein et le texte blanc
    marquent désormais la sélection.
- **ESSAI VISUEL — les vignettes de Galerie perdent le gras de leur ligne de
  nom** (acheteur, destinataire, ou emplacement en Réserve). `.font(.headline)`
  garde sa TAILLE (13/17 pt selon la plateforme), seule sa graisse par défaut
  est neutralisée via `.fontWeight(.regular)`. **TROIS vignettes distinctes à
  tenir d'accord** — chacune a son propre rendu, aucune n'est partagée :
  `VueGalerie.swift` (macOS ET iOS, via `VueFeuille`/`VueiOS`),
  `VueOeuvresStructuree.swift` (Catalogue/Ventes/modes de vente sur iPhone),
  `VueDonsStructuree.swift` (Dons sur iPhone).
  - **Étendu au mode LISTE des mêmes vues iOS**, sur demande : `VueiOS.swift`
    (Réserve/type/Favoris), `VueOeuvresStructuree.swift` et
    `VueDonsStructuree.swift` ont chacune une seconde ligne `.headline` dans
    leur `listeLignes`, distincte de celle de leur vignette de Galerie —
    même correctif, même `.fontWeight(.regular)`, à répéter aux DEUX endroits
    de chaque fichier.
  - **macOS n'a rien de comparable** : le mode Liste y est un `Table`
    (`VueFeuille.swift`), qui ne pose `.headline` sur aucune cellule — les
    deux occurrences trouvées dans ce fichier sont un bandeau éphémère et un
    titre de boîte de dialogue, sans rapport avec une ligne de liste.
- **macOS — menu Édition : Select All / Delete / Undo / Redo remplacés,
  Couper/Copier/Coller recréés** (`PierreVincentApp.swift`).
  `CommandGroup(replacing: .pasteboard)` prend la main sur le bloc standard
  Cut/Copy/Paste/Delete/Select All : les versions par défaut de Select All
  et Delete restaient GRISÉES, visant le premier répondant — que ni la
  sélection de `VueFeuille` (un `@State`, pas un `NSResponder`) ni la
  suppression confirmée n'utilisent.
  - **`champTexteFocalise`** (`@AppStorage`, remonté par le `@FocusState`
    existant de `EditeurEntree`) dit si un champ de texte a le focus. Il
    pilote la bascule de CINQ commandes :
    - **Couper/Copier/Coller** : cible `nil` (`NSApp.sendAction(_:to: nil,
      from: nil)`), le mécanisme standard par lequel un champ de texte les
      traite déjà — jamais de problème de chaîne de répondants ici,
      contrairement à Select All/Delete. Grisées hors d'un champ focalisé
      (`!champTexteFocalise`) ; limite acceptée, elles ne se grisent pas
      selon la granularité fine de Cocoa (présence d'une sélection).
    - **Tout sélectionner** : dans un champ, cible `nil` (sélectionne le
      TEXTE, action native) ; sinon, déclenche `selectionnerTout()` — la
      sélection des lignes de `VueFeuille`. Grisée seulement si l'éditeur
      est ouvert SANS champ focalisé, cas où rien n'a de sens à
      sélectionner. **Erreur commise puis corrigée** : la griser dès que
      l'éditeur est ouvert, sans le test de focus, la rendait inerte y
      compris EN TRAIN de taper.
    - **Annuler / Rétablir** : cible `GestionAnnulation.shared.undoManager`
      (les suppressions SwiftData) hors d'un champ, mais `nil` (l'action
      standard `undo:`/`redo:`) DANS un champ. **Bug corrigé** : le
      remplacement visait ce gestionnaire SANS CONDITION, et ⌘Z ne pouvait
      donc jamais défaire une frappe corrigée dans l'éditeur — le
      gestionnaire SwiftData n'a rien enregistré de la saisie.
      `#selector` ne peut pas viser `undo:`/`redo:` (non déclarés côté Swift
      sur `NSResponder`) : sélecteur construit à la main, `Selector(("undo:"))`.
- **iOS — pastille « Import en cours »** (`PastilleImportBase.swift`), même
  mécanisme de fenêtre à part que le masquage des prix (`PastillePrix.swift`)
  mais SANS minuteur : elle reste tant que l'import dure, pas une durée fixe.
  `gererImportBase` l'affiche puis lance l'import sur le tour de boucle
  suivant (`DispatchQueue.main.async`), pour que la pastille ait le temps de
  se peindre avant que l'import — synchrone et parfois long sur une grosse
  base — ne bloque le fil principal.
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
- **Sidebar — DÉROGATION assumée : aucune mémoire entre les sessions.**
  Une sidebar système mémorise ses blocs repliés ; celle-ci non. Les six
  états d'ouverture (`blocVentesOuvert`, `blocStockOuvert` et les quatre
  sous-groupes) sont de simples `@State` dans `ContentView`, avec pour
  défaut les deux grands blocs dépliés et les QUATRE sous-groupes repliés
  (les deux « Catégories », « Modes de vente », « Thèmes »). L'ouverture
  montre ainsi les seules vues d'ensemble, six rubriques au lieu d'une
  vingtaine. Un `@State` n'a pas de mémoire d'une session à l'autre par
  construction : les replis faits à la main ne valent donc que pour la
  session, sans rien à écrire nulle part.
  - **Ce n'est pas un oubli, ne pas « réparer »** en remettant la
    mémorisation. Décision prise le 22 août 2026.
  - **Étaient en `@AppStorage` au départ**, avec une réécriture des six clés
    à chaque lancement (`PierreVincentApp.arrangerSidebar()`, depuis
    supprimée) — un défaut de `@AppStorage` ne s'applique qu'à une clé
    **absente**, or ces clés existaient déjà sur toute installation ayant
    servi, d'où la réécriture systématique.
  - **Passées en `@State` pour une tout autre raison** : `DisclosureGroup`
    n'animait pas l'ouverture/fermeture des blocs malgré son animation
    native habituelle — une mutation `@AppStorage` passe par `UserDefaults`,
    dont la notification de changement n'arrive pas toujours dans la même
    transaction qu'un `withAnimation`. Une fois établi que la persistance ne
    servait déjà à rien au-delà de la session, le `@State` s'est imposé : il
    anime de façon fiable ET retombe naturellement à sa valeur par défaut à
    chaque lancement, l'un réglant l'autre.
  - L'`init` de `PierreVincentApp` reste hors du bloc `#if os(macOS)` (utile
    aux deux plateformes), mais ne fait plus que la ligne AppKit
    (`allowsAutomaticWindowTabbing`), gardée à l'intérieur de son propre
    `#if`.
- **Structure de la sidebar** (`ContentView.swift`, enum `Categorie`),
  identique sur les deux plateformes :

  ```
  ▼ VENTES ET DONS               ▼ RÉSERVE
       Catalogue                      Catalogue
     ▼ Supports                       Collection personnelle
          Tableaux                  ▼ Genres
          Dessins                        …déduits des données
          Tapis                     ▼ Supports
       Ventes                            Tableaux
     ▼ Modes de vente                    Dessins
          Expositions
          Ventes aux enchères           Favoris
          Vente privée
          …tout mode inédit
       Dons
       Synthèse
  ```

  - **« Supports » et « Genres »** sont les libellés de sidebar — le champ
    sous-jacent (`type`, `theme`) et les fonctions qui s'y rapportent
    (`themesPresents`…) gardent leur ancien nom, « Catégories » et
    « Thèmes » n'étaient que le texte affiché ici.
  - **Genres avant Supports dans la Réserve**, l'inverse de « Ventes et
    dons » : c'est le genre (thème) qui range les cartons. `categoriesSidebar`
    doit suivre le MÊME ordre, sans quoi ↑↓ sauterait d'une rubrique à l'autre
    dans un ordre que rien à l'écran n'explique.
  - **Ordre de « Ventes et dons »** : Catalogue, Supports, Ventes, Modes de
    vente, Dons, Synthèse — les deux sous-groupes s'intercalent entre les
    rubriques de premier niveau, ils ne sont plus regroupés à la fin.
    `categoriesSidebar` suit ce même ordre pour la navigation ↑↓.
  - **Favoris est une rubrique ISOLÉE**, dans sa propre section sans en-tête
    ni repli, détachée des deux blocs : un favori pourra venir de l'un comme
    de l'autre. Elle ne dépend d'aucun repli.
    - **N'apparaît que s'il existe au moins un favori** (`auMoinsUnFavori`,
      partagée entre les deux plateformes) : sur les DEUX `Section` de la
      sidebar (macOS et iOS) ET dans `categoriesSidebar`, sans quoi ↑↓
      mènerait à une rubrique invisible à l'écran. Propriété volontairement
      posée EN DEHORS du bloc `#if os(macOS)` de `categoriesSidebar`, pour
      rester utilisable par le rendu iOS aussi.
    - **Le champ `Oeuvre.favori` existe désormais** (Bool, défaut `false`,
      exporté en optionnel dans `.pvbase` comme tout champ ajouté après coup).
      La rubrique est donc passée d'une coquille vide à une VUE AGRÉGÉE
      (`feuille` vaut `nil`, comme Catalogue) — l'étape que la note
      précédente annonçait comme « à revoir le jour où le champ existera ».
    - **`correspond(favoriSeul:)`** court-circuite le test de statut quand il
      est actif : un favori peut être vendu, donné ou encore en réserve, et
      la rubrique n'a donc aucune liste de statuts à faire valoir — seul
      `o.favori` compte. `Categorie.favoriSeul` (vrai pour `.favoris` seul)
      le pilote, sur le même patron que `collectionSeule`.
    - **Bascule via le menu contextuel iOS** (`InteractionApercu` dans
      `TransitionVisionneuse.swift`, donc les trois vues qui le partagent) :
      l'entrée « Ajouter aux favoris » n'était plus inerte, elle devient
      « Retirer des favoris » une fois l'œuvre favorite — libellé et icône
      recalculés à CHAQUE ouverture du menu, jamais périmés. L'œuvre reste à
      SA place d'origine ; elle apparaît EN PLUS dans Favoris, sans y être
      déplacée ni dupliquée.
      **Bascule aussi depuis macOS** désormais : menu contextuel de la
      `Table` (liste — `menuContextuel`, partagé par les trois feuilles) et
      de `VueGalerie` (`#if os(macOS)` seul, sans toucher iOS), plus une
      commande dédiée du menu Édition. Les trois libellés suivent la MÊME
      convention sur une sélection multiple : si au moins une œuvre visée
      n'est pas favorite, « Ajouter aux favoris » les marque TOUTES ; si
      toutes le sont déjà, « Retirer des favoris » les démarque toutes —
      jamais un simple `.toggle()` par œuvre, qui mélangerait les états.
      `VueFeuille.basculerFavoriSelection()` est le point de passage unique
      pour la Table et le menu Édition ; `VueGalerie` calcule sa propre
      version localement (une cible de clic droit peut différer de la
      sélection remontée au menu Édition).
    - **Menu contextuel de la Table (liste, macOS)** — celui qui sert aussi
      Modifier/Dupliquer/Supprimer, voir plus bas — propose désormais
      « Supprimer… » (avec les points de suspension, une confirmation
      suivant) et la bascule des favoris, dans TOUTES les vues en
      présentation Liste. Sur iPhone, le menu de la pression longue ne porte
      QUE la bascule des favoris — pas de Modifier/Supprimer, l'app restant
      en lecture seule côté édition sur cette plateforme.
    - **ESSAYÉ ET ABANDONNÉ — double-tap sur une vignette/ligne pour
      basculer le favori**, comme alternative au menu contextuel iOS.
      Techniquement, la bonne méthode UIKit a été posée : un second
      `UITapGestureRecognizer` (2 taps) avec `tap.require(toFail:
      doubleTap)` sur le premier, exactement le mécanisme qui fait
      normalement attendre le tap simple. **Constaté à l'usage : ça ne
      marchait pas** — le tap simple continuait d'intercepter la commande
      avant qu'un second ait pu être reconnu. Revert complet (`InteractionApercu`
      revient à tap simple + menu contextuel seul, les lignes de liste
      retrouvent leur `Button` d'origine, `InteractionListeFavori` supprimé).
      Ne pas retenter cette même piste sans en comprendre la cause exacte.
    - Ses pastilles de type passent à TROIS (comme Catalogue), et non plus
      les deux de la Réserve : un tapis peut être favori.
      **Sur iPhone, elles sont en outre réellement PRÉSENTES** — la seule
      rubrique où `typesFiltre` cède la place à une liste déduite des
      données (`typesFiltreAffiches` dans `VueiOS.swift`), calculée AVANT
      le filtre de type actif, sur le même principe que les vendeurs
      déduits. Sans favori d'un type donné, sa pastille n'apparaît pas.
    - **Aucun récapitulatif ni menu/bouton de tri sur iPhone ni sur Mac** :
      un critère commun (prix, acheteur…) n'a pas de sens sur un mélange de
      vendus/donnés/réservés. Galerie et Liste restent les seules
      présentations.
    - **Vide, elle affiche un état DISCRET** à la place de la galerie/liste
      (`VueiOS.swift`), et masque pastilles et compteur du même geste (ils
      dépendent tous deux de la présence réelle de favoris). **PAS de
      `ContentUnavailableView`** — essayé, son icône par défaut est bien
      plus grosse qu'une icône de sidebar et le rendu se lisait comme une
      alerte plutôt qu'un simple vide. Un `VStack` maison reprend la même
      taille d'icône que la sidebar (`.font(.body)`, aucune taille imposée),
      le même corps que les libellés de rubrique, en gris (`.secondary`).
    - **Suppression des favoris : une icône de corbeille dans la toolbar**,
      tout à droite, seulement s'il existe au moins un favori — et non un
      gros bouton en pied de galerie/liste, essayé puis retiré à la demande
      (jugé trop voyant). `VueGalerie` garde son paramètre `piedDePage`
      (nul ici désormais, encore utile ailleurs au besoin).
      Confirmation par **`.alert`, et non `.confirmationDialog`** : ce
      dernier s'affiche en feuille au bas de l'écran (le style d'un menu
      d'action), alors qu'une alerte standard apparaît au centre. Démarque
      TOUS les favoris de l'app, quel que soit le filtre de type actif —
      « Supprimer » désigne la mise en favori, pas les œuvres, qui ne sont
      jamais effacées.
    - Le bouton « Ajouter » en est retiré (voir `feuilleAjout` ci-dessous) :
      une vue agrégée n'a pas de feuille cible unique où créer une œuvre.

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
  - **Les icônes sont des SF Symbols, réunies dans `Categorie.symbole`** — un
    seul endroit pour les deux plateformes : la branche macOS de `lien()`
    construit un `HStack` (pour placer la pastille à droite) et la branche iOS
    un `Label`, mais toutes deux affichent `Image(systemName: cat.symbole)`.
    En vigueur : `photo.artframe` (les deux Catalogue), `paintpalette`
    (Tableaux), `pencil.and.outline` (Dessins), `square.grid.3x3.square`
    (Tapis), `gift` (Dons), `creditcard` (Ventes), `cart` (tout mode de
    vente), `person` (Collection personnelle), `paintbrush.pointed` (tout
    thème), `chart.bar.doc.horizontal` (Synthèse).
    Les cas à valeur associée n'ont qu'une branche : un mode ou un thème
    inédit reçoit son icône sans rien à ajouter.

- **Réserve › Catégories : Tableaux et Dessins**, pendants exacts l'un de
  l'autre — seul leur `types` diffère (`["Tableau"]` / `["Dessin"]`). Le
  statut « Disponible » ne leur est PAS écrit en dur : il vient de
  `statutsReserve`, comme à toute la section. Leur `feuille` valant
  `.reserve`, elles héritent sans rien ajouter de l'absence de prix, de menu
  de tri et de bouton de masquage.
  - Ajouter une rubrique demande **dix points de branchement** dans
    `ContentView.swift`, dont deux qui s'oublient : `categoriesSidebar`, sans
    quoi la navigation clavier ↑↓ saute la rubrique, et la liste des
    **pastilles de comptage**, dont l'écart avec la vue avait déjà produit un
    « 9 » au-dessus d'une rubrique vide.
  - `typesFiltre` y reste **vide** : filtrer par type une rubrique déjà
    filtrée par type n'aurait pas de sens.

- **Sous-catégories dynamiques par thème, dans la Réserve**
  (`ContentView.swift`, cas `reserveTheme(String)`) : même principe que les
  modes de vente ci-dessous — `themesPresents` déduit les rubriques des
  données, en écartant les vides et « Inconnu ».
  - Le balayage ne porte QUE sur les œuvres de la Réserve : un thème
    n'existant que sur une œuvre vendue aurait sinon sa rubrique ici,
    systématiquement vide.
  - Le filtre passe par un paramètre `themes` ajouté à `correspond`, donc au
    même endroit que ceux par statut et par type — ce qui le fait reprendre
    tel quel par les pastilles de comptage et la navigation clavier.
  - Ces vues reprennent l'interface des Dons : pastilles Tableaux / Dessins et
    compteur, pas de masquage des prix. Le menu de critère en est absent sans
    rien ajouter, la feuille étant `.reserve`.
  - Libellés **mis au pluriel à l'affichage** (« Natures mortes »,
    « Paysages », « Bouquets », « Portraits ») ; la valeur stockée reste au
    singulier, et c'est elle que voient l'éditeur, l'inspecteur et le filtre.
- **Sous-catégories dynamiques par mode de vente** (`ContentView.swift`) :
  le groupe « Modes de vente » n'est **pas déclaré** — il est déduit des
  données par `modesDeVentePresents`. Un mode inédit crée sa rubrique dès
  qu'une œuvre le porte, et elle disparaît quand plus aucune ne l'a. Les modes
  de `modesDeVenteReference` gardent leur ordre, les inédits suivent par ordre
  alphabétique ; les valeurs vides, « Inconnu » et « Don » sont écartées.
  - Rendu possible par `case modeVente(String)`, un cas **à valeur associée**.
    `Categorie` a donc dû perdre `CaseIterable`, incompatible — sans
    conséquence, `allCases` ne servait qu'à du code mort.
  - **Icône sur l'en-tête du sous-groupe : ESSAYÉE PUIS RETIRÉE** —
    `Label("Modes de vente", systemImage: "cart")` à la place d'un `Text`
    nu, le temps d'un aller-retour. Revenu à `Text("Modes de vente")` :
    les en-têtes de sous-groupe restent du texte nu partout (« Supports »,
    « Genres »), pas d'exception ici.
  - **Icône des rubriques individuelles : `cart` → `bag`**, à la demande
    (`Categorie.symbole` pour `.modeVente`). Chaque mode de vente
    (Expositions, Ventes aux enchères, Directe, tout mode inédit) porte
    cette icône, le cas étant à valeur associée — une seule branche pour
    tous.
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
  - **« Vente privée » s'affiche « Directe »**, même principe que les deux
    précédents : `titre` traduit, `modeVente` sur l'œuvre et
    `modesDeVenteReference` restent « Vente privée ». Y toucher romprait la
    reconnaissance des œuvres déjà classées dans ce mode.
- **Sous-groupe « Supports » de « Ventes et dons » : rétabli, APLATI sur
  macOS, puis SUPPRIMÉ sur iOS — n'existe plus sur AUCUNE des deux
  plateformes.** D'abord rétabli comme sous-groupe repliable après l'essai
  qui le masquait, puis aplati sur macOS (Tableaux/Dessins/Tapis au MÊME
  NIVEAU que Catalogue, sans en-tête « Supports » ni repli), et enfin retiré
  purement et simplement d'iOS : la vue Catalogue y offre déjà le même
  filtre par type (bandeau de pastilles), la sous-rubrique de sidebar faisait
  double emploi. `contenuVentesEtDons` (`ContentView.swift`) n'a donc plus
  qu'une seule forme, sans branche `#if os` — `lien(.oeuvres)` puis
  `lien(.oeuvresDonnees)` directement, sur les deux plateformes.
  `sousBlocCategoriesOuvert` (l'état de repli qu'utilisait le
  `DisclosureGroup` iOS) est supprimé, n'ayant plus aucun appelant.
  `categoriesSidebar` (navigation clavier macOS) suit : `.tableauxVendus/
  .dessinsVendus/.tapisVendus` y sont ajoutés sans condition, il n'y a plus
  de repli à tester pour eux.
  - **Ces trois rubriques restent des `Categorie` valides**, seulement
    retirées de la NAVIGATION de sidebar — sur iPhone, il n'existe plus de
    chemin pour y accéder directement en dehors du filtre de Catalogue.
  - **Celui de la RÉSERVE reste MASQUÉ, essai en cours, DEUX plateformes**
    (`afficherSupportsSidebarReserve` dans `TriEtTotaux.swift`) : les deux
    occurrences partageaient à l'origine un seul drapeau
    (`afficherSupportsSidebar`) ; rétablir Ventes et dons sans toucher à la
    Réserve a demandé de le renommer et de le restreindre à cette seule
    section. Code conservé, `true` restaure celui de la Réserve.
    `categoriesSidebar` (navigation clavier macOS) ne propose plus ses
    rubriques (Tableaux/Dessins de la Réserve) tant que le drapeau est à
    `false` — sans ce garde-fou, ↑↓ aurait pu s'arrêter sur une rubrique
    invisible à l'écran.
- **Ordre de « Ventes et dons » : Dons remonté AVANT Ventes et Modes de
  vente**, sur les DEUX plateformes — Catalogue, (Supports), **Dons**,
  Ventes, Modes de vente, Synthèse. `contenuVentesEtDons` (ordre partagé
  macOS/iOS) et `categoriesSidebar` (navigation clavier macOS) suivent tous
  deux ce nouvel ordre.

- **iOS — pas de récapitulatif dans Ventes ni dans Dons** : leur seule ligne
  (« Nombre de ventes », « Nombre de dons ») annonçait un nombre que le
  compteur du bandeau de pastilles donne déjà, à côté. Le bandeau devient le
  premier élément et porte ses propres 8 pt en haut, ceux qu'avait le
  récapitulatif.
  - Dans Ventes, le retrait est conditionné à la **présence du bandeau**
    (`estModeVentes && !typesFiltre.isEmpty`) et non au seul mode Ventes : les
    sous-rubriques de mode de vente partagent cette vue avec le même
    `estModeVentes`. Elles n'avaient pas de pastilles quand la règle a été
    écrite — elles en ont depuis, et perdent donc leur ligne elles aussi.
  - **Dans Catalogue, les capsules sont AU-DESSUS du récapitulatif** : le
    filtre d'abord, ce qu'il donne ensuite. Le récapitulatif porte depuis lors
    sa propre marge basse, que le bandeau lui donnait tant qu'il le suivait —
    encore un cas de marge tenue par le voisin.
  - **Compteur du bandeau aligné avec les nombres du récapitulatif, dans
    Catalogue seulement** : `BandeauTypes.paddingCompteur` (nouveau
    paramètre, défaut 12 — la valeur d'origine) contrôle la marge horizontale
    du compteur, donc où tombe son bord droit. Catalogue passe 20, pour que
    ce bord tombe exactement sur celui des nombres de `ligneRecap` juste en
    dessous (16 pt de marge de carte + 20 pt de padding de ligne = 36 pt
    depuis le bord de l'écran, contre 16 + 12 = 28 pt sans ce réglage).
    Réserve et Dons, seules autres vues à utiliser `BandeauTypes`, n'ont pas
    de second nombre à aligner en dessous et gardent le défaut.
  - **« Ventes » et « Dons » en style NORMAL dans Catalogue seulement**
    (`ligneRecap(gras:)`) : `estModeVentes` vaut `false` pour Catalogue, donc
    `gras: false` s'y applique aux deux lignes (intitulé et compteur) — la
    ligne « Dons » n'existe d'ailleurs QUE là, elle ne s'affiche jamais pour
    une sous-rubrique de mode de vente. « Nombre de ventes », affichée dans
    Ventes et ses sous-rubriques (`estModeVentes` vrai), garde son gras
    d'origine — `gras: estModeVentes` au premier appel le distingue du
    second, où `false` est fixe puisque cette ligne n'a qu'un seul contexte.
- **iOS — le récapitulatif défile avec le contenu** dans toutes les vues.
  Placé au-dessus du `ScrollView` (ce qu'il était dans `VueiOS`), il restait
  ancré et la barre de navigation ne prenait pas sa transparence. En mode
  galerie, `VueGalerie` étant partagée avec macOS et ayant son propre
  `ScrollView`, elle reçoit un paramètre `entete` **optionnel** rendu dans la
  zone de défilement — nul côté Mac, où rien ne change.

- **iOS — Catalogue, bouton flottant « Retour en haut »**
  (`VueOeuvresStructuree.swift`) : une pastille ronde à fond OPAQUE (accent
  de la rubrique) et flèche BLANCHE (`arrow.up`), survole le contenu
  (`.overlay` sur le `ScrollView`, PAS dans la hiérarchie défilante).
  Apparaît après un défilement de deux fois la hauteur visible
  (`.onScrollGeometryChange`, iOS 18+), via `boutonHautVisible`. Ramène tout
  en haut par `proxy.scrollTo(ancreHaut, anchor: .top)`, une ancre invisible
  posée en tête du `VStack` défilant.
  - **Fond TRANSPARENT essayé d'abord, ABANDONNÉ** : premier essai à
    contour seul, jugé trop peu visible et repositionné trop bas. Passé à un
    disque plein (couleur `accentRubrique`) avec une ombre portée, pour
    rester lisible par-dessus des vignettes de toutes teintes.
  - **Position calculée, pas un simple padding depuis un coin** : le bouton
    doit tomber exactement à la limite haute du TIERS BAS de l'écran, pas à
    une marge fixe. Un `GeometryReader` posé dans l'`.overlay` lit la
    hauteur du `ScrollView`, et `.position(x:, y: hauteur * 2/3)` place le
    bouton à cette hauteur précise, ancré près du bord droit sur `x`. Les
    anciens `.padding(.trailing/.bottom)` sur le bouton lui-même ont été
    retirés : ils entraient en conflit avec ce calcul de position.
  - **Restreint au Catalogue** (`!estModeVentes`) : Galerie et Liste
    partagent le même `ScrollView` dans cette vue, donc la même condition
    couvre les deux présentations d'un coup. Les sous-rubriques de mode de
    vente (`estModeVentes` vrai), qui réutilisent cette même vue, n'ont pas
    ce bouton.
  - **Apparition animée** : `boutonHautVisible` est désormais posé dans un
    `withAnimation(.easeOut(duration: 0.25))`, sans quoi le `.transition`
    posé sur le bouton ne jouait pas (une transition n'anime que si le
    changement de présence a lieu dans une transaction animée). Le fondu
    seul (`.opacity`) a été remplacé par un zoom léger depuis le centre
    combiné au fondu (`.scale(scale: 0.7).combined(with: .opacity)`), plus
    fluide qu'un simple fondu sec.
  - **`DesactiveDelaiDefilement` (UIViewRepresentable)** : sans elle, le
    bouton ne réagissait qu'à un second tap tant que le `ScrollView`
    défilait encore — UIKit absorbe le premier tap pour arrêter le
    défilement avant de le transmettre au bouton en overlay. Ce composant
    désactive `delaysContentTouches` sur le `UIScrollView` le plus proche,
    remonté DE PROCHE EN PROCHE depuis une vue invisible posée en
    `.background` du `ScrollView` — pas de recherche par classe depuis la
    racine de la fenêtre, méthode qui a déjà cassé d'autres vues par le
    passé (voir plus haut, l'incident `DefilementTableau`/`NSOutlineView`).
  - **ESSAI — bouton JUMEAU translucide, tout à gauche, pour comparer les
    deux styles** : `boutonRetourHaut(proxy:opaque:)` prend un booléen de
    style. `opaque: false` donne un fond translucide — **le MÊME rendu que
    les boutons standards de retour en arrière déjà dans l'app** (cercle
    sombre `black.opacity(0.55)` cerclé de l'accent de la rubrique, voir
    `VisionneuseOeuvres.boutonFermer` / `VisionneuseImagePleinEcran`), pas
    un `.ultraThinMaterial` inventé pour l'occasion — au lieu du disque
    plein accent. **Flèche BLANCHE dans les deux styles**, `opaque` ne
    change que le fond. Posé au même niveau vertical (`y: hauteur * 2/3`)
    mais collé au bord GAUCHE (`x: 20 + 22`, symétrique du bouton de
    droite). Même action, même geste — un pur essai visuel, à retirer une
    fois le style tranché entre les deux.
  - Teinté par `\.accentRubrique` (orange dans « Ventes et dons »), comme le
    reste des contrôles de cette section.

- **Piège : `init` explicite et initialiseur mémberwise.** `VueiOS` et
  `VueOeuvresStructuree` en déclarent un ; ajouter une propriété ne suffit
  donc PAS à pouvoir la passer à l'appel, il faut aussi étendre l'`init`.
  Rencontré deux fois.

- **Couleurs standard de l'interface** (`Couleurs.swift`, `ContentView.swift`) :
  les fonds auparavant crème utilisent désormais les fonds système macOS et
  iOS. Les sélections personnalisées des sidebars ont été retirées afin de
  laisser les deux systèmes afficher leur sélection bleue native ; la
  sélection marron de la sidebar macOS n'est donc plus utilisée. Les couleurs
  orange international et bleu ardoise sont conservées pour les éléments
  d'interface qui les utilisent déjà : icônes, pastilles, compteurs, contours
  et filets. L'icône de la rubrique Favoris est jaune sur les deux plateformes.

- **macOS — premier répondant des vues Liste** (`VueFeuille.swift`) : la
  sélection bleue native pouvait devenir grise après un changement de
  rubrique, car le `NSTableView` partagé restait un tableau sélectionné mais
  inactif. `ForceSelectionBleueTableau` réimpose `selectionHighlightStyle =
  .regular` et rend le tableau de contenu premier répondant dès qu'un clic est
  effectué dans ses limites. Le correctif ne touche pas la sidebar, dont la
  sélection marron personnalisée reste inchangée.

- **macOS — sélection bleue des vues Liste** (`VueFeuille.swift`) : la couleur
  de fond de sélection reste celle de la `Table` native de macOS, donc bleue,
  dans toutes les rubriques et quel que soit l'ordre d'ouverture. Le composant
  `ForceSelectionBleueTableau` réimpose `selectionHighlightStyle = .regular`
  après chaque mise à jour du tableau partagé. Le marron personnalisé de la
  sidebar n'est pas modifié. Sur la ligne sélectionnée, les cellules textuelles
  et le prix restent blancs et gras pour assurer la lisibilité.

- **macOS — lisibilité de la sélection dans les tableaux** (`VueFeuille.swift`) :
  la sélection de la `Table` reste la sélection bleue native de macOS. Dans les
  trois tableaux — Ventes, Dons et Réserve — le texte de toutes les cellules de
  la ligne sélectionnée passe en blanc et en gras. Le prix suit la même règle ;
  hors sélection, il conserve la couleur d'accent de la rubrique. Le style est
  centralisé dans `TexteLigneSelectionnee`, afin que les trois tableaux restent
  cohérents.

- **Favoris — accent TAUPE CHAUD** (`Couleurs.swift`, `ContentView.swift`) :
  `Color.taupeChaud`, (125, 106, 88) en clair, éclairci en sombre. Il remplace
  le jaune, qui n'a plus aucune occurrence dans le code. Il s'applique à
  l'icône de la sidebar, au fond du compteur de la sidebar, au compteur de la
  vue et aux trois pastilles de type. Le bleu ardoise reste l'accent des
  autres rubriques de la Réserve.
  - **TROIS accents cohabitent donc**, et non deux : orange (« Ventes et
    dons »), bleu ardoise (« Réserve »), taupe (Favoris). Favoris est une
    rubrique ISOLÉE, qui n'appartient à aucune des deux sections — sa teinte
    propre le dit.
  - **La valeur claire est contrainte par la pastille de comptage**, qui pose
    du texte BLANC sur un fond plein de cette teinte. (125, 106, 88) donne
    5,15:1, au-dessus du seuil AA ; (138, 118, 98), essayé d'abord, tombait à
    4,33:1. Ne pas éclaircir ce taupe sans refaire ce calcul — c'est le même
    écueil qui avait fait écarter la plus claire des deux nuances de sélection
    de sidebar macOS.
  - **Une seule source** : `Categorie.accent`. Les deux tests
    `cat == .favoris ? Color.yellow : …` qui traînaient dans `lien()` ont
    disparu — celui d'iOS était même redondant, `accent` renvoyant déjà cette
    teinte. Seul subsiste, côté macOS, le test qui fait garder à Favoris SA
    couleur quand la rubrique est sélectionnée, là où les autres passent au
    blanc ; il passe désormais par `cat.accent`, donc la teinte se change à un
    seul endroit.

- **Accent système et Synthèse** (`project.pbxproj`, `Couleurs.swift`,
  `VueSynthese.swift`) : le projet ne déclare plus le catalogue `AccentColor`
  vide comme accent global, afin que la sidebar macOS utilise l'accent choisi
  dans les réglages système, y compris après relance. Les fonds des tuiles de
  Synthèse utilisent le fond secondaire standard gris (`fondLegende`), tandis
  que le fond général reste le fond système.

- **Sidebar macOS — sélection native active** (`ContentView.swift`) : la
  sélection grise observée dans la sidebar correspond à la sélection native
  inactive de macOS, et non à une couleur personnalisée. Le composant
  `ActiveSidebarSelection` réactive le `NSOutlineView` de la sidebar uniquement
  lorsqu'une rubrique change, afin que la couleur d'accent choisie dans les
  réglages système soit affichée. Il ne doit pas reprendre le focus pendant
  les mises à jour du tableau central.

- **Générateur de données et d'images de test supprimé** (`DonneesTest.swift`,
  `ContentView.swift`) : le générateur qui créait automatiquement des œuvres
  et des images artificielles lorsque la base était vide a été entièrement
  supprimé. Il n'existe plus de génération automatique de données de test au
  lancement, y compris sur une installation neuve. Les données réelles
  doivent être introduites par les mécanismes d'importation de l'application.

- **Cache des vignettes borné** (`CacheVignettes.swift`) : le dictionnaire qui
  conservait toutes les vignettes préparées pendant la session a été remplacé
  par un `NSCache` limité à 48 entrées. Cette limite est commune aux variantes
  carrées des listes et aux variantes avec ratio de la galerie. Les vignettes
  anciennes peuvent donc être évacuées automatiquement, notamment sous
  pression mémoire, puis recréées à la demande si nécessaire.

- **Cache des vignettes — clé, regroupement et abandon** (`CacheVignettes.swift`).
  Trois défauts corrigés ensemble, tous invisibles à la lecture du code :
  - **La clé inclut la TAILLE**, plus seulement le nom et la variante. La
    galerie demande 320 pt, les listes structurées 240, le mode Liste une
    taille qui suit la hauteur de rangée : sans elle, la première vignette
    préparée était resservie à toutes les autres, donc floue si elle avait été
    fabriquée plus petite. La taille est arrondie à un palier de 40 pt, sans
    quoi une hauteur de rangée réglable fabriquerait une variante par pixel.
  - **Les demandeurs d'une même vignette sont REGROUPÉS.** Une demande portant
    sur une clé déjà en cours était auparavant ignorée et son rappel **perdu** :
    la deuxième cellule n'était jamais prévenue et restait sur son icône grise
    jusqu'à ce qu'on quitte la vue et y revienne. Le défaut s'est aggravé avec
    le `NSCache`, qui peut évincer une entrée puis la voir redemandée par
    plusieurs cellules à la fois.
  - **Une fabrication que plus personne n'attend est ABANDONNÉE.**
    `demanderVignette` (rappel) a laissé la place à `vignette(nom:cote:)`,
    **`async`** : SwiftUI annule le `.task(id:)` quand la cellule disparaît,
    l'attente se dénoue seule, et si plus aucun demandeur ne reste, la
    fabrication est sautée. Le test se fait au tour de la demande dans la file,
    donc **une fabrication déjà commencée va jusqu'au bout** — on n'interrompt
    jamais un décodage en cours. Sans cela, changer de rubrique laissait la
    file terminer des dizaines de vignettes devenues invisibles.
  - `JetonAbandon` est un booléen sous verrou, partagé entre le fil principal
    qui le pose et la file qui le lit. Il est **réarmé** si une nouvelle
    demande arrive sur une clé dont les demandeurs avaient tous renoncé.
  - **Une continuation doit être reprise exactement une fois** : un demandeur
    qui renonce est servi avec `nil` plutôt que laissé en suspens.
  - La file reste **sérielle** et en `.userInitiated` : voir plus haut, c'est ce
    qui évite le « Hang Risk » d'une tâche détachée par image.
- **Réduction des vignettes par ImageIO** (`CacheVignettes.swift`) : la
  fabrication des variantes carrée et avec ratio utilise désormais
  `CGImageSourceCreateThumbnailAtIndex`. ImageIO réduit l'image pendant le
  décodage au lieu de charger l'image pleine taille avec `NSImage(data:)` ou
  `UIImage(data:)`. Le recadrage carré reste centré, l'orientation EXIF est
  respectée et les deux plateformes utilisent leur type d'image natif. Il
  n'y a toujours pas de préchauffage global : seules les vignettes demandées
  par les cellules visibles sont préparées.
