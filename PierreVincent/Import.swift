import Foundation
import SwiftData
import AppKit

/// Importe des données depuis un dossier de migration.
/// Le dossier doit contenir un fichier « import.csv » et un sous-dossier « Photos ».
///
/// VERSION 4 — corrige la gestion des fins de ligne.
/// En Swift, la séquence \r\n compte comme UN SEUL Character. On utilise donc
/// la propriété `isNewline`, qui reconnaît toutes les formes de saut de ligne.
enum Import {

    struct Resultat { let importees: Int; let erreur: String? }

    /// Analyse le texte CSV et renvoie les lignes, chacune sous forme de champs.
    /// Gère les guillemets, les virgules et les retours à la ligne à l'intérieur
    /// des champs cités, ainsi que toutes les fins de ligne (\n, \r, \r\n).
    private static func analyser(_ texte: String) -> [[String]] {
        var lignes: [[String]] = []
        var champs: [String] = []
        var courant = ""
        var dansGuillemets = false

        for c in texte {
            if dansGuillemets {
                if c == "\"" {
                    dansGuillemets = false
                } else {
                    courant.append(c)
                }
            } else {
                if c == "\"" {
                    dansGuillemets = true
                } else if c == "," {
                    champs.append(courant); courant = ""
                } else if c.isNewline {
                    // Reconnaît \n, \r ET la séquence combinée \r\n.
                    champs.append(courant); courant = ""
                    lignes.append(champs); champs = []
                } else {
                    courant.append(c)
                }
            }
        }
        // Dernière ligne s'il reste du contenu non terminé par un saut de ligne.
        if !courant.isEmpty || !champs.isEmpty {
            champs.append(courant)
            lignes.append(champs)
        }
        return lignes
    }

    @MainActor
    static func importer(depuis dossier: URL, context: ModelContext) -> Resultat {
        let accesOk = dossier.startAccessingSecurityScopedResource()
        defer { if accesOk { dossier.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let csvURL = dossier.appendingPathComponent("import.csv")

        guard fm.fileExists(atPath: csvURL.path) else {
            return Resultat(importees: 0, erreur: "import.csv introuvable dans le dossier choisi.")
        }
        guard var contenu = try? String(contentsOf: csvURL, encoding: .utf8) else {
            return Resultat(importees: 0, erreur: "Impossible de lire import.csv.")
        }
        if contenu.hasPrefix("\u{FEFF}") { contenu.removeFirst() }

        let lignes = analyser(contenu)
        guard lignes.count > 1 else {
            return Resultat(importees: 0,
                erreur: "VERSION 4 — Le fichier n'a produit que \(lignes.count) ligne(s).")
        }

        let dossierPhotos = dossier.appendingPathComponent("Photos", isDirectory: true)
        let entetes = lignes[0].map { $0.trimmingCharacters(in: .whitespaces) }
        func idx(_ nom: String) -> Int? { entetes.firstIndex(of: nom) }
        let iFeuille = idx("Feuille")
        var compte = 0

        for champs in lignes.dropFirst() {
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
