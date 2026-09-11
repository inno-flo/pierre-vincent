#!/usr/bin/env python3
# Fabrique les calques SVG de l'icône « kaki » et les aperçus PNG 1024×1024.
#
#   python3 faire-icone.py
#
# La géométrie est écrite UNE SEULE FOIS ; seules les couleurs changent d'une
# variante à l'autre. Les calques d'avant-plan sont livrés sur toile pleine et
# transparente, sans coins arrondis : le masque squircle est appliqué par le
# système, et les reflets spéculaires par Icon Composer.

import json
import math
import os
import subprocess
import sys

DOSSIER = os.path.dirname(os.path.abspath(__file__))
COTE = 1024

# ----------------------------------------------------------------- géométrie
# Tout est dessiné sur une grille de 1024. Le fruit et son calice tiennent dans
# une boîte centrée d'environ 650 × 640, soit une marge d'au moins 185 px sur
# les quatre bords — de quoi survivre au masque squircle sans rognage.

# Corps du fruit : plus large que haut (648 × 558), épaules hautes et sommet
# aplati — c'est ce qui distingue un kaki d'une pomme ou d'un abricot.
CORPS = (
    "M 512 272 "
    "C 340 272 188 332 188 472 "
    "C 188 654 336 830 512 830 "
    "C 688 830 836 654 836 472 "
    "C 836 332 684 272 512 272 Z"
)

# Facette claire du flanc gauche : une ellipse simple, DÉCOUPÉE par le contour
# du fruit — sans ce découpage elle débordait en bas à gauche. Bord franc
# partout, comme le demandent les HIG : aucun flou, aucun halo. Elle reste
# discrète, le reflet spéculaire étant le travail du système, pas le nôtre.
FACETTE = {"cx": 306, "cy": 438, "rx": 214, "ry": 288}

# Un sépale, dessiné pointant vers la droite depuis le pédoncule (512, 292) et
# SYMÉTRIQUE par rapport à son axe. La version précédente ne l'était pas : mis
# en rotation, le calice tournait comme un moulin à vent.
SEPALE = (
    "M 512 292 "
    "C 554 240 638 234 727 292 "
    "C 638 350 554 344 512 292 Z"
)

# Le calice est vu de trois quarts dessus, comme sur un kaki posé : les deux
# sépales latéraux s'étalent de tout leur long, ceux de devant et de derrière
# sont raccourcis par la perspective. L'échelle est donc DISSOCIÉE en longueur
# et en largeur — un simple facteur uniforme les amincissait en flammes.
# (angle, longueur, largeur)
SEPALES = ((4, 1.0, 1.0), (176, 1.0, 1.0), (-86, 0.52, 0.92), (94, 0.34, 1.06))

# Pédoncule : un court tronçon trapu au centre de la rosette.
PEDONCULE = (
    "M 490 300 "
    "C 490 274 490 256 494 246 "
    "C 502 232 522 232 530 246 "
    "C 534 256 534 274 534 300 Z"
)


# ----------------------------------------------------------------- palettes
class Palette:
    def __init__(self, nom, fond, fruit_haut, fruit_bas, facette, calice_clair,
                 calice_fonce, pedoncule):
        self.nom = nom
        self.fond = fond
        self.fruit_haut = fruit_haut
        self.fruit_bas = fruit_bas
        self.facette = facette            # (couleur, opacité)
        self.calice_clair = calice_clair
        self.calice_fonce = calice_fonce
        self.pedoncule = pedoncule


CLAIR = Palette(
    nom="clair",
    fond="#2F6A97",                       # bleu profond, complémentaire de l'orange
    fruit_haut="#FBAE33",
    fruit_bas="#E8681A",
    facette=("#FFFFFF", 0.06),
    calice_clair="#6DA05F",               # le calice est éclairci DEPUIS que le
    calice_fonce="#4E7C47",               # fond a foncé : les pointes des sépales
    pedoncule="#3B6440",                  # dépassent du fruit, sur le bleu
)

