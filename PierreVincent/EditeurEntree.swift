import SwiftUI
import SwiftData

/// Feuille modale pour créer ou modifier une entrée.
/// Les champs affichés dépendent de la feuille (vente vs don).
///
/// Saisie fluide : les champs sont des variables LOCALES (@State) ; on ne
/// recopie dans l'objet de la base qu'à l'enregistrement.
struct EditeurEntree: View {
    @Environment(\.dismiss) private var dismiss

    let feuille: Feuille
    @Bindable var oeuvre: Oeuvre
    let estNouvelle: Bool
    var onValider: () -> Void
    var onAnnuler: () -> Void
    /// Appelé par « Enregistrer et nouveau » : la vue parente crée une nouvelle
    /// entrée vierge et renvoie l'objet à éditer ensuite (ou nil si impossible).
    var onEnregistrerEtNouveau: (() -> Oeuvre?)? = nil

    private var estVente: Bool { feuille != .oeuvresDonnees }

    // Champs pour la navigation au clavier (Tab).
    private enum Champ: Hashable {
        case type, prix, dimensions, format, vendeur, acheteur, date, destinataire, remarques
    }
    @FocusState private var focus: Champ?

    // Copies locales des champs (saisie fluide).
    @State private var photoNom = ""
    @State private var type = ""
    @State private var dimensions = ""
    @State private var format = ""
    @State private var vendeur = ""
    @State private var acheteur = ""
    @State private var date = ""
    @State private var destinataire = ""
    @State private var remarques = ""
    @State private var prixTexte = ""
    @State private var initialise = false
    // Référence à l'entrée en cours (change quand on enchaîne « et nouveau »).
    @State private var courante: Oeuvre?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(estNouvelle ? "Nouvelle entrée — \(feuille.rawValue)"
                             : "Modifier — \(feuille.rawValue)")
                .font(.headline)
                .padding()

            Divider()

            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    PhotoField(photoNom: $photoNom)

                    VStack(alignment: .leading, spacing: 12) {
                        if estVente {
                            champTexte("Type", $type, champ: .type)
                            champPrix()
                            champTexte("Dimensions", $dimensions, champ: .dimensions)
                            champTexte("Format", $format, champ: .format)
                            champTexte("Vendeur", $vendeur, champ: .vendeur)
                            champTexte("Acheteur", $acheteur, champ: .acheteur)
                            champTexte("Date", $date, champ: .date)
                        } else {
                            champTexte("Destinataire", $destinataire, champ: .destinataire)
                            champTexte("Type", $type, champ: .type)
                            champTexte("Dimensions", $dimensions, champ: .dimensions)
                            champTexte("Format", $format, champ: .format)
                        }
                        champRemarques()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }

            Divider()

            HStack {
                Spacer()
                Button("Annuler", role: .cancel) {
                    if photoNom != (courante?.photoNom ?? ""), !photoNom.isEmpty {
                        PhotoStore.supprimerPhoto(nom: photoNom)
                    }
                    onAnnuler(); dismiss()
                }
                .keyboardShortcut(.cancelAction)

                // Bouton d'enchaînement, seulement en création.
                if estNouvelle, onEnregistrerEtNouveau != nil {
                    Button("Enregistrer et nouveau") { enregistrerEtNouveau() }
                }

                Button("Enregistrer") { enregistrer() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 620, height: 520)
        .onAppear {
            courante = oeuvre
            chargerDepuis(oeuvre)
            // Focus sur le premier champ à l'ouverture.
            focus = estVente ? .type : .destinataire
        }
    }

    // MARK: Chargement / enregistrement

    private func chargerDepuis(_ o: Oeuvre) {
        photoNom     = o.photoNom
        type         = o.type
        dimensions   = o.dimensions
        format       = o.format
        vendeur      = o.vendeur
        acheteur     = o.acheteur
        date         = o.date
        destinataire = o.destinataire
        remarques    = o.remarques
        prixTexte    = o.prix == 0 ? "" : String(Int(o.prix.rounded()))
    }

    private func viderChamps() {
        photoNom = ""; type = ""; dimensions = ""; format = ""
        vendeur = ""; acheteur = ""; date = ""; destinataire = ""
        remarques = ""; prixTexte = ""
    }

    /// Recopie les champs locaux dans l'entrée donnée.
    private func appliquer(sur o: Oeuvre) {
        o.photoNom     = photoNom
        o.type         = type
        o.dimensions   = dimensions
        o.format       = format
        o.vendeur      = vendeur
        o.acheteur     = acheteur
        o.date         = date
        o.destinataire = destinataire
        o.remarques    = remarques
        let net = prixTexte
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        o.prix = Double(net) ?? 0
    }

    private func enregistrer() {
        if let o = courante { appliquer(sur: o) }
        onValider()
        dismiss()
    }

    /// Enregistre l'entrée courante et prépare une nouvelle fiche vierge,
    /// sans fermer la fenêtre.
    private func enregistrerEtNouveau() {
        if let o = courante { appliquer(sur: o) }
        onValider()
        // La vue parente crée une nouvelle entrée vierge et nous la renvoie.
        if let suivante = onEnregistrerEtNouveau?() {
            courante = suivante
            viderChamps()
            focus = estVente ? .type : .destinataire
        } else {
            dismiss()
        }
    }

    // MARK: Champs

    private func champTexte(_ titre: String, _ liaison: Binding<String>, champ: Champ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titre).font(.caption).foregroundStyle(.secondary)
            TextField("", text: liaison)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: champ)
        }
    }

    private func champPrix() -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Prix").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("0", text: $prixTexte)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .focused($focus, equals: .prix)
                Text("€").foregroundStyle(.secondary)
            }
        }
    }

    private func champRemarques() -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Remarques").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $remarques)
                .font(.body)
                .frame(height: 80)
                .focused($focus, equals: .remarques)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor)))
        }
    }
}
