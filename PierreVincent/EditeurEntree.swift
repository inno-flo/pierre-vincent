#if os(macOS)
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
    /// Appelée à chaque fermeture pour réinitialiser l'état côté parent
    /// (fiabilise la réouverture de l'éditeur sur macOS).
    var onFermer: () -> Void = {}
    /// Appelé par « Enregistrer et nouveau » : la vue parente crée une nouvelle
    /// entrée vierge et renvoie l'objet à éditer ensuite (ou nil si impossible).
    var onEnregistrerEtNouveau: (() -> Oeuvre?)? = nil
    /// Liste ordonnée des œuvres (ordre d'affichage), pour naviguer Précédent /
    /// Suivant sans fermer la fenêtre. Vide = navigation désactivée (création).
    var listeNavigation: [Oeuvre] = []
    /// Appelé à chaque navigation Précédent / Suivant avec la nouvelle œuvre,
    /// pour que la fenêtre principale mette à jour sa sélection en conséquence.
    var onNaviguer: (Oeuvre) -> Void = { _ in }

    // Œuvre actuellement éditée (change lors de la navigation Précédent/Suivant).
    @State private var courante: Oeuvre?
    // Index de l'œuvre courante dans listeNavigation.
    @State private var indexCourant = 0
    // Confirmation avant de quitter une œuvre modifiée pendant la navigation.
    @State private var confirmationNavigation = false
    @State private var navigationEnAttente = 0   // +1 suivant, -1 précédent

    private var estVente: Bool { feuille != .oeuvresDonnees }

    // Champs pour la navigation au clavier (Tab).
    private enum Champ: Hashable {
        case type, prix, dimensions, format, vendeur, modeVente, acheteur, date, destinataire, remarques
    }
    @FocusState private var focus: Champ?

    // Copies locales des champs (saisie fluide).
    @State private var photoNom = ""
    @State private var type = ""
    @State private var dimensions = ""
    @State private var format = ""
    @State private var vendeur = ""
    @State private var modeVente = ""
    @State private var acheteur = ""
    @State private var date = ""
    @State private var destinataire = ""
    @State private var remarques = ""
    @State private var prixTexte = ""
    // Instantané des valeurs au chargement, pour détecter les modifications.
    @State private var instantaneInitial = ""
    // Masquage des prix : quand actif, le champ Prix est flouté et désactivé.
    @AppStorage("prixMasques") private var prixMasques = false
    @State private var initialise = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Éditeur")
                .font(.headline)
                .padding()

            Divider()

            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    PhotoField(photoNom: $photoNom)

                    VStack(alignment: .leading, spacing: 12) {
                        if estVente {
                            // Cellule Prix.
                            celluleEditeur { champPrix() }
                            // Cellule Type.
                            celluleEditeur { champTexte("Type", $type, champ: .type) }
                            // Cellule Dimensions + Format.
                            celluleEditeur {
                                champTexte("Dimensions", $dimensions, champ: .dimensions)
                                champTexte("Format", $format, champ: .format)
                            }
                            // Cellule Vendeur + Acheteur + Mode de vente.
                            celluleEditeur {
                                champTexte("Vendeur", $vendeur, champ: .vendeur)
                                champTexte("Acheteur", $acheteur, champ: .acheteur)
                                champTexte("Mode de vente", $modeVente, champ: .modeVente)
                            }
                            // Cellule Date.
                            celluleEditeur { champTexte("Date", $date, champ: .date) }
                        } else {
                            // Cellule Destinataire.
                            celluleEditeur {
                                champTexte("Destinataire", $destinataire, champ: .destinataire)
                            }
                            // Cellule Type.
                            celluleEditeur { champTexte("Type", $type, champ: .type) }
                            // Cellule Dimensions + Format.
                            celluleEditeur {
                                champTexte("Dimensions", $dimensions, champ: .dimensions)
                                champTexte("Format", $format, champ: .format)
                            }
                        }
                        // Cellule Remarques.
                        celluleEditeur { champRemarques() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .background(Color.cremeFond)

            Divider()

            HStack {
                // Navigation Précédent / Suivant (pas en création).
                if !estNouvelle, !listeNavigation.isEmpty {
                    Button {
                        demanderNavigation(-1)
                    } label: {
                        Label("Précédent", systemImage: "chevron.left")
                    }
                    .disabled(indexCourant <= 0)
                    // Flèche gauche du clavier comme alternative au bouton
                    // (sans modificateur : les champs texte gardent la priorité
                    // pour déplacer le curseur pendant la saisie).
                    .keyboardShortcut(.leftArrow, modifiers: [])

                    Button {
                        demanderNavigation(1)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Suivant")
                            Image(systemName: "chevron.right")
                        }
                    }
                    .disabled(indexCourant >= listeNavigation.count - 1)
                    // Flèche droite du clavier comme alternative au bouton.
                    .keyboardShortcut(.rightArrow, modifiers: [])
                }

                Spacer()
                Button("Annuler", role: .cancel) {
                    if photoNom != (courante?.photoNom ?? ""), !photoNom.isEmpty {
                        PhotoStore.supprimerPhoto(nom: photoNom)
                    }
                    onAnnuler(); onFermer(); dismiss()
                }
                .keyboardShortcut(.cancelAction)

                // Bouton d'enchaînement, seulement en création.
                if estNouvelle, onEnregistrerEtNouveau != nil {
                    Button("Enregistrer et nouveau") { enregistrerEtNouveau() }
                }

                Button("Enregistrer") { enregistrer() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!aEteModifie)
            }
            .padding()
        }
        .frame(width: 820, height: 760)
        .onAppear {
            courante = oeuvre
            chargerDepuis(oeuvre)
            // Position de départ dans la liste de navigation.
            if let i = listeNavigation.firstIndex(where: { $0.id == oeuvre.id }) {
                indexCourant = i
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focus = nil
            }
        }
        // Confirmation avant de quitter une œuvre modifiée pendant la navigation.
        .alert("Modifications non enregistrées", isPresented: $confirmationNavigation) {
            Button("Enregistrer et continuer") {
                if let o = courante { appliquer(sur: o); onValider() }
                naviguer(navigationEnAttente)
            }
            Button("Ignorer les modifications", role: .destructive) {
                naviguer(navigationEnAttente)
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Vous avez modifié cette œuvre. Que voulez-vous faire avant de changer d'œuvre ?")
        }
    }

    // MARK: Navigation Précédent / Suivant

    /// Demande à naviguer de `sens` (+1 suivant, -1 précédent). Si des
    /// modifications sont en cours, demande confirmation d'abord.
    private func demanderNavigation(_ sens: Int) {
        navigationEnAttente = sens
        if aEteModifie {
            confirmationNavigation = true
        } else {
            naviguer(sens)
        }
    }

    /// Effectue le changement d'œuvre et recharge les champs.
    private func naviguer(_ sens: Int) {
        let nouvelIndex = indexCourant + sens
        guard nouvelIndex >= 0, nouvelIndex < listeNavigation.count else { return }
        indexCourant = nouvelIndex
        let o = listeNavigation[nouvelIndex]
        courante = o
        chargerDepuis(o)
        focus = nil
        // Met à jour la sélection dans la fenêtre principale en arrière-plan.
        onNaviguer(o)
    }

    // MARK: Chargement / enregistrement

    private func chargerDepuis(_ o: Oeuvre) {
        photoNom     = o.photoNom
        type         = o.type
        dimensions   = o.dimensions
        format       = o.format
        vendeur      = o.vendeur
        modeVente    = o.modeVente
        acheteur     = o.acheteur
        date         = o.date
        destinataire = o.destinataire
        remarques    = o.remarques
        prixTexte    = o.prix == 0 ? "" : String(Int(o.prix.rounded()))
        // Mémorise l'état initial pour détecter d'éventuelles modifications.
        instantaneInitial = instantaneCourant
    }

    /// Concatène tous les champs : sert à comparer l'état courant à l'initial.
    private var instantaneCourant: String {
        [photoNom, type, dimensions, format, vendeur, modeVente,
         acheteur, date, destinataire, remarques, prixTexte].joined(separator: "␟")
    }

    /// Vrai si au moins un champ a changé depuis l'ouverture.
    private var aEteModifie: Bool {
        instantaneCourant != instantaneInitial
    }

    private func viderChamps() {
        photoNom = ""; type = ""; dimensions = ""; format = ""
        vendeur = ""; modeVente = ""; acheteur = ""; date = ""; destinataire = ""
        remarques = ""; prixTexte = ""
    }

    /// Recopie les champs locaux dans l'entrée donnée.
    private func appliquer(sur o: Oeuvre) {
        o.photoNom     = photoNom
        o.type         = type
        o.dimensions   = dimensions
        o.format       = format
        o.vendeur      = vendeur
        o.modeVente    = modeVente
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
        onFermer(); dismiss()
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
            // Aucun champ présélectionné.
        } else {
            onFermer(); dismiss()
        }
    }

    // MARK: Champs

    /// Enveloppe un ou plusieurs champs dans une cellule au style de
    /// l'inspecteur : fond crème, coins arrondis, filet orange léger.
    @ViewBuilder
    private func celluleEditeur<Contenu: View>(
        @ViewBuilder _ contenu: () -> Contenu) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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

    private func champTexte(_ titre: String, _ liaison: Binding<String>, champ: Champ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titre).font(.body).fontWeight(.bold).foregroundStyle(.secondary)
            TextField("", text: liaison)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: champ)
        }
    }

    private func champPrix() -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Prix").font(.body).fontWeight(.bold).foregroundStyle(.secondary)
            HStack {
                TextField("0", text: $prixTexte)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .focused($focus, equals: .prix)
                    .foregroundStyle(Color.orangeInternational)
                    // Masquage : flouté et non modifiable tant qu'il est actif.
                    // (le flou hérite de la couleur orange du texte)
                    .blur(radius: prixMasques ? 5 : 0)
                    .disabled(prixMasques)
                Text("€").foregroundStyle(.secondary)
            }
            if prixMasques {
                Text("Prix masqué — désactivez le masquage pour le modifier.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: prixMasques)
    }

    private func champRemarques() -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Remarques").font(.body).fontWeight(.bold).foregroundStyle(.secondary)
            TextEditor(text: $remarques)
                .font(.body)
                .frame(height: 96)   // ~3 lignes visibles
                .focused($focus, equals: .remarques)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor)))
        }
    }
}

#endif
