# Audit technique et pistes d’optimisation — PierreVincent

**Date :** 27 août 2026  
**Périmètre :** audit statique de 37 fichiers Swift, de la configuration Xcode, du cache d’images, des imports/exports, des recalculs SwiftUI/SwiftData et du code mort.

Ce document consigne l’audit réalisé sur l’application. Aucun code fonctionnel n’a été modifié pendant l’audit ; ce fichier constitue le relevé des constats et des corrections à envisager.

## Conclusion principale

Le cache des vignettes n’est **pas reconstruit pour toutes les vues au lancement**. Il est alimenté à la demande par les cellules visibles, via `.task(id:)`.

En revanche :

- les préparations déjà lancées ne sont pas annulées lorsqu’on change de vue ;
- la file de préparation utilise la priorité `.userInitiated` ;
- le cache mémoire n’a pas de limite ;
- les résultats repassent par `MainActor` et déclenchent des mises à jour de cellules.

Les pauses de plusieurs secondes viennent donc plus probablement de traitements synchrones sur `MainActor`, en particulier pendant l’initialisation et les imports/exports.

## 1. Causes probables des blocages au démarrage

### Initialisation dans `ContentView`

Dans `PierreVincent/ContentView.swift:681-797`, `.onAppear` effectue plusieurs traitements synchrones :

- construction de l’ensemble des photos utilisées ;
- nettoyage des photos orphelines avec `PhotoStore.nettoyerPhotosOrphelines` ;
- génération de données de test si la base est vide ;
- exécution d’une douzaine de reprises de données ;
- plusieurs recherches de toutes les œuvres et certaines sauvegardes `context.save()`.

Ces opérations sont regroupées dans le lancement de la hiérarchie principale. Elles peuvent empêcher l’interface de répondre pendant leur exécution.

### Générateur de données de test

Dans `PierreVincent/DonneesTest.swift:71-138`, `genererSiVide` crée, sur une base vide :

- 5 images contenant 4000 formes aléatoires chacune ;
- 310 œuvres ;
- puis sauvegarde le tout.

C’est une cause très probable de blocage lors d’une installation fraîche. Ce code est explicitement destiné au développement et devrait être désactivé ou protégé avant diffusion.

### Reprises de données

Les reprises sont définies dans `PierreVincent/Oeuvre.swift`. Plusieurs fonctions exécutent chacune un `FetchDescriptor<Oeuvre>()` sur l’ensemble de la base :

`Oeuvre.swift:100`, `:122`, `:156`, `:221`, `:256`, `:277`, `:305`, `:341`, `:365`, `:388`, `:413`, `:435` et `:452`.

Le nombre total de balayages et de sauvegardes peut donc être important lors d’un premier lancement.

Piste d’amélioration : coordonner les reprises, limiter l’initialisation à une séquence unique et, lorsque la sécurité des migrations le permet, effectuer un seul fetch et une seule sauvegarde. Il faut conserver une grande prudence : certaines passes écrasent ou suppriment volontairement des données.

### Nettoyage des photos orphelines

`PhotoStore.nettoyerPhotosOrphelines` (`PierreVincent/PhotoStore.swift:271`) parcourt le dossier des photos et supprime synchroniquement les fichiers non référencés.

Après de nombreux imports ou suppressions, cette opération peut devenir lente et contribuer au blocage de l’interface au lancement.

## 2. Opérations coûteuses sur le thread principal

### Configuration Xcode

