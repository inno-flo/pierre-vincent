# Audit du code — PierreVincent

*Réalisé le 27 août 2026 par Claude Code. Point de départ : des gels de
quelques secondes pendant lesquels l'app ne réagit plus, « comme si une tâche
d'arrière-plan la bloquait ». Hypothèse de départ de l'utilisateur : la
reconstruction du cache des vignettes au premier lancement.*

---

## 1. Cause principale des gels — cache de vignettes sans borne

**L'hypothèse de départ vise le bon fichier, mais pas le bon moment.**

Ce n'est pas le *premier* lancement. Le cache de vignettes est uniquement en
mémoire — le cache disque a été essayé puis entièrement reverté (voir CLAUDE.md,
« Préchauffage des vignettes au lancement : ESSAYÉ, ABANDONNÉ »). Il se
reconstruit donc à **chaque** lancement, et surtout il **ne se vide jamais**.

`CacheVignettes.cache` (`CacheVignettes.swift`) est un `[String: ImagePlateforme]`
**sans aucune borne**, qui garde des images **décodées**.

### Mesures

Sur une image au gabarit réel du projet (2000×1500, 288 Ko sur disque après la
compression de `PhotoStore.importerImageCompressee`) :

| Élément | Poids en mémoire une fois décodé |
|---|---|
| 1 vignette galerie (480×360) | 675 Ko |
| 1 vignette liste (480×480, carrée) | 900 Ko |
| 500 œuvres, galerie seule | 330 Mo |
| 1000 œuvres, galerie seule | **659 Mo** |
| 1000 œuvres, galerie + liste | **1,5 Go** |
| 1500 œuvres, galerie + liste | **2,3 Go** |

### Pourquoi la note double

Le cache stocke **deux variantes par photo** : la clé `nom` (vignette carrée des
listes) et la clé `nom|ratio` (vignette au ratio d'origine, galerie). Parcourir
une rubrique en Galerie *puis* en Liste range donc deux images en mémoire pour
une seule œuvre.

### Pourquoi cela produit exactement le symptôme observé

Plus on navigue, plus la mémoire monte, sans jamais redescendre. Quand macOS se
met à compresser puis à swapper, l'app gèle plusieurs secondes **sans qu'aucun
calcul visible ne tourne** — d'où l'impression d'une tâche d'arrière-plan qui
bloque. Le gel n'a pas lieu au lancement mais **après avoir parcouru assez de
vues**.

Sur iPhone, la conséquence est différente et plus brutale : iOS ne swappe pas,
il **tue l'app** (jetsam).

### Correctif proposé

Remplacer le dictionnaire par un `NSCache` avec une limite. Il relâche la
mémoire tout seul sous pression système, et **le patron existe déjà dans le
projet** : `PhotoStore.cacheImages` est un `NSCache` borné à 6 entrées.

---

## 2. Fabrication des vignettes — 3× trop lente, et pour rien

`CacheVignettes.fabriquerVignette` et `fabriquerVignetteRatio` procèdent en
trois temps : `Data(contentsOf:)` charge tout le fichier, `NSImage(data:)` /
`UIImage(data:)` décode l'image **entière** en mémoire, puis elle est
redessinée en petit.

Or la bonne méthode est **déjà utilisée ailleurs dans le projet** :
`PhotoStore.importerImageCompressee` passe par
`CGImageSourceCreateThumbnailAtIndex`, qui décode directement à la taille
voulue sans jamais charger l'image pleine.

### Mesures (40 vignettes, côté cible 480 px)

```
Actuelle (Data + NSImage + redraw)  : 686 ms   (17,2 ms/image)
CGImageSourceCreateThumbnailAtIndex : 214 ms   ( 5,3 ms/image)
                                      -> 3,2x plus rapide
```

### Effet cumulé avec la file sérielle

La fabrication passe par une file **sérielle** unique (choix volontaire et
justifié : voir CLAUDE.md, « une file SÉRIELLE, pas une tâche par image »). Les
vignettes se préparent donc l'une après l'autre. Conséquence directe : une
galerie de 100 vignettes met aujourd'hui **~1,7 s** à se remplir, contre
**~0,5 s** avec la méthode ci-dessus.

Bénéfice secondaire, qui rejoint le point 1 : les 3 Mpx ne sont jamais chargés
en mémoire au passage.

---

## 3. Vérifié et écarté — le coût de `dossierPhotos`

`PhotoStore.dossierRacine` et `PhotoStore.dossierPhotos` sont des propriétés
**calculées** qui appellent `FileManager.createDirectory` à **chaque accès** —
soit deux appels système par accès. Elles sont sollicitées pour chaque vignette
(`CacheVignettes.demanderVignette`) et chaque image chargée.

Cela ressemble à un défaut de performance. **Mesure faite : 0,008 ms par
accès**, le système mettant le résultat en cache. Sur 2000 accès, 15 ms au
total.

**Ce n'est donc pas une piste de performance.** Consigné ici précisément pour
éviter d'y passer du temps. Mettre l'URL en cache reste possible, mais relève du
nettoyage cosmétique, pas de l'optimisation.

---

## 4. Code mort confirmé

Vérifié par recherche exhaustive sur l'ensemble des fichiers Swift.

| Élément | Fichier | État |
|---|---|---|
| `LargeursColonnes` (classe entière, 59 lignes) | `LargeursColonnes.swift` | Référencée **nulle part**. Supprimable. |
| `totalPrix(_:)` | `TriEtTotaux.swift:271` | Jamais appelée. |
| `ouvrirDossierDonnees()` | `VueFeuille.swift:1609` | Jamais appelée. |
| `RetourAppuiLong.jouer()` | `RetourAppuiLong.swift:54` | Jamais appelée — **voir l'avertissement ci-dessous.** |

### Avertissement sur `RetourAppuiLong.jouer()`

**Ce n'est pas du code mort ordinaire, et il ne faut pas le supprimer.**

Seule la constante `RetourAppuiLong.duree` est encore utilisée, dans
`VueiOS.swift:734`. La fonction `jouer()`, elle, n'est appelée nulle part.

Autrement dit : la vibration et le son de l'appui prolongé sur la photo de la
fiche de détail **ne se jouent plus du tout**, alors que CLAUDE.md les décrit
comme étant en place (section « `RetourAppuiLong` (iOS) réunit vibration et son
du geste »).

C'est une **régression silencieuse**, à rebrancher — pas un reste à effacer.

---

## 5. Point à corriger hors performance — données de test en Release

`DonneesTest.genererSiVide` est appelée depuis `ContentView.onAppear` et
s'exécute **y compris en Release**. Elle crée 310 œuvres bidon (100 par
catégorie, 10 tapis) et 5 images de test dès lors que la base est **vide**.

