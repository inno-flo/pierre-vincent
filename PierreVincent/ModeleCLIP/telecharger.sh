#!/bin/sh
# Télécharge l'encodeur d'image MobileCLIP-S0 (Apple, Core ML), pour la
# rubrique « Affinités CLIP ». Voir README.md pour la licence.
set -e
cd "$(dirname "$0")"
BASE="https://huggingface.co/apple/coreml-mobileclip/resolve/main/mobileclip_s0_image.mlpackage"
DEST="mobileclip_s0_image.mlpackage"
mkdir -p "$DEST/Data/com.apple.CoreML/weights"
curl -sL "$BASE/Manifest.json" -o "$DEST/Manifest.json"
curl -sL "$BASE/Data/com.apple.CoreML/model.mlmodel" -o "$DEST/Data/com.apple.CoreML/model.mlmodel"
curl -sL "$BASE/Data/com.apple.CoreML/weights/weight.bin" -o "$DEST/Data/com.apple.CoreML/weights/weight.bin"
echo "OK : $DEST"
