#if os(macOS)
import SwiftUI
import AppKit

/// Visionneuse d'images occupant tout le panneau de contenu.
///
/// **Essai limité à Réserve › Catalogue** (`Categorie.visionneuseIntegree`).
/// Elle y remplace Quick Look sur la barre d'espace ; l'appel à Quick Look
/// reste en place pour toutes les autres rubriques, et rien n'a été supprimé —
/// on peut y revenir si cette voie ne convient pas.
///
/// Elle est posée en `overlay` sur le panneau, et non en `.sheet` : une feuille
/// se présente au-dessus de TOUTE la fenêtre, sidebar et barre d'outils
/// comprises, alors qu'on veut rester dans les limites du panneau.
struct VisionneusePanneau: View {
    /// Accent de la rubrique — orange dans « Ventes et dons », bleu ardoise
    /// dans la Réserve. Posé sur la colonne de contenu, il descend jusqu'ici.
    @Environment(\.accentRubrique) private var accent

    /// Œuvres parcourables — celles qui ont réellement une photo.
    let oeuvres: [Oeuvre]
    /// Position courante dans `oeuvres`.
    @Binding var index: Int
    let onFermer: () -> Void

    /// Facteur de zoom acquis, entre 1 (image entière) et 5.
    @State private var echelle: CGFloat = 1
    /// Zoom du geste en cours, rendu à 1 dès que les doigts se lèvent.
    @GestureState private var zoomEnCours: CGFloat = 1
    /// Déplacement acquis dans l'image agrandie, et celui du geste en cours.
    @State private var decalage: CGSize = .zero
    @GestureState private var decalageEnCours: CGSize = .zero

    private static let echelleMin: CGFloat = 1
    private static let echelleMax: CGFloat = 5

    private var echelleEffective: CGFloat {
        min(max(echelle * zoomEnCours, Self.echelleMin), Self.echelleMax)
    }

    private var decalageEffectif: CGSize {
        CGSize(width: decalage.width + decalageEnCours.width,
               height: decalage.height + decalageEnCours.height)
    }

    /// Le déplacement n'a de sens qu'une fois l'image agrandie : à l'échelle 1
    /// elle tient entièrement dans le cadre, il n'y a rien à aller chercher.
    private var deplacementPossible: Bool { echelleEffective > 1 }

    private var oeuvreCourante: Oeuvre? {
        oeuvres.indices.contains(index) ? oeuvres[index] : nil
    }

    var body: some View {
        ZStack {
            // Fond opaque : l'image doit se détacher du contenu qu'elle couvre.
            // PAS de `ignoresSafeArea()` : il faisait déborder le noir sous la
            // sidebar et l'inspecteur, qui sont translucides et échantillonnent
            // ce qu'il y a derrière — d'où leurs fonds virant au gris foncé.
            Color.black.opacity(0.92)

            if let o = oeuvreCourante {
                VStack(spacing: 16) {
                    // Le bouton de fermeture a SA PROPRE RANGÉE, au lieu d'être
                    // posé en overlay : ainsi l'image ne passe jamais dessous,
                    // même en fenêtre étroite où elle occupe toute la largeur.
                    HStack {
                        Spacer()
                        boutonFermer
                    }
                    image(pour: o)
                    legende(de: o)
                    barreNavigation
                }
                .padding(24)
            }
        }
        // Empêche les clics d'atteindre la galerie ou le tableau en dessous.
        .contentShape(Rectangle())
        .onTapGesture { }
        // Échap ferme la visionneuse. Le capteur n'est monté que tant qu'elle
        // est à l'écran, donc Échap garde son sens ailleurs dans l'app.
        .background(CaptureEchap { onFermer() })
        // ← et → défilent les images ici, et NON dans la galerie en dessous,
        // qui porte ses propres raccourcis. Le capteur consomme l'événement.
        // Les quatre flèches appartiennent à la visionneuse tant qu'elle est
        // ouverte : ←→ changent d'image, ↑↓ sont absorbées pour ne plus
        // déplacer la sélection dans la vue en arrière-plan.
        .background(CaptureFlechesLaterales(
            onGauche: { if index > 0 { index -= 1 } },
            onDroite: { if index < oeuvres.count - 1 { index += 1 } }))
        // Changer d'image repart de l'image entière : garder le zoom ferait
        // arriver sur un détail de la suivante, sans rapport avec ce qu'on
        // regardait.
        .onChange(of: index) { _, _ in
            echelle = 1
            decalage = .zero
        }
    }

