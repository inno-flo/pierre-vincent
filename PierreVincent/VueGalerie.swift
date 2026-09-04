import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// Vue « galerie » (par icône) : chaque entrée est une vignette de l'image
/// (200×200 max), avec en dessous le prix et les dimensions.
struct VueGalerie: View {
    /// ESSAI TEMPORAIRE (voir `TestFondPage`, `Couleurs.swift`) : observé
    /// pour que cette vue se redessine quand le fond de page testé change,
    /// bien qu'elle ne s'en serve pas autrement. À retirer avec l'essai.
    @AppStorage(TestFondPage.cle) private var testFondPage = "creme"
    /// Accent de la rubrique — orange dans « Ventes et dons », bleu ardoise
    /// dans la Réserve. Posé sur la colonne de contenu, il descend jusqu'ici.
    @Environment(\.accentRubrique) private var accent
    #if os(macOS)
    @Environment(\.modelContext) private var context
    #endif

    let oeuvres: [Oeuvre]
    @Binding var selection: Set<UUID>
    /// Double-clic sur une carte : ouvre la fiche d'édition.
    var onOuvrir: (Oeuvre) -> Void
    /// Appui prolongé sur une vignette (iPhone). Nul = pas d'appui prolongé,
    /// ce qui est le cas de toutes les rubriques sauf celles qui déclarent la
    /// visionneuse intégrée.
    var onAppuiLong: ((Oeuvre) -> Void)? = nil
    /// Second item du menu contextuel, « Œuvres proches » (CLIP) — nul
    /// partout sauf sur la Réserve et ses sous-rubriques (`VueiOS`).
    var onOeuvreProcheCLIP: ((Oeuvre) -> Void)? = nil
    /// Espace de transition partagé avec la vue qui présente la visionneuse.
    /// Nul = pas de transition de zoom (macOS, ou rubrique sans visionneuse).
    var espaceZoom: Namespace.ID? = nil
    /// Affiche la ligne de nom en tête de légende (acheteur, destinataire ou
    /// emplacement). Fausse pour les enchères et les expositions, où seuls le
    /// prix et les dimensions renseignent.
    var nomEnGalerie: Bool = true
    /// En-tête facultatif, placé DANS la zone de défilement : il défile donc
    /// avec les vignettes. Sert au récapitulatif des vues iOS ; nul sur Mac.
    var entete: AnyView? = nil
    /// Pied de page facultatif, placé APRÈS la grille, dans la même zone de
    /// défilement. Sert au bouton « Supprimer les favoris… » ; nul ailleurs.
    var piedDePage: AnyView? = nil
    /// Identifiant de l'œuvre en tête d'écran, lu et écrit en continu par
    /// `.scrollPosition(id:)` : sert à synchroniser le défilement avec la
    /// présentation Liste au moment de basculer entre les deux (voir
    /// `VueFeuille`/`VueiOS`, qui possèdent cet état). `.constant(nil)` par
    /// défaut pour les appelants qui n'ont pas de présentation Liste à
    /// synchroniser.
    var positionDefilement: Binding<UUID?> = .constant(nil)

    // Ancre pour la sélection par plage (Maj + clic).
    @State private var derniere: UUID?

    #if os(iOS)
    // Visibilité du bouton flottant « Retour en haut » — voir
    // BoutonRetourHaut.swift. macOS n'en a pas.
    @State private var boutonHautVisible = false
    // Tout en haut de la grille — cible du bouton « Retour en haut ».
    private let ancreHaut = "ancre-haut"
    #endif

    #if os(macOS)
    // Largeur mesurée de la grille, pour déduire le nombre de colonnes.
    @State private var largeurGrille: CGFloat = 600
    @FocusState private var focusGalerie: Bool
    #endif

