# Icône d'app — le kaki

L'illustration détourée du kaki, sur un aplat de couleur, en deux apparences :
**claire** (fond bleu profond) et **sombre** (fond noir). Le même calque sert
**iOS et macOS**.

Tout est fabriqué par `faire-icone.py` :

```bash
python3 faire-icone.py
```

## Ce que produit le script

| Fichier | Rôle |
|---|---|
| `kaki.icon/` | **le livrable** — paquet Icon Composer, les deux apparences, les deux plateformes |
| `kaki-fruit.png` | le calque d'avant-plan : le dessin retourné et recentré |
| `fond.svg` / `fond-sombre.svg` | **ne pas importer** — ces fichiers ne servent qu'à consigner l'hexadécimal du fond |
| `kaki-1024-clair.png` / `kaki-1024-sombre.png` | les deux apparences aplaties, 1024 × 1024, pour relecture |

Le dessin source n'est pas recopié ici : il est lu là où il vit, dans
`Ressources App Pierre-Vincent/Icône app/iconekaki.icon/Assets/kaki_detoure_couleur.png`.

## Le dessin

L'illustration d'origine, reprise **telle quelle** — aucune retouche des
couleurs du fruit. Deux traitements seulement, tous deux dans
`preparer_calque()` :

- **Miroir horizontal** (`MIROIR`). Le dessin est éclairé d'en **haut à
  droite** : sa zone claire est à droite, son ombre longe le bord gauche. La
  lumière devant venir d'en **haut à gauche**, le dessin est retourné — le
  modelé est déjà peint dans l'image, un miroir suffit à l'inverser. Repeindre
  les aplats aurait sali les bords adoucis du détourage pour le même résultat.
  Passer `MIROIR` à `False` rend l'éclairage d'origine.
- **Recentrage.** Le dessin penchait vers le bas et la droite (marges 192/178
  en horizontal, 193/164 en vertical). Il est recalé sur le centre de toile, ce
  que demandent les HIG (« Keep primary content centered ») : marges de 186 à
  187 px en horizontal, 179 à 180 px en vertical.

Le fruit est **identique en clair et en sombre** — seul le fond change, comme
dans la version précédente de l'icône. Le creux du calice laisse voir le fond :
bleu en apparence claire, noir en sombre, où il se lit très bien comme un
creux.

## Couleurs de fond

| | clair | sombre |
|---|---|---|
| Fond | `#2F6A97` | `#000000` |

Le fond clair était un bleu ciel (`#74C4EA`) ; il est passé à un bleu profond,
sur lequel l'orange du fruit ressort bien davantage. Quatre bleus plus sombres
ont été comparés à l'écran ; le bleu ardoise de l'app (`#466487`) virait au
gris et éteignait l'orange.

## Pourquoi un `.icon` et pas un `appiconset`

**Un `appiconset` ne sait pas porter d'icône sombre pour macOS.** Vérifié, pas
supposé — `actool` accepte le fichier sans le moindre avertissement, puis
ignore purement et simplement la variante :

| Déclaration | `Assets.car` | entrées « Appearance » |
|---|---|---|
| macOS, `idiom: mac`, sans variante sombre | 91 608 o | 0 |
| macOS, `idiom: mac`, **avec** variante sombre | 91 608 o | 0 |
| iOS, `platform: ios`, sans variante sombre | 173 720 o | 0 |
| iOS, `platform: ios`, **avec** variante sombre | 329 896 o | 2 |

Même taille à l'octet près côté macOS, alors que côté iOS la variante double le
catalogue : la ligne iOS est le contrôle positif qui prouve que la mesure est
bonne. `"platform": "macos"` avec `"idiom": "universal"` ne marche pas non
plus — `actool` ne compile alors **rien du tout**, et rend un plist vide.

Le format `.icon`, lui, compile sans erreur ni avertissement sur les deux
plateformes et déclare bien les apparences sombres :

| Plateforme | Produits | Apparences dans le catalogue |
|---|---|---|
| `macosx` | `kaki.icns` + `Assets.car` | Aqua, **DarkAqua**, Tintable |
| `iphoneos` | `Assets.car` + PNG | Light, **Dark**, Tintable |

C'est ce qui permet de décliner la version sombre pour macOS, et c'est de toute
façon la voie recommandée pour Liquid Glass.

