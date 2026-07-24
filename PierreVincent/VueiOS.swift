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
            DetailiOS(oeuvre: o, estFeuilleDon: estFeuilleDon)
        }
    }

    /// Liste simple : vignette + informations principales, adaptée au tactile.
    private var liste: some View {
        List(oeuvresGalerie) { o in
            Button {
                detail = o
            } label: {
                HStack(spacing: 12) {
                    vignette(o)
                    VStack(alignment: .leading, spacing: 3) {
                        if !estFeuilleDon {
                            Text(formaterEuros(o.prix))
                                .font(.headline)
                        }
                        Text(o.type.isEmpty ? "—" : o.type)
                            .font(estFeuilleDon ? .headline : .subheadline)
                            .lineLimit(1)
                        if !o.dimensions.isEmpty {
                            Text(o.dimensions)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if estFeuilleDon, !o.destinataire.isEmpty {
                            Text(o.destinataire)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                // Hauteur de ligne FIXE : évite que List recalcule la mise en
                // page quand une vignette arrive (source des saccades).
                .frame(height: 60)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func vignette(_ o: Oeuvre) -> some View {
        // Vignette mise en cache pour un défilement fluide.
        VignetteCachee(nom: o.photoNom, cote: 56)
    }
}

/// Fiche de détail d'une entrée (lecture seule) pour iPhone/iPad.
struct DetailiOS: View {
    let oeuvre: Oeuvre
    let estFeuilleDon: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Grande image.
                    if let img = PhotoStore.chargerImage(nom: oeuvre.photoNom) {
                        Image(imagePlateforme: img).resizable().scaledToFit()
                            .frame(maxWidth: .infinity)
                            .cornerRadius(12)
                    }

                    // Informations.
                    if !estFeuilleDon {
                        champ("Prix", formaterEuros(oeuvre.prix))
                    }
                    champ("Type", oeuvre.type)
                    champ("Dimensions", oeuvre.dimensions)
                    champ("Format", oeuvre.format)
                    if estFeuilleDon {
                        champ("Destinataire", oeuvre.destinataire)
                    } else {
                        champ("Vendeur", oeuvre.vendeur)
                        champ("Acheteur", oeuvre.acheteur)
                        champ("Date", oeuvre.date)
                    }
                    champ("Remarques", oeuvre.remarques)
                }
                .padding()
            }
            .navigationTitle("Détail")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func champ(_ titre: String, _ valeur: String) -> some View {
        if !valeur.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(titre).font(.caption).foregroundStyle(.secondary)
                Text(valeur).font(.body)
            }
        }
    }
}
#endif
