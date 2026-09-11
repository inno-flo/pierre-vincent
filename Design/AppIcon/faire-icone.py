#!/usr/bin/env python3
# Fabrique l'icône « kaki » : le calque d'avant-plan, les deux aperçus
# 1024 × 1024 et le paquet Icon Composer.
#
#   python3 faire-icone.py
#
# Le dessin du fruit est l'illustration détourée d'origine, reprise telle
# quelle. Seul le FOND change d'une apparence à l'autre — le fruit est le même
# en clair et en sombre, comme dans la version précédente de l'icône.

import json
import os
import shutil

from PIL import Image

DOSSIER = os.path.dirname(os.path.abspath(__file__))
COTE = 1024

# Le dessin d'origine, hors dépôt : il vit dans le dossier de ressources.
SOURCE = os.path.join(
    os.path.dirname(DOSSIER), "..", "..",
    "Ressources App Pierre-Vincent", "Icône app",
    "iconekaki.icon", "Assets", "kaki_detoure_couleur.png",
)

CALQUE = "kaki-fruit.png"

# Le dessin d'origine est éclairé d'en HAUT À DROITE : sa zone claire est à
# droite du fruit, son ombre longe le bord gauche. La lumière doit venir d'en
# haut à GAUCHE, donc le dessin est retourné horizontalement — le modelé est
# déjà peint dans l'image, un miroir suffit à l'inverser. Repeindre les aplats
# aurait sali les bords adoucis du détourage pour le même résultat.
MIROIR = True

# ----------------------------------------------------------------- palettes
FOND_CLAIR = "#2F6A97"   # bleu profond, complémentaire de l'orange du fruit
FOND_SOMBRE = "#000000"


def rvb(hexa):
    return tuple(int(hexa[i:i + 2], 16) for i in (1, 3, 5))


# ----------------------------------------------------------------- calque
def preparer_calque():
    """Recentre le dessin sur la toile et l'écrit comme calque d'avant-plan.

    Le dessin d'origine penche vers le bas et la droite (marges 192/178 en
    horizontal, 193/164 en vertical). Il est recalé sur le centre de toile,
    ce que demandent les HIG (« Keep primary content centered ») et ce qui
    donne des marges égales de 185 et 179 px — largement de quoi survivre au
    masque squircle.
    """
    src = Image.open(SOURCE).convert("RGBA")
    if src.size != (COTE, COTE):
        raise SystemExit(f"dessin source attendu en {COTE}×{COTE}, reçu {src.size}")
    if MIROIR:
        src = src.transpose(Image.FLIP_LEFT_RIGHT)

    x0, y0, x1, y1 = src.getchannel("A").getbbox()
    dx = round(COTE / 2 - (x0 + x1) / 2)
    dy = round(COTE / 2 - (y0 + y1) / 2)

    calque = Image.new("RGBA", (COTE, COTE), (0, 0, 0, 0))
    calque.paste(src, (dx, dy), src)
    calque.save(os.path.join(DOSSIER, CALQUE))

    bb = calque.getchannel("A").getbbox()
    print(f"écrit {CALQUE} — recalé de ({dx:+d}, {dy:+d}), "
          f"marges G{bb[0]} D{COTE-bb[2]} H{bb[1]} B{COTE-bb[3]}")
    return calque


# ----------------------------------------------------------------- aperçus
def apercu(calque, fond, nom):
    """Le calque posé sur son fond — ce que donnera l'icône, effets en moins."""
    plat = Image.new("RGB", (COTE, COTE), rvb(fond))
    plat.paste(calque, (0, 0), calque)
    plat.save(os.path.join(DOSSIER, nom))
    print(f"écrit {nom}")


def fond_svg(fond, nom):
    """Ne sert qu'à consigner l'hexadécimal — à ne pas importer dans le .icon,
    Icon Composer sachant poser une couleur de fond directement."""
    with open(os.path.join(DOSSIER, nom), "w", encoding="utf-8") as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{COTE}" '
                f'height="{COTE}" viewBox="0 0 {COTE} {COTE}">\n'
                f'  <rect width="{COTE}" height="{COTE}" fill="{fond}"/>\n</svg>\n')
    print(f"écrit {nom}")


# ----------------------------------------------------------------- paquet
def paquet_icon():
    """Un .icon prêt à ouvrir dans Icon Composer, avec ses DEUX apparences.

    C'est ce format — et non un `appiconset` — qui permet une icône sombre sur
    macOS : voir le README, actool ignore purement et simplement une variante
    sombre déclarée dans un appiconset pour macOS.

    Un SEUL calque : le fruit et son calice ne font qu'un dans le dessin
    d'origine, il n'y a rien à séparer. Seul le fond se spécialise en sombre.
    """
    racine = os.path.join(DOSSIER, "kaki.icon")
    assets = os.path.join(racine, "Assets")
    shutil.rmtree(racine, ignore_errors=True)
    os.makedirs(assets)
    shutil.copy(os.path.join(DOSSIER, CALQUE), os.path.join(assets, CALQUE))

    def gradient(hexa):
        r, v, b = (c / 255 for c in rvb(hexa))
        return {"automatic-gradient":
                f"extended-srgb:{r:.5f},{v:.5f},{b:.5f},1.00000"}

    icon = {
        "fill": gradient(FOND_CLAIR),
        "fill-specializations": {"dark-color": gradient(FOND_SOMBRE)},
        "groups": [{
            "layers": [{"image-name": CALQUE, "name": CALQUE[:-4]}],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": True, "value": 0.15},
        }],
        # « shared » : le MÊME calque sert iOS et macOS. Les icônes macOS 26
        # sont désormais à pleine toile et masquées en squircle, exactement
        # comme sur iOS — il n'y a plus de jeu à part à tenir.
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }
    with open(os.path.join(racine, "icon.json"), "w", encoding="utf-8") as f:
        json.dump(icon, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("écrit kaki.icon (apparences claire et sombre)")


def main():
    calque = preparer_calque()
    apercu(calque, FOND_CLAIR, "kaki-1024-clair.png")
    apercu(calque, FOND_SOMBRE, "kaki-1024-sombre.png")
    fond_svg(FOND_CLAIR, "fond.svg")
    fond_svg(FOND_SOMBRE, "fond-sombre.svg")
    paquet_icon()


if __name__ == "__main__":
    main()