SOMBRE = Palette(
    nom="sombre",
    fond="#000000",
    fruit_haut="#EE9524",                 # un cran plus profond : un orange trop
    fruit_bas="#C9530F",                  # lumineux « brûle » sur fond noir
    facette=("#FFFFFF", 0.05),
    calice_clair="#63955A",               # un cran plus clair : les pointes des
    calice_fonce="#456F41",               # sépales débordent sur le noir
    pedoncule="#3C6140",
)


# ----------------------------------------------------------------- fabrique
def entete(contenu):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{COTE}" height="{COTE}" '
        f'viewBox="0 0 {COTE} {COTE}">\n{contenu}\n</svg>\n'
    )


def calque_fruit(p, prefixe=""):
    """Corps du fruit + sa facette claire."""
    idg, idc = f"{prefixe}chair", f"{prefixe}contour"
    couleur, opacite = p.facette
    f = FACETTE
    return f"""  <defs>
    <linearGradient id="{idg}" gradientUnits="userSpaceOnUse"
                    x1="512" y1="272" x2="512" y2="830">
      <stop offset="0" stop-color="{p.fruit_haut}"/>
      <stop offset="1" stop-color="{p.fruit_bas}"/>
    </linearGradient>
    <clipPath id="{idc}">
      <path d="{CORPS}"/>
    </clipPath>
  </defs>
  <path d="{CORPS}" fill="url(#{idg})"/>
  <ellipse cx="{f['cx']}" cy="{f['cy']}" rx="{f['rx']}" ry="{f['ry']}"
           fill="{couleur}" fill-opacity="{opacite}" clip-path="url(#{idc})"/>"""


def sepale_place(angle, longueur, largeur, pivot=(512, 292)):
    """Un sépale tourné et mis à l'échelle, rendu en coordonnées ABSOLUES.

    Les quatre sépales ont d'abord été posés par un `transform` SVG. Mais un
    dégradé en `userSpaceOnUse` subit la transformation de l'élément qu'il
    peint : chaque sépale emportait donc son dégradé en tournant, au lieu de
    partager le dégradé vertical commun (sommet clair, base foncée). Les
    coordonnées sont calculées ici une fois pour toutes — un effet de bord
    heureux : plus aucun `transform` dans les fichiers livrés.
    """
    a = math.radians(angle)
    cos_a, sin_a = math.cos(a), math.sin(a)
    px, py = pivot

    def point(x, y):
        # échelle dans le repère du sépale, puis rotation, puis retour au pivot
        dx, dy = (x - px) * longueur, (y - py) * largeur
        return (px + dx * cos_a - dy * sin_a, py + dx * sin_a + dy * cos_a)

    sortie, nombres = [], []
    for jeton in SEPALE.split():
        if jeton in ("M", "C", "Z"):
            sortie.append(jeton)
        else:
            nombres.append(float(jeton))
            if len(nombres) == 2:
                x, y = point(*nombres)
                sortie.append(f"{x:.1f} {y:.1f}")
                nombres = []
    return " ".join(sortie)


def calque_calice(p, prefixe=""):
    """Les quatre sépales et le pédoncule."""
    idg = f"{prefixe}feuille"
    sepales = "\n".join(
        f'  <path d="{sepale_place(a, lg, la)}" fill="url(#{idg})"/>'
        for a, lg, la in SEPALES
    )
    return f"""  <defs>
    <linearGradient id="{idg}" gradientUnits="userSpaceOnUse"
                    x1="512" y1="200" x2="512" y2="400">
      <stop offset="0" stop-color="{p.calice_clair}"/>
      <stop offset="1" stop-color="{p.calice_fonce}"/>
    </linearGradient>
  </defs>
{sepales}
  <path d="{PEDONCULE}" fill="{p.pedoncule}"/>"""


def calque_fond(p):
    return f'  <rect width="{COTE}" height="{COTE}" fill="{p.fond}"/>'


def composite(p):
    """Aperçu : fond + les deux calques d'avant-plan, à plat."""
    return (
        calque_fond(p) + "\n"
        + calque_fruit(p, "a_") + "\n"
        + calque_calice(p, "b_")
    )


