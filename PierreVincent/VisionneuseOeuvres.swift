#if os(iOS)
import SwiftUI
import UIKit

/// Visionneuse plein écran parcourant PLUSIEURS œuvres — pendant iPhone de
/// `VisionneusePanneau` (macOS), avec la même croix, les mêmes chevrons et le
/// même compteur.
///
/// À ne pas confondre avec `VisionneuseImagePleinEcran`, qui montre UNE photo
/// et s'ouvre depuis la fiche de détail : les deux coexistent, celle-ci
/// s'ouvrant par appui prolongé sur une vignette de galerie.
///
/// En place dans TOUTES les rubriques (`Categorie.visionneuseIntegree`), comme
/// sur Mac.
struct VisionneuseOeuvres: View {
    /// Œuvres parcourables — celles qui ont réellement une photo.
    let oeuvres: [Oeuvre]
    @State var index: Int
    /// Appelé à CHAQUE changement d'image — balayage, chevrons — pour que la
    /// liste en arrière-plan suive. Sans cela l'index reste enfermé ici
    /// (`@State`) et fermer la visionneuse ramenait sur l'œuvre de départ.
    var onNaviguer: (Oeuvre) -> Void = { _ in }
    /// Cadre écran de la vignette d'où l'on vient, quand la transition est
    /// faite à la main (`TransitionVisionneuse.ressortMaison`). Nul avec la
    /// transition système, qui s'en charge elle-même.
    var cadreDepart: CGRect? = nil
    let onFermer: () -> Void

    // Échelle et décalage courants, et leurs valeurs de référence au début de
    // chaque geste — même patron que `VisionneuseImagePleinEcran`, pour que
    // les deux visionneuses se manipulent de la même façon.
    @State private var echelle: CGFloat = 1
    @State private var echelleReference: CGFloat = 1
    @State private var decalage: CGSize = .zero
    @State private var decalageReference: CGSize = .zero

    private let echelleMin: CGFloat = 1
    private let echelleMax: CGFloat = 5
    /// Amplitude minimale d'un balayage pour qu'il change d'image.
    private let seuilBalayage: CGFloat = 60
    /// Durée de la transition, alignée sur celle de `DetailiOS`.
    private let dureeTransition: Double = 0.25

    // Sens du dernier changement, pour orienter la transition (+1 / -1).
    @State private var sensTransition = 1
    // Verrou : empêche un nouveau changement pendant l'animation, sinon deux
    // transitions se chevauchent et l'affichage se fige. Même précaution que
    // dans `DetailiOS`.
    @State private var enTransition = false

    /// Vrai une fois l'ouverture jouée : l'image occupe alors tout l'écran.
    /// Faux au premier rendu, où elle épouse encore le cadre de la vignette.
    @State private var ouverte = false

    private var oeuvreCourante: Oeuvre? {
        oeuvres.indices.contains(index) ? oeuvres[index] : nil
    }

    /// Échelle et décalage de l'ANIMATION D'OUVERTURE, distincts du zoom que
    /// l'utilisateur applique ensuite. À l'état fermé, l'image est réduite et
    /// déplacée pour coïncider avec la vignette de départ.
    private func ouvertureDepuisVignette(_ ecran: CGSize) -> (CGFloat, CGSize) {
        guard TransitionVisionneuse.estRessort, !ouverte,
              let cadre = cadreDepart, ecran.width > 0, ecran.height > 0
        else { return (1, .zero) }
        let facteur = min(cadre.width / ecran.width, cadre.height / ecran.height)
        return (facteur,
                CGSize(width: cadre.midX - ecran.width / 2,
                       height: cadre.midY - ecran.height / 2))
    }

    var body: some View {
        GeometryReader { geo in
            corps(ecran: geo.size)
        }
        .ignoresSafeArea()
    }

    private func corps(ecran: CGSize) -> some View {
        let (facteur, decalageOuverture) = ouvertureDepuisVignette(ecran)
        return ZStack {
            // Plein écran, encoche et barres système comprises : c'est ce qui
            // fait tenir la vue en paysage comme en portrait.
            Color.black.ignoresSafeArea()
                // Le fond se révèle avec l'image : apparaître d'un bloc
                // trahirait le déplacement qu'on cherche à montrer.
                .opacity(TransitionVisionneuse.estRessort && !ouverte ? 0 : 1)

            // ZStack indispensable : sans lui, SwiftUI ne superpose pas
            // l'ancienne et la nouvelle image pendant l'animation, et le
            // glissement latéral ne se voit pas — juste un remplacement sec.
            ZStack {
                if let o = oeuvreCourante {
                    image(de: o)
                        // Identité liée à l'œuvre : SwiftUI anime le
                        // remplacement à chaque changement d'image.
                        .id(o.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: sensTransition > 0 ? .trailing : .leading)
                                .combined(with: .opacity),
                            removal: .move(edge: sensTransition > 0 ? .leading : .trailing)
                                .combined(with: .opacity)
                        ))
                }
            }

