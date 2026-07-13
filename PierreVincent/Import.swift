#if os(macOS)
import Foundation
import SwiftData
import AppKit

/// Importe des données depuis un dossier de migration.
/// Le dossier doit contenir un fichier « import.csv » et un sous-dossier « Photos ».
/// Le CSV a une première colonne « Feuille » qui indique l'onglet de destination,
/// puis les colonnes de données. La colonne Photo contient un nom de fichier
/// présent dans le sous-dossier Photos.
enum Import {

    /// Sépare une ligne CSV en champs en respectant les guillemets.
    private static func decouper(_ ligne: String) -> [String] {
        var champs: [String] = []
        var courant = ""
        var dansGuillemets = false
        var i = ligne.startIndex
        while i < ligne.endIndex {
            let c = ligne[i]
            if c == "\"" {
                let suivant = ligne.index(after: i)
                if dansGuillemets && suivant < ligne.endIndex && ligne[suivant] == "\"" {
                    courant.append("\"")
                    i = suivant
                } else {
                    dansGuillemets.toggle()
                }
            } else if c == "," && !dansGuillemets {
                champs.append(courant)
                courant = ""
            } else {
                courant.append(c)
            }
            i = ligne.index(after: i)
        }
        champs.append(courant)
        return champs
    }

    /// Découpe le texte CSV complet en lignes en respectant les guillemets.
    private static func lignesCSV(_ texte: String) -> [String] {
        var lignes: [String] = []
        var courant = ""
        var dansGuillemets = false
        for c in texte {
            if c == "\"" { dansGuillemets.toggle(); courant.append(c) }
            else if c == "\n" && !dansGuillemets { lignes.append(courant); courant = "" }
            else if c == "\r" { continue }
            else { courant.append(c) }
        }
        if !courant.isEmpty { lignes.append(courant) }
        return lignes
    }

    /// Résultat lisible de l'import.
    struct Resultat { let importees: Int; let erreur: String? }

    @MainActor
    static func importer(depuis dossier: URL, context: ModelContext) -> Resultat {
        let csvURL = dossier.appendingPathComponent("import.csv")
        let dossierPhotos = dossier.appendingPathComponent("Photos", isDirectory: true)

        guard var contenu = try? String(contentsOf: csvURL, encoding: .utf8) else {
            return Resultat(importees: 0, erreur: "Fichier import.csv introuvable ou illisible.")
        }
        // Retire un éventuel BOM.
        if contenu.hasPrefix("\u{FEFF}") { contenu.removeFirst() }

        let lignes = lignesCSV(contenu)
        guard lignes.count > 1 else {
            return Resultat(importees: 0, erreur: "Le fichier ne contient aucune donnée.")
        }

        let entetes = decouper(lignes[0]).map { $0.trimmingCharacters(in: .whitespaces) }
        func idx(_ nom: String) -> Int? { entetes.firstIndex(of: nom) }

        let iFeuille = idx("Feuille")
        var compte = 0

        for ligne in lignes.dropFirst() {
            let champs = decouper(ligne)
            if champs.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            func val(_ nom: String) -> String {
                guard let k = idx(nom), k < champs.count else { return "" }
                return champs[k].trimmingCharacters(in: .whitespaces)
            }

            let nomFeuille = (iFeuille != nil && iFeuille! < champs.count)
                ? champs[iFeuille!].trimmingCharacters(in: .whitespaces) : ""
            let feuille = Feuille(rawValue: nomFeuille) ?? .tableauxVendus

            let o = Oeuvre(feuille: feuille)
            o.type        = val("Type")
            o.dimensions  = val("Dimensions")
            o.format      = val("Format")
            o.remarques   = val("Remarques")
            o.vendeur     = val("Vendeur")
            o.acheteur    = val("Acheteur")
            o.date        = val("Date")
            o.destinataire = val("Destinataire")
            let prixTxt = val("Prix").replacingOccurrences(of: ",", with: ".")
            o.prix = Double(prixTxt) ?? 0

            // Photo : copie le fichier depuis le dossier Photos vers le stockage app.
            let nomPhoto = val("Photo")
            if !nomPhoto.isEmpty {
                let src = dossierPhotos.appendingPathComponent(nomPhoto)
                if let img = NSImage(contentsOf: src),
                   let stocke = PhotoStore.enregistrer(image: img) {
                    o.photoNom = stocke
                }
            }

            context.insert(o)
            compte += 1
        }

        try? context.save()
        return Resultat(importees: compte, erreur: nil)
    }
}

#endif
