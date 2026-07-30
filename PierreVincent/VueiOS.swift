#if os(iOS)
import SwiftUI
import SwiftData

/// Vue de consultation pour iPhone/iPad (lecture seule).
/// Affiche les entrées d'une catégorie en liste ou en galerie, avec accès
/// à une fiche de détail (photo, prix, informations) au toucher.
struct VueiOS: View {
    let feuille: Feuille?          // nil = vue compilée « Œuvres »
    let titre: String

    @Query private var toutes: [Oeuvre]
    @State private var tri: [KeyPathComparator<Oeuvre>] = [
        KeyPathComparator(\Oeuvre.type)
    ]
    // Mode d'affichage, conservé entre les sessions (comme sur Mac).
    @AppStorage("modeAffichage") private var modeAffichage: String = "liste"
    // Critère de tri de la galerie (partagé avec le Mac via le même réglage).
    @AppStorage("triGalerie") private var triGalerie: String = "prix"
    // Sens du tri : true = croissant (du plus petit au plus grand).
    @AppStorage("triCroissant") private var triCroissant: Bool = false
    @State private var selection: Set<UUID> = []
    @State private var detail: Oeuvre?

    /// Œuvres de cette catégorie (ou compilation des 4).
    private var oeuvres: [Oeuvre] {
        let base: [Oeuvre]
        if let f = feuille {
            base = toutes.filter { $0.feuille == f }
        } else {
            base = toutes
        }
        return base.sorted(using: tri)
    }

    private var estFeuilleDon: Bool { feuille == .oeuvresDonnees }

    /// Œuvres triées pour la galerie, selon le critère choisi (prix ou acheteur).
    private var oeuvresGalerie: [Oeuvre] {
        let base: [Oeuvre]
        if let f = feuille {
            base = toutes.filter { $0.feuille == f }
        } else {
            base = toutes
        }
        // Critère effectif : on retombe sur un tri pertinent si le critère
        // mémorisé ne s'applique pas à cette feuille (ex. prix dans les dons,
        // dimensions dans les tapis).
        var critere = triGalerie
        if estFeuilleDon, critere == "prix" { critere = "dimensions" }
        if feuille == .tapisVendus, critere == "dimensions" { critere = "prix" }

        // Tri de base, toujours calculé en ordre CROISSANT
        // (du plus petit / début d'alphabet au plus grand).
        let triees: [Oeuvre]
        switch critere {
        case "acheteur":
            // Pour les dons, l'acheteur est vide : on trie alors sur le
            // destinataire, qui joue le même rôle dans l'affichage.
            func nom(_ o: Oeuvre) -> String {
                !o.acheteur.isEmpty ? o.acheteur : o.destinataire
            }
            triees = base.sorted { nom($0).localizedCaseInsensitiveCompare(nom($1)) == .orderedAscending }
        case "dimensions":
            // Tri par SURFACE (largeur × hauteur) plutôt que par texte.
            triees = base.sorted { surfaceDimensions($0.dimensions) < surfaceDimensions($1.dimensions) }
        default: // "prix"
            triees = base.sorted { $0.prix < $1.prix }
        }
        // Le bouton d'ordre inverse la liste si l'on veut du plus grand au plus petit.
        return triCroissant ? triees : triees.reversed()
    }

