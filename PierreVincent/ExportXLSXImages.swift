import Foundation
import AppKit
import XLKit

/// Export .xlsx avec les images incrustées DANS les cellules, pour ouverture
/// dans Excel ou Numbers (on voit les photos, pas des noms de fichiers).
/// Utilise la bibliothèque XLKit.
enum ExportXLSXImages {

    /// Génère le fichier .xlsx à l'URL demandée.
    /// `colonnes` fournit l'ordre et les titres ; la colonne Photo reçoit
    /// l'image incrustée quand l'entrée en a une.
    @MainActor
    static func exporter(oeuvres: [Oeuvre],
                         colonnes: [Colonne],
                         nomFeuille: String,
                         vers url: URL) async throws {

        let workbook = Workbook()
        // XLKit limite les noms de feuille à 31 caractères ; on tronque au besoin.
        let nomCourt = String(nomFeuille.prefix(31))
        let sheet = workbook.addSheet(name: nomCourt)

        // --- Ligne d'en-tête (ligne 1) ---
        let titres = colonnes.map { $0.titre }
        sheet.setRow(1, strings: titres)

        // --- Lignes de données (à partir de la ligne 2) ---
        // On écrit d'abord tout le texte, puis on incruste les images.
        for (i, o) in oeuvres.enumerated() {
            let ligne = i + 2   // ligne 1 = en-tête
            let valeurs: [String] = colonnes.map { col in
                switch col.cle {
                case .photo:
                    return ""   // la cellule photo reste vide (image incrustée ensuite)
                case .prix:
                    return String(Int(o.prix.rounded()))
                default:
                    return col.cle.texte(pour: o)
                }
            }
            sheet.setRow(ligne, strings: valeurs)
        }

        // --- Incrustation des images dans la colonne Photo ---
        // On repère l'index de la colonne Photo pour construire la référence
        // de cellule (ex. "A2", "A3"…).
        if let indexPhoto = colonnes.firstIndex(where: {
            if case .photo = $0.cle { return true } else { return false }
        }) {
            let lettreColonne = lettreExcel(pour: indexPhoto)   // 0 -> "A", 1 -> "B"…
            for (i, o) in oeuvres.enumerated() {
                let ligne = i + 2
                guard !o.photoNom.isEmpty,
                      let imgURL = PhotoStore.urlPhoto(nom: o.photoNom),
                      let data = try? Data(contentsOf: imgURL) else { continue }
                let ref = "\(lettreColonne)\(ligne)"
                try await sheet.embedImageAutoSized(data, at: ref, of: workbook)
            }
        }

        // --- Enregistrement ---
        try await workbook.save(to: url)
    }

    /// Convertit un index de colonne (0, 1, 2…) en lettre Excel (A, B, C…).
    /// Gère aussi au-delà de Z (AA, AB…) par sécurité.
    private static func lettreExcel(pour index: Int) -> String {
        var n = index
        var resultat = ""
        repeat {
            let reste = n % 26
            resultat = String(UnicodeScalar(65 + reste)!) + resultat
            n = n / 26 - 1
        } while n >= 0
        return resultat
    }
}