`"supported-platforms": {"squares": "shared"}` : le **même** calque sert iOS et
macOS. Les icônes macOS 26 sont désormais à pleine toile et masquées en
squircle, exactement comme sur iOS — il n'y a plus de jeu à part à tenir.

### Un point à confirmer en ouvrant le fichier

L'apparence sombre passe par la clé `fill-specializations`, indexée par
**`dark-color`**. Cette clé vient du framework d'Icon Composer, qui déclare la
famille complète (`light-color`, `dark-color`, `light-tint`, `dark-tint`,
`light-clear`, `dark-clear`).

`actool` compile sans broncher, mais il ne valide pas les clés inconnues : une
clé mal orthographiée serait ignorée en silence, et macOS dériverait alors son
apparence sombre tout seul au lieu d'utiliser le fond noir demandé. **Ouvrir
`kaki.icon` dans Icon Composer lève le doute en une seconde** : si l'onglet
*Dark* montre le fond noir, la clé est la bonne. Sinon, la corriger dans
l'interface — le fichier est de toute façon fait pour être ouvert là.

## Installation dans la cible Xcode

Le paquet est déposé dans `PierreVincent/Kaki.icon` et la cible pointe dessus
par `ASSETCATALOG_COMPILER_APPICON_NAME = Kaki` (Debug et Release).

**Aucune déclaration à écrire dans `project.pbxproj`** : le projet est en
`objectVersion = 77` avec un `PBXFileSystemSynchronizedRootGroup` sur le
dossier `PierreVincent/`. Tout fichier déposé là est inclus automatiquement —
seul le nom de l'icône a dû être changé dans les réglages de la cible.

Vérifié par un build réel sur les deux plateformes :

| | macOS | iOS |
|---|---|---|
| Build | succès | succès |
| Produit | `Kaki.icns` | `Kaki60x60@2x.png`, `Kaki76x76@2x~ipad.png` |
| `CFBundleIconName` | `Kaki` | `Kaki` |
| Apparences compilées | Aqua, **DarkAqua**, Tintable | Light, **Dark**, Tintable |

L'icône extraite de l'app compilée montre bien le kaki, avec le masque squircle
et le reflet spéculaire posés par le système.

### L'ancien `AppIcon.appiconset` est resté en place

Il n'est plus utilisé — plus rien ne pointe dessus — mais il n'a pas été
supprimé : ses images sont l'ancienne icône, et le retirer est une décision à
prendre à part. Il continue d'être compilé dans `Assets.car` pour rien. Le
supprimer est sans risque une fois la nouvelle icône validée à l'usage.

## Conformité Liquid Glass

Vérifié contre « App icons » (HIG, révision du 8 juin 2026, *Refined guidance
for Liquid Glass*).

Conforme : toile pleine **sans coins pré-découpés** (le masque squircle est
appliqué par le système ; l'icône précédente, elle, avait ses coins cuits) ;
contenu centré avec une marge minimale de 179 px, donc rien n'est rogné ; fond
en aplat de couleur et non en image, comme le recommandent les HIG ; un motif,
pas de texte, pas de réplique de composant d'interface.

### Trois écarts assumés

- **Le dessin est une illustration, pas un tracé vectoriel.** Les HIG
  préfèrent le vecteur, qui reste net à toutes les tailles. Ce dessin-ci a été
  retenu pour son réalisme. Il tient bien jusqu'à 40 px, vérifié.
  Une version entièrement vectorielle existe dans `variante-vectorielle/` :
  plus simple de dessin, en deux calques séparés (fruit et calice), avec son
  propre script. Elle n'est plus le livrable, elle est gardée de côté.
- **Le dessin porte son propre modelé**, ombre comprise, là où les HIG
  confient ombres et reflets au système. C'est indissociable de l'illustration
  choisie — et c'est aussi ce qui permet d'orienter la lumière par un simple
  miroir.
- **Un seul calque d'avant-plan.** Le fruit et son calice ne font qu'un dans le
  dessin, il n'y a rien à séparer. Deux calques donneraient plus de relief sous
  Liquid Glass, mais demanderaient de redécouper le dessin.
- **Le fond noir en apparence sombre** va contre « Color backgrounds generally
  offer the greatest contrast in dark icons ». C'est une demande explicite, et
  le noir fait bien ressortir l'orange. Le « Avoid using black for your icon's
  background » des HIG figure sous *Platform considerations → watchOS*, qui
  n'est pas une cible ici.