    var body: some View {
        Group {
            if modeAffichage == "icone" {
                VueGalerie(
                    oeuvres: oeuvresGalerie,
                    estFeuilleDon: estFeuilleDon,
                    selection: $selection,
                    onOuvrir: { o in detail = o }
                )
            } else {
                liste
            }
        }
        .navigationTitle(titre)
        .toolbar {
            // Un seul set de contrôles, compact : Liste, Galerie, tri, sens.
            // Regroupés dans un HStack pour maîtriser l'espacement (plus serré
            // que l'espacement par défaut d'un ToolbarItemGroup).
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {

                // 1. Vue Liste.
                Button {
                    modeAffichage = "liste"
                } label: {
                    Image(systemName: "list.bullet")
                }
                .disabled(modeAffichage == "liste")

                // 2. Vue Galerie.
                Button {
                    modeAffichage = "icone"
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .disabled(modeAffichage == "icone")

                // 3. Critère de tri (selon la feuille affichée).
                Menu {
                    // Prix : sans objet pour les dons (pas de prix).
                    if !estFeuilleDon {
                        Button {
                            triGalerie = "prix"
                        } label: {
                            Label(triGalerie == "prix" ? "✓ Prix" : "Prix",
                                  systemImage: "eurosign")
                        }
                    }
                    Button {
                        triGalerie = "acheteur"
                    } label: {
                        Label(triGalerie == "acheteur" ? "✓ Acheteur" : "Acheteur",
                              systemImage: "person")
                    }
                    // Dimensions : proposé partout sauf pour les tapis.
                    if feuille != .tapisVendus {
                        Button {
                            triGalerie = "dimensions"
                        } label: {
                            Label(triGalerie == "dimensions" ? "✓ Dimensions" : "Dimensions",
                                  systemImage: "ruler")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }

                // 4. Sens du tri : on utilise UNE seule icône (dont l'existence
                // est certaine) que l'on retourne verticalement pour figurer le
                // sens inverse. Les longueurs des traits s'inversent ainsi :
                // décroissant = grand/moyen/petit, croissant = petit/moyen/grand.
                Button {
                    triCroissant.toggle()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .scaleEffect(x: 1, y: triCroissant ? -1 : 1)
                }
                .id("bouton-sens-tri")
                }
            }
        }
        // Fiche de détail au toucher d'une entrée.
        .sheet(item: $detail) { o in
            DetailiOS(oeuvre: o, estFeuilleDon: estFeuilleDon,
                      listeNavigation: modeAffichage == "icone" ? oeuvresGalerie : oeuvres)
        }
    }

    /// Liste en blocs séparés sur fond beige (même style que la vue « Œuvres »).
    private var liste: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(oeuvresGalerie) { o in
                    Button {
                        detail = o
                    } label: {
                        HStack(spacing: 12) {
                            VignetteCachee(nom: o.photoNom, cote: 64)
                            VStack(alignment: .leading, spacing: 3) {
                                if !estFeuilleDon {
                                    // Acheteur en premier (mis en avant), puis prix.
                                    Text(o.acheteur.isEmpty ? "—" : o.acheteur)
                                        .font(.headline)
                                        .lineLimit(1)
                                    PrixText(o.prix)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.orangeInternational)
                                    if !o.modeVente.isEmpty {
                                        Text(o.modeVente)
                                            .font(.body).foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                } else if !o.destinataire.isEmpty {
                                    Text(o.destinataire)
                                        .font(.headline).lineLimit(1)
                                }
                                // Le type n'est PAS affiché ici : ces vues ne
                                // contiennent qu'un seul type d'œuvre.
                                if !o.dimensions.isEmpty {
                                    Text(o.dimensions)
                                        .font(.body).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .frame(height: 88)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.fondLegende)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .background(Color.cremeFond)
    }
}

/// Fiche de détail d'une entrée (lecture seule) pour iPhone/iPad.
struct DetailiOS: View {
    let oeuvre: Oeuvre
    let estFeuilleDon: Bool
    /// Liste ordonnée pour naviguer Précédent / Suivant (ordre d'affichage).
    var listeNavigation: [Oeuvre] = []
    @Environment(\.dismiss) private var dismiss

    // Œuvre affichée (change avec les chevrons) et sa position dans la liste.
    @State private var courante: Oeuvre?
    @State private var indexCourant = 0
    // Sens du dernier changement, pour orienter la transition (+1 / -1).
    @State private var sensTransition = 1

    /// Œuvre réellement affichée (la courante, ou celle passée à l'ouverture).
    private var oeuvreAffichee: Oeuvre { courante ?? oeuvre }

    var body: some View {
        NavigationStack {
            ScrollView {
                contenuFiche
                    // Identité liée à l'œuvre : SwiftUI anime le remplacement
                    // du contenu à chaque changement.
                    .id(oeuvreAffichee.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: sensTransition > 0 ? .trailing : .leading)
                            .combined(with: .opacity),
                        removal: .move(edge: sensTransition > 0 ? .leading : .trailing)
                            .combined(with: .opacity)
                    ))
            }
            .background(Color.cremeFond)
            // Navigation par glissement latéral : vers la gauche = suivant,
            // vers la droite = précédent.
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { valeur in
                        // On ne réagit qu'aux glissements franchement horizontaux.
                        let dx = valeur.translation.width
                        let dy = valeur.translation.height
                        guard abs(dx) > abs(dy), abs(dx) > 60 else { return }
                        if dx < 0 {
                            naviguer(1)   // glissement vers la gauche → suivant
                        } else {
                            naviguer(-1)  // glissement vers la droite → précédent
                        }
                    }
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Deux boutons natifs séparés par un ToolbarSpacer : sur iOS 26,
                // chacun reçoit son propre fond « liquid glass » au lieu d'être
                // fusionnés dans une capsule commune.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        naviguer(-1)
                    } label: { Image(systemName: "chevron.left") }
                        .disabled(indexCourant <= 0)
                }
                ToolbarSpacer(.fixed, placement: .topBarLeading)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        naviguer(1)
                    } label: { Image(systemName: "chevron.right") }
                        .disabled(indexCourant >= listeNavigation.count - 1)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .onAppear {
                courante = oeuvre
                if let i = listeNavigation.firstIndex(where: { $0.id == oeuvre.id }) {
                    indexCourant = i
                }
            }
        }
    }

