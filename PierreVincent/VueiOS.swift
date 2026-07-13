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

    var body: some View {
        Group {
            if modeAffichage == "icone" {
                VueGalerie(
                    oeuvres: oeuvres,
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
            ToolbarItem(placement: .primaryAction) {
                // Bascule Liste / Galerie.
                Picker("Affichage", selection: $modeAffichage) {
                    Image(systemName: "list.bullet").tag("liste")
                    Image(systemName: "square.grid.2x2").tag("icone")
                }
                .pickerStyle(.segmented)
            }
        }
        // Fiche de détail au toucher d'une entrée.
        .sheet(item: $detail) { o in
            DetailiOS(oeuvre: o, estFeuilleDon: estFeuilleDon)
        }
    }

    /// Liste simple : vignette + informations principales, adaptée au tactile.
    private var liste: some View {
        List(oeuvres) { o in
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
                    Button("Fermé") { dismiss() }
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