# ----------------------------------------------------------------- écriture
def ecrire(nom, contenu):
    chemin = os.path.join(DOSSIER, nom)
    with open(chemin, "w", encoding="utf-8") as f:
        f.write(entete(contenu))
    print(f"écrit {nom}")
    return chemin


def rasteriser(svg, png):
    """QuickLook sait rendre un SVG ; c'est le seul rasteriseur présent d'office."""
    tmp = os.path.join(DOSSIER, ".rendu")
    os.makedirs(tmp, exist_ok=True)
    subprocess.run(
        ["qlmanage", "-t", "-s", str(COTE), "-o", tmp, svg],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
    )
    produit = os.path.join(tmp, os.path.basename(svg) + ".png")
    if not os.path.exists(produit):
        print(f"⚠︎ rendu manqué pour {svg}", file=sys.stderr)
        return
    os.replace(produit, os.path.join(DOSSIER, png))
    print(f"écrit {png}")


def paquet_icon(clair, sombre):
    """Un .icon prêt à ouvrir dans Icon Composer, avec ses DEUX apparences.

    Les deux calques d'avant-plan forment DEUX groupes distincts : les effets
    Liquid Glass s'appliquent au niveau du groupe, et un calice séparé du fruit
    reçoit donc son propre relief. Le fond n'est pas une image mais une couleur,
    comme le recommandent les HIG.

    L'apparence sombre passe par les clés `*-specializations`, indexées par
    `dark-color`. C'est ce format — et non un `appiconset` — qui permet une
    icône sombre sur macOS : voir le README, actool ignore purement et
    simplement une variante sombre déclarée dans un appiconset pour macOS.
    """
    import shutil

    racine = os.path.join(DOSSIER, "kaki.icon")
    assets = os.path.join(racine, "Assets")
    shutil.rmtree(racine, ignore_errors=True)
    os.makedirs(assets)

    calques = (("kaki-fruit.svg", "kaki-fruit-sombre.svg"),
               ("kaki-calice.svg", "kaki-calice-sombre.svg"))
    for paire in calques:
        for nom in paire:
            shutil.copy(os.path.join(DOSSIER, nom), os.path.join(assets, nom))

    def gradient(hexa):
        r, v, b = (int(hexa[i:i + 2], 16) / 255 for i in (1, 3, 5))
        return {"automatic-gradient":
                f"extended-srgb:{r:.5f},{v:.5f},{b:.5f},1.00000"}

    def groupe(jour, nuit):
        return {
            "layers": [{
                "image-name": jour,
                "name": jour[:-4],
                "image-name-specializations": {"dark-color": nuit},
            }],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": True, "value": 0.15},
        }

    icon = {
        "fill": gradient(clair.fond),
        "fill-specializations": {"dark-color": gradient(sombre.fond)},
        "groups": [groupe(*paire) for paire in calques],
        # « shared » : le MÊME jeu de calques sert iOS et macOS. Les icônes
        # macOS 26 sont désormais à pleine toile et masquées en squircle,
        # exactement comme sur iOS — il n'y a plus de jeu à part à tenir.
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }
    with open(os.path.join(racine, "icon.json"), "w", encoding="utf-8") as f:
        json.dump(icon, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("écrit kaki.icon (apparences claire et sombre)")


def main():
    for p in (CLAIR, SOMBRE):
        suffixe = "" if p.nom == "clair" else "-sombre"
        ecrire(f"kaki-fruit{suffixe}.svg", calque_fruit(p))
        ecrire(f"kaki-calice{suffixe}.svg", calque_calice(p))
        # Le fond n'est pas à importer dans Icon Composer (il sait poser une
        # couleur unie) ; ce fichier ne sert qu'à consigner l'hexadécimal.
        ecrire(f"fond{suffixe}.svg", calque_fond(p))

        apercu = ecrire(f".plat-{p.nom}.svg", composite(p))
        rasteriser(apercu, f"kaki-1024-{p.nom}.png")
        os.remove(apercu)

    paquet_icon(CLAIR, SOMBRE)

    rendu = os.path.join(DOSSIER, ".rendu")
    if os.path.isdir(rendu):
        os.rmdir(rendu)


if __name__ == "__main__":
    main()