            VStack {
                HStack {
                    Spacer()
                    boutonFermer
                }
                Spacer()
                barreNavigation
            }
            .padding(20)
            // Les commandes n'arrivent qu'une fois l'image en place.
            .opacity(TransitionVisionneuse.estRessort && !ouverte ? 0 : 1)
        }
        // L'agrandissement porte sur TOUT le contenu, image et commandes.
        .scaleEffect(facteur)
        .offset(decalageOuverture)
        .statusBarHidden()
        // Déclenche l'ouverture au premier rendu : l'état de départ a été
        // dessiné, le ressort a donc quelque chose à animer.
        .task {
            guard TransitionVisionneuse.estRessort, !ouverte else { return }
            withAnimation(TransitionVisionneuse.ressort) { ouverte = true }
        }
        // Changer d'image repart de l'image entière et recentrée : garder le
        // zoom ferait arriver sur un détail arbitraire de la suivante.
        .onChange(of: index) { _, nouveau in
            reinitialiserZoom()
            if oeuvres.indices.contains(nouveau) { onNaviguer(oeuvres[nouveau]) }
        }
        // Position de départ : la vue de fond peut déjà être ailleurs si la
        // visionneuse a été ouverte depuis une vignette non sélectionnée.
        .onAppear {
            if oeuvres.indices.contains(index) { onNaviguer(oeuvres[index]) }
        }
    }

    // MARK: Éléments

    @ViewBuilder
    private func image(de o: Oeuvre) -> some View {
        if let img = PhotoStore.chargerImage(nom: o.photoNom) {
            Image(imagePlateforme: img)
                .resizable()
                .scaledToFit()
                .scaleEffect(echelle)
                .offset(decalage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(gesteCombine)
                // Double-tap : retour rapide à l'image entière.
                .onTapGesture(count: 2) { reinitialiserZoom() }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo").font(.system(size: 48))
                Text("Image introuvable")
            }
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var barreNavigation: some View {
        HStack(spacing: 28) {
            bouton("chevron.left", actif: index > 0) { naviguer(-1) }
            Text("\(index + 1) / \(oeuvres.count)")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .frame(minWidth: 70)
            bouton("chevron.right", actif: index < oeuvres.count - 1) { naviguer(1) }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
    }

    private var boutonFermer: some View {
        Button(action: onFermer) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(pastille(actif: true))
        }
        .accessibilityLabel("Fermer")
    }

    private func bouton(_ symbole: String, actif: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(actif ? 1 : 0.3))
                .frame(width: 34, height: 34)
                .background(pastille(actif: actif))
        }
        .disabled(!actif)
    }

    /// Fond des boutons : cercle opaque cerclé d'orange, sur le modèle des
    /// pastilles de comptage — et identique à la visionneuse macOS.
    private func pastille(actif: Bool) -> some View {
        Circle()
            .fill(.black.opacity(0.55))
            .overlay(
                Circle().strokeBorder(
                    Color.orangeInternational.opacity(actif ? 1 : 0.35),
                    lineWidth: 1)
            )
    }

    // MARK: Gestes

    /// Pincement (zoom) et glissement (déplacement), simultanés.
    private var gesteCombine: some Gesture {
        let pincement = MagnificationGesture()
            .onChanged { valeur in
                echelle = min(max(echelleReference * valeur, echelleMin), echelleMax)
            }
            .onEnded { _ in
                echelleReference = echelle
                if echelle <= echelleMin { reinitialiserZoom() }
            }

        let glissement = DragGesture()
            .onChanged { valeur in
                // Inerte à l'échelle 1 : l'image tient entière à l'écran, et
                // un glissement libre y serait sans objet.
                guard echelle > echelleMin else { return }
                decalage = CGSize(
                    width: decalageReference.width + valeur.translation.width,
                    height: decalageReference.height + valeur.translation.height)
            }
            .onEnded { valeur in
                // À l'échelle 1, le glissement ne déplace rien : il sert alors
                // à passer d'une image à l'autre. Une fois zoomé, il reprend
                // son rôle de déplacement — les deux ne peuvent pas coexister
                // sur le même geste.
                guard echelle > echelleMin else {
                    balayer(valeur.translation)
                    return
                }
                decalageReference = decalage
            }

        return pincement.simultaneously(with: glissement)
    }

    /// Change d'image sur un balayage franchement horizontal.
    ///
    /// On exige que la composante horizontale l'emporte sur la verticale : un
    /// geste de biais, ou une amorce de défilement, ne doit pas faire défiler
    /// les images à l'insu de l'utilisateur.
    private func balayer(_ translation: CGSize) {
        guard abs(translation.width) > abs(translation.height),
              abs(translation.width) > seuilBalayage else { return }
        // Vers la droite = image précédente, vers la gauche = suivante.
        naviguer(translation.width > 0 ? -1 : 1)
    }

    /// Passe à l'image précédente (-1) ou suivante (+1), avec la transition
    /// glissée. Point de passage UNIQUE — chevrons comme balayage — pour que
    /// le sens de l'animation et le verrou soient posés dans tous les cas.
    private func naviguer(_ sens: Int) {
        guard !enTransition else { return }
        let nouvel = index + sens
        guard nouvel >= 0, nouvel < oeuvres.count else { return }
        sensTransition = sens
        enTransition = true
        withAnimation(.easeInOut(duration: dureeTransition)) {
            index = nouvel
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dureeTransition) {
            enTransition = false
        }
    }

    private func reinitialiserZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            echelle = 1
            decalage = .zero
        }
        echelleReference = 1
        decalageReference = .zero
    }
}
#endif