Dans `PierreVincent.xcodeproj/project.pbxproj` :

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` aux lignes `317` et `379` ;
- en Debug, `SWIFT_OPTIMIZATION_LEVEL = "-Onone"` aux lignes `207` et `320` ;
- en Debug, `GCC_OPTIMIZATION_LEVEL = 0` à la ligne `190` ;
- en Release, `SWIFT_COMPILATION_MODE = wholemodule` à la ligne `263`.

Conséquences :

- une grande partie du code non annoté est isolée sur `MainActor` ;
- l’exécution depuis Xcode en Debug amplifie les coûts de recalcul et de décodage ;
- il faut comparer le comportement avec une build Release avant d’attribuer un blocage à l’application distribuée.

### Import de photos

Dans `PierreVincent/ImportPhotos.swift:66-157`, `importer` est `@MainActor`.

Pour chaque fichier, la fonction :

- lit les métadonnées IPTC ;
- lit la légende ;
- compresse et réduit l’image ;
- crée l’œuvre ;
- l’insère dans SwiftData.

`await Task.yield()` entre deux fichiers rend la main entre les fichiers, mais ne déplace pas le traitement d’un fichier hors du thread principal. Une seule image lourde peut donc encore bloquer l’interface pendant son traitement.

Les métadonnées sont lues séparément par `motsCles` et `legende`, puis le fichier est rouvert pour la compression : cela entraîne plusieurs lectures ImageIO par photo.

Piste d’amélioration :

- déplacer la lecture des métadonnées et la compression dans un worker ou un acteur de fond ;
- revenir sur `MainActor` uniquement pour insérer les `Oeuvre` dans SwiftData et mettre à jour la progression ;
- regrouper les lectures ImageIO des métadonnées afin d’éviter les ouvertures répétées.

### Import CSV

Dans `PierreVincent/Import.swift:75-199`, le traitement est entièrement `@MainActor`.

Lorsqu’un dossier `Photos` est présent :

- `NSImage(contentsOf:)` décode chaque photo ;
- `PhotoStore.enregistrer(image:)` la réencode ;
- l’ensemble se déroule sur le thread principal.

Pour un gros lot, l’interface peut donc rester bloquée.

Piste d’amélioration : copier directement les données avec `Data(contentsOf:)` puis utiliser `enregistrerDonnees`, et déplacer cette partie hors du thread principal.

### Échange `.pvbase`

#### Export

Dans `PierreVincent/EchangeBase.swift:66-101`, l’export est `@MainActor` et :

- lit chaque image ;
- l’encode en base64 ;
- construit un JSON complet en mémoire.

Le coût CPU, disque et mémoire peut devenir important pour une grosse base.

#### Import

Dans `PierreVincent/EchangeBase.swift:111-182`, l’import est `@MainActor` et :

- décode tout le fichier ;
- supprime les œuvres et photos existantes ;
- décode et réécrit toutes les images ;
- insère toutes les œuvres.

La sauvegarde intermédiaire tous les 25 éléments ne déplace pas le travail hors du thread principal.

Piste d’amélioration : traiter le décodage, le base64 et l’écriture des images en arrière-plan, puis réserver au contexte principal les mutations SwiftData.

### Exports

- `PierreVincent/Exports.swift:139-240` : export PDF synchrone ; chaque image est chargée et convertie en représentation `CGImage` pendant le dessin.
- `PierreVincent/ExportXLSXImages.swift:14-65` : fonction `async`, mais annotée `@MainActor`; les lectures `Data(contentsOf:)` restent donc sur le thread principal, même si XLKit suspend éventuellement pendant certaines opérations.
- Les exports CSV, XLS et dossier sont synchrones. Leur risque est plus faible, mais ils doivent être surveillés sur de gros volumes.

### Éditeur et images

Les chargements ou traitements d’image suivants peuvent se produire pendant un recalcul de vue :

- `PierreVincent/PhotoStore.swift:179-215` : import d’image compressée synchrone ;
- `PierreVincent/PhotoField.swift:84-88` et `:94-103` : dépôt ou choix d’une image, avec compression sur le thread principal ;
- `PierreVincent/VueFeuille.swift:306-310` : l’inspecteur macOS charge directement l’image complète dans `body` ;
- `PierreVincent/VueiOS.swift:728-731` : la fiche iOS charge l’image dans `body` ;
- `PierreVincent/VisionneusePanneau.swift:108` : chargement de l’image pleine taille macOS ;
- `PierreVincent/VisionneuseOeuvres.swift:178-180` : chargement de l’image pleine taille iOS ;
- `PierreVincent/TransitionVisionneuse.swift:192-193` : image d’aperçu.

Chaque recalcul de `body` peut donc relire et décoder l’image. C’est particulièrement problématique pendant un zoom, un déplacement ou un réaffichage.

Piste d’amélioration : charger une image pleine taille une seule fois dans un état local ou dans un cache partagé et borné. Éviter d’appeler directement `PhotoStore.chargerImage` à chaque recalcul de `body`.

## 3. Cache des vignettes

Le fichier concerné est `PierreVincent/CacheVignettes.swift`.

### Fonctionnement observé

- `CacheVignettes` est `@MainActor` et singleton.
- Le cache mémoire est un dictionnaire sans limite (`CacheVignettes.swift:20-23`).
- Les demandes viennent des cellules visibles (`:194-200` et `:235-241`).
- La préparation utilise une file série à priorité `.userInitiated` (`:46-74`).
- La fabrication lit `Data(contentsOf:)`, crée `NSImage(data:)` ou `UIImage(data:)`, puis dessine une petite image (`:83-160`).

### Constats

1. Il n’y a pas de préchauffage global au lancement.
2. Les cellules réellement rendues déclenchent les demandes.
3. Les demandes déjà en file continuent après un changement de vue, car elles ne sont pas annulées.
4. Chaque résultat repasse par `MainActor` et modifie l’état d’une cellule.
5. Le dictionnaire conserve toutes les vignettes pendant toute la vie du processus.
6. L’image source est décodée plus grande que nécessaire avant réduction.
7. Si la même clé est déjà dans `enCours`, la nouvelle demande est ignorée et son callback n’est pas mémorisé.
8. La clé ne contient pas `cote`, donc deux tailles différentes peuvent réutiliser la première vignette préparée.
9. Pour la variante avec ratio, la clé est seulement `nom + "|ratio"`.

### Recommandations

- remplacer le dictionnaire par un `NSCache` borné par nombre d’éléments ou par coût mémoire ;
- réduire directement avec `CGImageSourceCreateThumbnailAtIndex`, déjà utilisé dans `PhotoStore.importerImageCompressee` (`PierreVincent/PhotoStore.swift:188-198`) ;
- utiliser une priorité `.utility` pour les préparations non urgentes, ou un worker borné ;
- annuler ou ignorer les demandes devenues obsolètes lors d’un changement de vue ;
- regrouper les abonnés d’une même image au lieu de perdre les callbacks ;
- inclure la taille et la variante dans la clé si plusieurs résolutions sont nécessaires.

### Conclusion sur le cache

Le cache est une piste secondaire mais crédible pour les saccades et une consommation mémoire excessive. Il n’explique pas un cache « reconstruit pour toutes les vues au lancement », car ce mécanisme n’existe pas dans le code actuel.

## 4. Recalculs SwiftUI et SwiftData

### Sidebar

Dans `PierreVincent/ContentView.swift:913-947`, `nombrePourCategorie` commence par `toutes.filter(estVenduOuDonne)`.

Chaque ligne de sidebar peut donc refaire un filtrage complet. Les rubriques dynamiques de modes et de thèmes peuvent multiplier les parcours.

Avec environ 1000 œuvres, le coût reste probablement de l’ordre de quelques millisecondes, mais il est répété inutilement et amplifié en Debug.

Piste d’amélioration : construire un snapshot des compteurs lors d’une mise à jour de `toutes`, puis le réutiliser pour toutes les lignes.

Dans `ContentView.swift:1080-1107`, `modesDeVentePresents` parcourt et trie les données. Dans `ContentView.swift:1142-1154`, `themesPresents` parcourt et trie à nouveau les œuvres de Réserve. `categoriesSidebar` réutilise ensuite ces résultats pour la navigation et la construction de la sidebar.

### Vues principales

Une requête `@Query private var toutes: [Oeuvre]` existe notamment dans :

- `ContentView.swift:375` ;
- `VueFeuille.swift:88` ;
- `VueiOS.swift:54` ;
- `VueOeuvresStructuree.swift:51` ;
- `VueDonsStructuree.swift:27`.

Les vues recalculent leurs tableaux à chaque réévaluation :

- `VueFeuille.swift:160-187` et `:235-264` ;
- `VueiOS.swift:85-135` ;
- `VueOeuvresStructuree.swift:109-164` ;
- `VueDonsStructuree.swift:53-81` ;
- `VueSynthese.swift:76-109`.

Exemples de travail répété :

- filtres complets ;
- tris ;
- recherche de vendeurs et de types ;
- appels répétés à `oeuvres` depuis le `body`, l’inspecteur, la navigation et les actions.

Piste d’amélioration : calculer un snapshot local une fois par rendu ou introduire un modèle de présentation observable. Éviter de recalculer le même tri dans le `body`, l’inspecteur et les actions.

Ce point ne semble toutefois pas suffire à expliquer à lui seul des pauses de plusieurs secondes avec environ 1000 œuvres. Les opérations image et les traitements `MainActor` sont prioritaires.

## 5. Code mort ou à nettoyer

Le nettoyage doit être effectué après stabilisation fonctionnelle. Certaines solutions de repli sont conservées volontairement.

### Candidats sans référence active

- `PierreVincent/LargeursColonnes.swift` : aucune référence trouvée en dehors de son propre fichier ; candidat à supprimer après vérification finale.
- `DesactiveSurbrillanceSidebar` dans `ContentView.swift:1346` : déclaration présente, mais aucun appel actif.
- `@AppStorage("statutVenduRempli")` dans `ContentView.swift:393` : ancien drapeau, aucune lecture ou écriture active.
- `@AppStorage("reservePurgee")` dans `ContentView.swift:414` : ancien drapeau associé à une purge débranchée.
- `PhotoStore.prechargerImage` (`PhotoStore.swift:108`) : aucune invocation active.
- `RetourAppuiLong.preparer` et `RetourAppuiLong.jouer` (`RetourAppuiLong.swift:51` et `:54`) : aucune invocation active ; seul `RetourAppuiLong.duree` est utilisé dans `VueiOS.swift:734`.
- `ThemeApp` et le mécanisme `couleurTheme` dans `Couleurs.swift` : encore utilisés indirectement pour certaines couleurs, mais le sélecteur de thème a été retiré ; la partie héritée pourra être simplifiée après vérification des anciennes préférences.
- `graphitePageBg`, `graphiteCardBg`, `graphiteTileBg`, `graphiteTexte` et `graphiteBordure` (`Couleurs.swift:163-167`) : aucune référence active trouvée.
- `fondCelluleSidebar`, `fondCelluleSidebarSelectionnee` et `fondSelectionSidebarMac` sont encore définis ; les deux premiers fonds ne servent plus activement à la sélection, et `fondSelectionSidebarMac` ne doit pas être réintroduit sans décision.

### Éléments conservés volontairement

- `afficherMenuFiltreTypeToolbar` et `afficherBoutonCorbeilleToolbar` sont volontairement à `false` pour conserver les essais ; ne pas les supprimer sans décision.
- Quick Look est conservé comme solution de repli, même si la visionneuse intégrée est active ; ne pas le supprimer sans choix explicite.
- `purgerReserve` est conservée mais débranchée pour sécurité ; ne surtout pas la reconnecter.

### Commentaires obsolètes ou incohérents

- `TriEtTotaux.swift:6-9` parle encore de double-tap alors que le double-tap a été abandonné.
- `VisionneusePanneau.swift:8` décrit une limitation à Réserve › Catalogue alors que le drapeau de visionneuse intégrée est désormais vrai partout.
- `RetourAppuiLong.swift:43-46` affirme qu’un préchargement est lancé au contact alors que `PhotoStore.prechargerImage` n’est appelé nulle part.
- Plusieurs commentaires dans `Couleurs.swift`, `ContentView.swift` et `VueSynthese.swift` parlent encore de thèmes, de marron ou de Graphite anciens.

### Sauvegardes silencieuses

`rg` a trouvé de nombreux `try? context.save()` :

- `ImportPhotos.swift:148` ;
- `Import.swift:199` ;
- `VueGalerie.swift:269` ;
- `VueDonsStructuree.swift:340` ;
- `VueFeuille.swift:555`, `:1485`, `:1532` et `:1572` ;
- `DernierImport.swift:61` ;
- `EchangeBase.swift:177` et `:181` ;
- plusieurs reprises dans `Oeuvre.swift` ;
- `TriEtTotaux.swift:13`.

Conséquence : une erreur de sauvegarde est ignorée silencieusement, l’utilisateur peut croire que l’action a réussi et le diagnostic devient difficile.

Piste d’amélioration :

- au minimum, journaliser l’erreur ;
- pour les actions utilisateur, afficher une erreur ;
- pour les migrations, ne valider le drapeau de reprise qu’après avoir traité et évalué le résultat de la sauvegarde.

## 6. Build, tests et vérifications

- Aucune cible de tests n’existe dans le dépôt.
- La compilation Release exécutée le 27 août 2026 retourne un code 0.
- Un avertissement est émis dans `PierreVincent/PierreVincentApp.swift:255` : `Selector(("selectAll:"))` pourrait utiliser `#selector`.
- L’environnement Xcode bêta a aussi affiché des messages CoreSimulator, mais cela ne concernait pas l’analyse macOS Release.