Conséquence : sur une installation neuve — un iPhone après réinstallation, avant
le premier import — l'app se remplit de fausses données.

Correctif : encadrer l'appel d'un `#if DEBUG`.

---

## 6. Piste secondaire — compteurs de la sidebar

`nombrePourCategorie` (`ContentView.swift:913`) rebalaye **toute la base** pour
**chaque** rubrique de la sidebar (une vingtaine), à chaque redessin — donc à
chaque bascule de favori, chaque modification d'œuvre.

`toutes.filter(estVenduOuDonne)` est recalculé à chaque appel au lieu d'une
fois. S'y ajoutent `modesDeVentePresents` et `themesPresents`, qui rebalayent
également.

**Ordre de grandeur : quelques millisecondes, pas des secondes.** À traiter
après les points 1 et 2, jamais avant : ce n'est pas la cause des gels.

---

## Récapitulatif — ordre de traitement conseillé

1. **Borner le cache mémoire** (`NSCache`) — cause principale des gels.
2. **`CGImageSourceCreateThumbnailAtIndex`** pour fabriquer les vignettes — 3,2×,
   et supprime le pic mémoire au passage.
3. `#if DEBUG` autour de `DonneesTest.genererSiVide`.
4. Rebrancher `RetourAppuiLong.jouer()`.
5. Supprimer le code mort (`LargeursColonnes`, `totalPrix`, `ouvrirDossierDonnees`).
6. Mémoïser les compteurs de sidebar.

Les points 1 et 2 touchent un seul fichier, `CacheVignettes.swift`.

---

## Méthode

Mesures réalisées avec des programmes Swift compilés en `-O`, sur une image
générée au gabarit réel du projet. Le conteneur de l'app
(`~/Library/Containers/com.florianinnocente.PierreVincent`) n'est pas lisible
depuis un terminal (protection macOS) : le nombre exact de photos et leur poids
réel n'ont donc pas pu être relevés, et les totaux mémoire ci-dessus sont des
projections à 500 / 1000 / 1500 œuvres.
