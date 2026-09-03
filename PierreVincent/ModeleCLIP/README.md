# Modèle CLIP (essai de comparaison)

Ce dossier contient **MobileCLIP-S0** (encodeur d'image seul), converti en
Core ML par Apple, utilisé par la rubrique « Affinités CLIP » pour comparer
ses regroupements à ceux du moteur maison de « Affinités ».

## Pourquoi ce fichier n'est PAS versionné dans Git

`mobileclip_s0_image.mlpackage` (~23 Mo) est exclu par `.gitignore`, pour
deux raisons :

1. **Licence.** Les poids sont sous la licence recherche d'Apple
   (« Apple Machine Learning Research Model License »), qui limite l'usage
   aux « Research Purposes » — explicitement PAS à « tout produit ou
   service commercial », ni au « développement de produit ». Convient à un
   essai de comparaison ; à reconsidérer avant tout usage durable dans l'app
   distribuée. Texte complet :
   https://github.com/apple/ml-mobileclip/blob/main/LICENSE_MODELS
2. **Poids binaire.** 23 Mo de données qui n'ont pas leur place dans
   l'historique Git, au même titre que les images de travail déjà exclues.

## Comment le récupérer

```bash
./telecharger.sh
```

Ou manuellement, depuis https://huggingface.co/apple/coreml-mobileclip :
`mobileclip_s0_image.mlpackage` (Manifest.json + Data/com.apple.CoreML/…).

Une fois le dossier `mobileclip_s0_image.mlpackage` présent ici, Xcode le
compile automatiquement (groupe synchronisé) — rien d'autre à faire.