    // MARK: Éléments

    @ViewBuilder
    private func image(pour o: Oeuvre) -> some View {
        if let img = PhotoStore.chargerImage(nom: o.photoNom) {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .scaleEffect(echelleEffective)
                .offset(decalageEffectif)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Sans découpe, l'image agrandie déborderait sur la légende
                // et sur les boutons de navigation.
                .clipped()
                // Borne la zone SENSIBLE au cadre. `clipped()` ne découpe que
                // le dessin : sans ceci, l'image agrandie restait cliquable
                // bien au-delà et interceptait la croix de fermeture, qui
                // devenait inopérante dès qu'on avait zoomé.
                .contentShape(Rectangle())
                // Pincement du trackpad : écarter agrandit, resserrer réduit.
                // `updating` suit le geste en direct, `onEnded` fige le
                // facteur atteint — borné entre 1 et 5.
                .gesture(
                    MagnifyGesture()
                        .updating($zoomEnCours) { valeur, etat, _ in
                            etat = valeur.magnification
                        }
                        .onEnded { valeur in
                            echelle = min(max(echelle * valeur.magnification,
                                              Self.echelleMin), Self.echelleMax)
                            // Revenu à l'image entière : on recentre, sinon
                            // elle resterait décalée sans raison visible.
                            if echelle == Self.echelleMin { decalage = .zero }
                        }
                )
                // Déplacement dans l'image agrandie, en parallèle du pincement.
                .simultaneousGesture(
                    DragGesture()
                        .updating($decalageEnCours) { valeur, etat, _ in
                            guard deplacementPossible else { return }
                            etat = valeur.translation
                        }
                        .onEnded { valeur in
                            guard deplacementPossible else { return }
                            decalage.width += valeur.translation.width
                            decalage.height += valeur.translation.height
                        }
                )
        } else {
            // La photo est référencée mais illisible : on le dit plutôt que
            // d'afficher un rectangle vide sans explication.
            VStack(spacing: 10) {
                Image(systemName: "photo")
                    .font(.system(size: 48))
                Text("Image introuvable")
            }
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func legende(de o: Oeuvre) -> some View {
        VStack(spacing: 4) {
            Text(afficher(o.emplacement))
                .font(.system(size: 13))
                .foregroundStyle(.white)
            Text(o.dimensions)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var barreNavigation: some View {
        HStack(spacing: 24) {
            bouton("chevron.left", aide: "Image précédente", actif: index > 0) {
                index -= 1
            }
            Text("\(index + 1) / \(oeuvres.count)")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .frame(minWidth: 70)
            bouton("chevron.right", aide: "Image suivante",
                   actif: index < oeuvres.count - 1) {
                index += 1
            }
        }
    }

    private var boutonFermer: some View {
        Button(action: onFermer) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
                .background(pastille(actif: true))
        }
        .buttonStyle(.plain)
        .help("Fermer")
    }

    private func bouton(_ symbole: String, aide: String,
                        actif: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(actif ? 1 : 0.3))
                .padding(12)
                .background(pastille(actif: actif))
        }
        .buttonStyle(.plain)
        .disabled(!actif)
        .help(aide)
    }

    /// Fond des boutons : cercle opaque cerclé d'orange, sur le modèle des
    /// pastilles de comptage. Le contour s'atténue quand le bouton est inerte
    /// — en bout de série — sans disparaître, pour que la rangée garde sa
    /// forme.
    private func pastille(actif: Bool) -> some View {
        Circle()
            .fill(.black.opacity(0.55))
            .overlay(
                Circle().strokeBorder(
                    accent.opacity(actif ? 1 : 0.35),
                    lineWidth: 1)
            )
    }
}
#endif