    // Colonnes de la grille :
    // - iPhone : 2 colonnes fixes (les images se réduisent pour tenir à 2 par rangée).
    // - Mac : grille adaptative selon la largeur disponible.
    private var colonnes: [GridItem] {
        #if os(iOS)
        return [GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)]
        #else
        return [GridItem(.adaptive(minimum: 200, maximum: 220), spacing: 16)]
        #endif
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                #if os(iOS)
                // Tout en haut : cible du bouton « Retour en haut ».
                Color.clear.frame(height: 0).id(ancreHaut)
                #endif
                entete
                LazyVGrid(columns: colonnes, spacing: 16) {
                    ForEach(oeuvres) { o in
                        carte(o)
                            .id(o.id)
                    }
                }
                // INDISPENSABLE à `.scrollPosition(id:)` ci-dessous : sans
                // elle, le binding ne reçoit JAMAIS l'œuvre en tête d'écran
                // et reste à `nil` — la synchronisation avec la Liste n'a
                // alors rien à restaurer. Elle désigne le conteneur dont les
                // enfants sont les repères de défilement.
                .scrollTargetLayout()
                .padding(16)
                piedDePage
            }
            .background(Color.cremeFond)
            // Synchronisation Galerie ↔ Liste : tient `positionDefilement` à
            // jour en continu avec l'œuvre en tête d'écran, et défile vers
            // elle à l'apparition si elle était déjà renseignée (retour
            // depuis la Liste).
            //
            // `anchor: .top` et non le défaut : c'est ce qui rend le repère
            // SYMÉTRIQUE — l'œuvre lue est celle du haut de l'écran, et c'est
            // en haut de l'écran qu'on la replace. Sans ancre explicite, le
            // système se contente de « rendre visible », ce qui autorise un
            // décalage d'un écran entier.
            .scrollPosition(id: positionDefilement, anchor: .top)
            // Fait défiler vers l'œuvre sélectionnée quand la sélection change
            // (utile lors de la navigation Précédent / Suivant de l'éditeur).
            .onChange(of: selection) { _, nouvelle in
                guard nouvelle.count == 1, let id = nouvelle.first else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            #if os(iOS)
            // Bouton « Retour en haut » — voir BoutonRetourHaut.swift.
            .retourEnHaut(visible: $boutonHautVisible) {
                withAnimation { proxy.scrollTo(ancreHaut, anchor: .top) }
            }
            #endif
            #if os(macOS)
            // Focus clavier sur le ScrollView pour recevoir les touches fléchées.
            // focusEffectDisabled() supprime l'anneau bleu de focus.
            // Focalisable UNIQUEMENT s'il y a une vignette sélectionnée : sinon
            // la galerie captait le focus dès l'ouverture d'une rubrique, la
            // sidebar le perdait (sélection qui vire au gris/marron) et ses ↑↓
            // ne répondaient plus. Même correctif que sur le Table du mode liste.
            .focusable(!selection.isEmpty)
            .focused($focusGalerie)
            .focusEffectDisabled()
            .onKeyPress(.leftArrow)  { naviguerClavier(delta: -1) }
            .onKeyPress(.rightArrow) { naviguerClavier(delta: +1) }
            .onKeyPress(.upArrow)    { naviguerClavier(delta: -nbColonnes) }
            .onKeyPress(.downArrow)  { naviguerClavier(delta: +nbColonnes) }
            .onKeyPress(.return) {
                guard selection.count == 1,
                      let id = selection.first,
                      let o = oeuvres.first(where: { $0.id == id }) else { return .ignored }
                onOuvrir(o)
                return .handled
            }
            // Overlay invisible pour mesurer la largeur sans perturber le layout.
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.size.width, initial: true) { _, w in
                            largeurGrille = w
                        }
                }
            }
            #endif
        }
    }

    #if os(macOS)
    // Nombre de colonnes déduit de la largeur mesurée, pour la navigation ↑↓.
    // La grille utilise adaptive(minimum: 200), spacing: 16 ; padding: 16 de chaque côté.
    private var nbColonnes: Int {
        let spacing: CGFloat = 16
        let padding: CGFloat = 32
        let available = max(1, largeurGrille - padding)
        return max(1, Int((available + spacing) / (200 + spacing)))
    }

    // Déplace la sélection de `delta` positions dans la liste ordonnée des œuvres.
    // Retourne .handled pour bloquer la propagation même si le bord est atteint.
    private func naviguerClavier(delta: Int) -> KeyPress.Result {
        guard selection.count == 1,
              let id = selection.first,
              let idx = oeuvres.firstIndex(where: { $0.id == id }) else { return .ignored }
        let nouveauIdx = idx + delta
        guard nouveauIdx >= 0, nouveauIdx < oeuvres.count else { return .handled }
        let nouvelle = oeuvres[nouveauIdx]
        selection = [nouvelle.id]
        derniere = nouvelle.id
        return .handled
    }
    #endif

    /// Police du prix et des dimensions dans la légende d'une vignette.
    /// 13 pt sur macOS : c'est `NSFont.systemFontSize`, la taille standard
    /// d'un libellé (`.subheadline` n'y vaut que 11 pt).
    /// Sur iOS on garde `.subheadline` (15 pt) : le 13 pt macOS n'y est pas
    /// la référence et rapetisserait le texte.
    private var policeLegende: Font {
        #if os(macOS)
        .system(size: 13)
        #else
        .subheadline
        #endif
    }

    private func carte(_ o: Oeuvre) -> some View {
        VStack(spacing: 0) {
            // Image en haut : cadre en PORTRAIT (proche du ratio réel des
            // photos de tableaux), pour ne rogner que très peu tout en
            // remplissant la carte. Essai de nouvelle présentation.
            ZStack {
                Color.gray.opacity(0.12)
                VignetteCacheeFlexible(nom: o.photoNom, coteSource: 320,
                                       preserverRatio: true)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3.0/4.0, contentMode: .fit)   // portrait 3:4
            .clipped()

            // Bande blanche en légende, sous l'image.
            // Textes forcés en sombre car le fond reste blanc dans les deux modes.
            VStack(alignment: .leading, spacing: 5) {
                // Le nom de l'acheteur (pour la feuille « données », le
                // destinataire, qui joue le même rôle) — `ligneGras` garde
                // son nom mais plus son gras, voir ESSAI VISUEL plus bas.
                if o.feuille == .reserve {
                    // Réserve : l'intitulé du champ d'abord, en gris, puis sa
                    // valeur — l'inverse se lisait mal, la valeur seule
                    // (« Natures mortes carton 2 ») ne disant pas de quoi il
                    // s'agit tant qu'on n'a pas lu la ligne suivante.
                    // Le champ montré dépend du type : voir `rangementVignette`.
                    Text(rangementVignette(o).intitule)
                        .font(policeLegende)
                        .foregroundStyle(Color.texteLegende.opacity(0.6))
                        .lineLimit(1)
                } else if nomEnGalerie {
                    // ESSAI VISUEL : `.headline` garde sa taille, mais plus
                    // sa graisse — même parti que les pastilles de filtre et
                    // le récapitulatif de Catalogue, ailleurs dans l'app.
                    Text(ligneGras(o).isEmpty ? " " : ligneGras(o))
                        .font(.headline)
                        .fontWeight(.regular)
                        .foregroundStyle(Color.texteLegende)
                        .lineLimit(1)
                }

                // En dessous : prix à gauche, dimensions à droite.
                // Le test porte sur l'ŒUVRE et non sur la rubrique affichée :
                // dans les vues agrégées (Inventaire, Ventes), une œuvre donnée
                // affichait « 0 € » sous sa vignette. Même correctif que dans
                // l'inspecteur. La vue n'a donc plus besoin qu'on lui passe le
                // caractère « don » de la rubrique.
                HStack {
                    if aUnPrix(o) {
                        PrixText(o.prix)
                            .foregroundStyle(accent)
                        Spacer()
                        Text(o.dimensions)
                            .foregroundStyle(Color.texteLegende.opacity(0.6))
                    } else if o.feuille == .reserve {
                        // La valeur, sous son intitulé.
                        Text(rangementVignette(o).valeur)
                            .foregroundStyle(Color.texteLegende)
                            .lineLimit(1)
                        Spacer()
                        Text(o.dimensions)
                            .foregroundStyle(Color.texteLegende.opacity(0.6))
                    } else {
                        // Dons : rien à gauche, les dimensions y viennent —
                        // sinon elles restaient plaquées à droite, seules,
                        // désalignées du destinataire juste au-dessus.
                        Text(o.dimensions)
                            .foregroundStyle(Color.texteLegende.opacity(0.6))
                        Spacer()
                    }
                }
                .font(policeLegende)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.fondLegende)
        }
        // Carte « photo posée » : fond blanc, coins arrondis, ombre douce.
        .background(Color.fondLegende)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selection.contains(o.id) ? accent : Color.filetVignette,
                              lineWidth: selection.contains(o.id) ? 3 : 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 5, x: 0, y: 2)
        .contentShape(Rectangle())
        #if os(iOS)
        // Source de la transition de zoom : la vignette s'agrandit pour
        // devenir la visionneuse, au lieu d'un remplacement sec.
        .modifier(SourceZoom(identifiant: o.id, espace: espaceZoom))
        #endif
        #if os(macOS)
        // Sur Mac : un clic sélectionne, un double-clic sélectionne PUIS ouvre
        // la fiche. Le double-clic n'appelait auparavant que `onOuvrir` : le
        // filet orange restait donc sur la vignette précédemment sélectionnée.
        // Sélection posée directement (et non via `cliquer`, qui tient compte
        // des touches Cmd/Maj) : un double-clic désigne toujours cette seule
        // vignette.
        .onTapGesture { cliquer(o) }
        .onTapGesture(count: 2) {
            selection = [o.id]
            derniere = o.id
            onOuvrir(o)
        }
        // Menu contextuel : pendant Mac de la commande du menu contextuel
        // iOS. Agit sur TOUTE la sélection si la vignette cliquée en fait
        // partie, sinon sur elle seule — même convention qu'un clic droit
        // standard sur une sélection multiple.
        .contextMenu {
            let cibles = selection.contains(o.id) ? selection : [o.id]
            let visees = oeuvres.filter { cibles.contains($0.id) }
            let toutFavori = !visees.isEmpty && visees.allSatisfy { $0.favori }
            Button(toutFavori ? "Retirer des favoris" : "Ajouter aux favoris") {
                let nouvelEtat = !toutFavori
                for v in visees { v.favori = nouvelEtat }
                try? context.save()
            }
        }
        // Glisser-déposer vers la rubrique Favoris de la sidebar : l'UUID
        // suffit, la cible retrouve l'œuvre via `toutes`. Voir
        // `ContentView.swift`, `.dropDestination` posé sur `lien(.favoris)`.
        //
        // Aperçu personnalisé, PETIT : sans lui, l'aperçu par défaut prend
        // toute la carte (image + légende), et l'animation de fin de dépôt
        // glissait vers le bas au lieu de s'estomper sur place — l'aperçu
        // par défaut d'une vue de cette taille semble suivre un chemin
        // d'animation différent de celui d'une petite vignette.
        //
        // `coteSource: 320, preserverRatio: true` — LES MÊMES valeurs que
        // la vignette de carte ci-dessus, pour retrouver la MÊME entrée du
        // cache. Un premier essai avec une taille inventée (60) tombait sur
        // une clé jamais préparée par personne : le cache renvoyait `nil`,
        // d'où l'icône « image manquante » à la place d'une vraie vignette.
        //
        // Sur une sélection multiple, `identifiantsGlisse(pour:)` embarque
        // TOUTE la sélection si la carte glissée en fait partie — même
        // règle que le menu contextuel ci-dessus — pas la seule vignette
        // sous le doigt. L'aperçu, lui, reste celui de CETTE carte : montrer
        // un aperçu par œuvre glissée n'apporterait rien de plus.
        .draggable(identifiantsGlisse(pour: o)) {
            VignetteCacheeFlexible(nom: o.photoNom, coteSource: 320, preserverRatio: true)
                .frame(width: 60, height: 60)
        }
        #else
        // Sur iPhone : tap et appui prolongé sont pris par une vue UIKit
        // posée en overlay. Elle seule peut prévenir d'un tap sur l'aperçu du
        // menu contextuel — le geste de Photos —, que SwiftUI n'expose pas.
        // Elle prend AUSSI le tap simple : sinon elle le confisquerait.
        .overlay(MenuApercuSiDemande(oeuvre: o,
                                     onTap: { onOuvrir(o) },
                                     onAfficher: onAppuiLong,
                                     onOeuvreProche: onOeuvreProcheCLIP))
        #endif
    }

    #if os(macOS)
    /// Charge utile du glisser-déposer vers Favoris (`ContentView.swift`) :
    /// TOUTE la sélection courante si la carte glissée en fait partie —
    /// même règle que le menu contextuel ci-dessus — sinon cette seule
    /// œuvre. Les UUID sont joints par une virgule ; la cible
    /// (`ajouterAuxFavoris`) les sépare avant de résoudre chaque œuvre.
    private func identifiantsGlisse(pour o: Oeuvre) -> String {
        let cibles = selection.contains(o.id) ? selection : [o.id]
        return cibles.map { $0.uuidString }.joined(separator: ",")
    }
    #endif

    /// Texte de la ligne en gras : le nom de l'acheteur pour les ventes,
    /// le destinataire pour les dons.
    /// Texte de la ligne en gras : le nom de l'acheteur s'il existe, sinon le
    /// destinataire (utile dans la vue « Œuvres » qui compile ventes ET dons).
    private func ligneGras(_ o: Oeuvre) -> String {
        // Le champ se choisit sur la FEUILLE, jamais sur le vide : depuis la
        // reprise « Inconnu », `acheteur` n'est plus jamais vide sur un don —
        // il contient ce mot — et un test d'emptiness affichait donc
        // « Inconnu » à la place du destinataire.
        if o.feuille == .oeuvresDonnees { return afficher(o.destinataire) }
        return afficher(o.acheteur)
    }

    /// Gère le clic selon les touches enfoncées, comme dans la vue liste :
    /// - Cmd : ajoute/retire l'entrée de la sélection.
    /// - Maj : sélectionne toute la plage depuis la dernière entrée cliquée.
    /// - sans touche : sélectionne uniquement cette entrée.
    private func cliquer(_ o: Oeuvre) {
        #if os(macOS)
        let mod = NSEvent.modifierFlags
        if mod.contains(.command) {
            if selection.contains(o.id) { selection.remove(o.id) } else { selection.insert(o.id) }
            derniere = o.id
        } else if mod.contains(.shift), let ancre = derniere,
                  let iA = oeuvres.firstIndex(where: { $0.id == ancre }),
                  let iC = oeuvres.firstIndex(where: { $0.id == o.id }) {
            for idx in min(iA, iC)...max(iA, iC) { selection.insert(oeuvres[idx].id) }
        } else {
            selection = [o.id]
            derniere = o.id
        }
        // Focus demandé APRÈS la mise à jour de la sélection : la galerie
        // n'est focalisable que si la sélection est non vide (voir plus haut),
        // donc une demande faite avant serait purement et simplement ignorée.
        focusGalerie = !selection.isEmpty
        #else
        // iPhone (consultation) : un simple tap sélectionne l'entrée.
        selection = [o.id]
        derniere = o.id
        #endif
    }
}