    /// Contenu de la fiche (extrait pour alléger la vérification de type).
    private var contenuFiche: some View {
        let oeuvre = oeuvreAffichee
        return VStack(alignment: .leading, spacing: 12) {
            // Grande image.
            if let img = PhotoStore.chargerImage(nom: oeuvre.photoNom) {
                Image(imagePlateforme: img).resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .cornerRadius(12)
            }

            // Cellule 1 : Prix (sauf dons).
            if !estFeuilleDon {
                cellule {
                    ligne("Prix", formaterEuros(oeuvre.prix),
                          couleur: Color.orangeInternational, estPrix: true)
                }
            }

            // Cellule 2 : Type.
            cellule {
                ligne("Type", oeuvre.type)
            }

            // Cellule 3 : Dimensions et Format.
            cellule {
                ligne("Dimensions", oeuvre.dimensions)
                ligne("Format", oeuvre.format)
            }

            // Cellule 4 : Vendeur, Acheteur (ou Destinataire), Mode de vente.
            cellule {
                if estFeuilleDon {
                    ligne("Destinataire", oeuvre.destinataire)
                } else {
                    ligne("Vendeur", oeuvre.vendeur)
                    ligne("Acheteur", oeuvre.acheteur)
                    ligne("Mode de vente", oeuvre.modeVente)
                }
            }

            // Cellule 5 : Date (sauf dons).
            if !estFeuilleDon {
                cellule {
                    ligne("Date", oeuvre.date)
                }
            }

            // Cellule 6 : Remarques, seulement si renseignées.
            if !oeuvre.remarques.isEmpty {
                cellule {
                    ligne("Remarques", oeuvre.remarques)
                }
            }
        }
        .padding()
    }

    /// Passe à l'œuvre précédente (-1) ou suivante (+1).
    private func naviguer(_ sens: Int) {
        let nouvel = indexCourant + sens
        guard nouvel >= 0, nouvel < listeNavigation.count else { return }
        sensTransition = sens
        // Transition rapide et fluide (fondu + glissement).
        withAnimation(.easeInOut(duration: 0.25)) {
            indexCourant = nouvel
            courante = listeNavigation[nouvel]
        }
    }

    /// Une cellule façon Synthèse / Inspecteur : fond crème, filet orange léger.
    @ViewBuilder
    private func cellule<Contenu: View>(
        @ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            contenu()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.fondLegende)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.orangeInternational.opacity(0.4), lineWidth: 1)
                )
        )
    }

    /// Une ligne libellé + valeur dans une cellule (masquée si vide).
    /// Style aligné sur l'inspecteur macOS : intitulé en gras, taille body.
    @ViewBuilder
    private func ligne(_ titre: String, _ valeur: String,
                       couleur: Color = .primary,
                       estPrix: Bool = false) -> some View {
        if !valeur.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(titre).font(.body).fontWeight(.bold).foregroundStyle(.secondary)
                if estPrix {
                    Text(valeur).font(.body).foregroundStyle(couleur)
                        .flouteSiPrixMasques()
                } else {
                    Text(valeur).font(.body).foregroundStyle(couleur)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
