import SwiftUI

/// Mémorise la largeur de chaque colonne (par feuille) ET la hauteur des
/// rangées (par feuille), de façon persistante dans les réglages de l'app.
/// Les valeurs sont donc conservées d'une session à l'autre.
@Observable
final class LargeursColonnes {
    private var largeurs: [String: CGFloat] = [:]
    private var hauteurs: [String: CGFloat] = [:]

    init() { charger() }

    private func cle(feuille: String, colonne: String) -> String {
        "\(feuille)|\(colonne)"
    }

    // MARK: Largeur des colonnes

    func largeur(feuille: String, colonne: String, defaut: CGFloat) -> CGFloat {
        largeurs[cle(feuille: feuille, colonne: colonne)] ?? defaut
    }

    func definir(feuille: String, colonne: String, _ valeur: CGFloat) {
        let bornee = min(max(valeur, 44), 600)
        largeurs[cle(feuille: feuille, colonne: colonne)] = bornee
        enregistrer()
    }

    // MARK: Hauteur des rangées (une valeur par feuille)

    func hauteur(feuille: String, defaut: CGFloat = 40) -> CGFloat {
        hauteurs[feuille] ?? defaut
    }

    func definirHauteur(feuille: String, _ valeur: CGFloat) {
        let bornee = min(max(valeur, 30), 200)
        hauteurs[feuille] = bornee
        enregistrer()
    }

    // MARK: Persistance

    private let cleLargeurs = "largeursColonnes"
    private let cleHauteurs = "hauteursRangees"

    private func enregistrer() {
        UserDefaults.standard.set(largeurs.mapValues { Double($0) }, forKey: cleLargeurs)
        UserDefaults.standard.set(hauteurs.mapValues { Double($0) }, forKey: cleHauteurs)
    }

    private func charger() {
        if let l = UserDefaults.standard.dictionary(forKey: cleLargeurs) as? [String: Double] {
            largeurs = l.mapValues { CGFloat($0) }
        }
        if let h = UserDefaults.standard.dictionary(forKey: cleHauteurs) as? [String: Double] {
            hauteurs = h.mapValues { CGFloat($0) }
        }
    }
}