#if os(iOS)
/// Pose le menu contextuel quand la rubrique propose la visionneuse.
/// Enveloppé parce que l'action est optionnelle : sans elle, pas de menu.
struct MenuApercuSiDemande: View {
    let oeuvre: Oeuvre
    let onTap: () -> Void
    /// Nul quand la rubrique ne propose pas la visionneuse : le menu
    /// contextuel n'aurait alors rien à montrer.
    let onAfficher: ((Oeuvre) -> Void)?
    /// Commande « Œuvres proches » (CLIP), en second dans le menu — nul
    /// partout sauf sur la Réserve et ses sous-rubriques.
    var onOeuvreProche: ((Oeuvre) -> Void)? = nil

    var body: some View {
        if let onAfficher {
            InteractionApercu(oeuvre: oeuvre,
                              onTap: onTap,
                              onAfficher: { onAfficher(oeuvre) },
                              onOeuvreProche: onOeuvreProche.map { cl in { cl(oeuvre) } })
        } else {
            Color.clear.allowsHitTesting(false)
        }
    }
}

/// Marque une vue comme point de départ de la transition de zoom.
///
/// Enveloppé dans un `ViewModifier` parce que `matchedTransitionSource` exige
/// un `Namespace.ID` non optionnel : la vue appelante, elle, n'en a pas
/// toujours un (macOS, ou rubrique sans visionneuse).
struct SourceZoom: ViewModifier {
    let identifiant: UUID
    let espace: Namespace.ID?

    func body(content: Content) -> some View {
        if let espace {
            content.matchedTransitionSource(id: identifiant, in: espace)
        } else {
            content
        }
    }
}
#endif