Les fonctions pures suivantes mériteraient des tests unitaires :

- `correspond` ;
- `themesDeOeuvre` ;
- `filtrerParType` ;
- `normaliserCollectionPersonnelle` ;
- `surfaceDimensions` ;
- `formaterEuros` ;
- les tables de correspondance de `ImportPhotos`.

## 7. Ordre recommandé des corrections

1. Désactiver ou protéger `DonneesTest` avant diffusion.
2. Mesurer le lancement avec Instruments Time Profiler, en ajoutant éventuellement des signposts autour de `ContentView.onAppear`, des reprises et de chaque préparation de vignette.
3. Déplacer la lecture IPTC, la compression, les exports/imports d’images et le base64 hors de `MainActor`.
4. Charger les images pleine taille une seule fois et ajouter un cache borné.
5. Améliorer `CacheVignettes` avec ImageIO downsampling, cache borné, annulation et coalescence des demandes.
6. Construire des snapshots de filtrage et de tri réutilisables.
7. Nettoyer le code mort et les commentaires, puis traiter les erreurs de sauvegarde.
8. Ajouter les tests unitaires des fonctions de filtrage et d’import.

## Conclusion

Sans mesure Instruments, il est impossible d’attribuer avec certitude chaque pause à un seul composant.

L’audit montre néanmoins que la reconstruction globale du cache au lancement n’est pas la cause : les cellules visibles alimentent le cache à la demande. Les suspects prioritaires sont l’initialisation synchronisée de `ContentView`, le générateur de données de test, les reprises de données et les traitements d’image, d’import et d’export exécutés sur `MainActor`.
