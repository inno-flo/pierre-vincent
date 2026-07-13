#if os(macOS)
import Foundation
import AppKit
import PDFKit

/// Regroupe toutes les fonctions d'export.
enum Exports {

    // MARK: - Outils communs

    /// Échappe une valeur pour le CSV (guillemets, virgules, retours ligne).
    private static func echapperCSV(_ valeur: String) -> String {
        var v = valeur.replacingOccurrences(of: "\"", with: "\"\"")
        if v.contains(",") || v.contains("\n") || v.contains("\"") {
            v = "\"\(v)\""
        }
        return v
    }

    /// Construit le contenu texte CSV pour une feuille donnée.
    /// La colonne Photo contient le nom de fichier de l'image.
    static func contenuCSV(oeuvres: [Oeuvre], colonnes: [Colonne]) -> String {
        var lignes: [String] = []
        lignes.append(colonnes.map { echapperCSV($0.titre) }.joined(separator: ","))
        for o in oeuvres {
            let cells = colonnes.map { col -> String in
                if case .prix = col.cle {
                    return echapperCSV(String(format: "%.2f", o.prix))
                }
                return echapperCSV(col.cle.texte(pour: o))
            }
            lignes.append(cells.joined(separator: ","))
        }
        return lignes.joined(separator: "\n")
    }

    // MARK: - Export CSV simple

    static func exporterCSV(oeuvres: [Oeuvre], colonnes: [Colonne], vers url: URL) throws {
        let contenu = contenuCSV(oeuvres: oeuvres, colonnes: colonnes)
        // BOM UTF-8 pour qu'Excel lise correctement les accents.
        let data = "\u{FEFF}".data(using: .utf8)! + contenu.data(using: .utf8)!
        try data.write(to: url)
    }

    // MARK: - Export Excel (.xls via SpreadsheetML lisible par Excel/Numbers)

    /// Génère un fichier tableur au format XML SpreadsheetML 2003,
    /// que Excel et Numbers ouvrent nativement. Extension .xls.
    static func exporterXLS(oeuvres: [Oeuvre], colonnes: [Colonne],
                            nomFeuille: String, vers url: URL) throws {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
             .replacingOccurrences(of: "\"", with: "&quot;")
        }
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <?mso-application progid="Excel.Sheet"?>
        <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
         xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
        <Worksheet ss:Name="\(esc(nomFeuille))">
        <Table>

        """
        // En-tête
        xml += "<Row>"
        for col in colonnes {
            xml += "<Cell><Data ss:Type=\"String\">\(esc(col.titre))</Data></Cell>"
        }
        xml += "</Row>\n"
        // Données
        for o in oeuvres {
            xml += "<Row>"
            for col in colonnes {
                if case .prix = col.cle {
                    xml += "<Cell><Data ss:Type=\"Number\">\(o.prix)</Data></Cell>"
                } else {
                    xml += "<Cell><Data ss:Type=\"String\">\(esc(col.cle.texte(pour: o)))</Data></Cell>"
                }
            }
            xml += "</Row>\n"
        }
        xml += "</Table>\n</Worksheet>\n</Workbook>\n"
        try xml.data(using: .utf8)!.write(to: url)
    }

    // MARK: - Export « standard » : dossier avec données + images

    /// Crée un dossier contenant :
    ///  - donnees.csv (avec une colonne renvoyant vers le fichier image)
    ///  - un sous-dossier « Photos » avec toutes les images.
    /// C'est ce dossier qui sert aussi de sauvegarde transférable.
    static func exporterDossier(oeuvres: [Oeuvre], colonnes: [Colonne],
                                nomFeuille: String, vers dossierParent: URL) throws {
        let fm = FileManager.default
        let dossier = dossierParent.appendingPathComponent(nomFeuille, isDirectory: true)
        try? fm.removeItem(at: dossier)
        try fm.createDirectory(at: dossier, withIntermediateDirectories: true)

        let dossierPhotos = dossier.appendingPathComponent("Photos", isDirectory: true)
        try fm.createDirectory(at: dossierPhotos, withIntermediateDirectories: true)

        // On ajoute une colonne « Feuille » en tête, pour que ce dossier soit
        // DIRECTEMENT ré-importable dans l'app (migration sans reprise manuelle).
        var lignes: [String] = []
        lignes.append((["Feuille"] + colonnes.map { $0.titre }).joined(separator: ","))

        for (index, o) in oeuvres.enumerated() {
            var nomImageExporte = ""
            if !o.photoNom.isEmpty, let src = PhotoStore.urlPhoto(nom: o.photoNom) {
                nomImageExporte = String(format: "%04d.png", index + 1)
                let dest = dossierPhotos.appendingPathComponent(nomImageExporte)
                try? fm.copyItem(at: src, to: dest)
            }
            var cells = [echapperCSV(o.feuille.rawValue)]
            cells += colonnes.map { col -> String in
                if case .photo = col.cle {
                    return echapperCSV(nomImageExporte)
                }
                if case .prix = col.cle {
                    return echapperCSV(String(format: "%.2f", o.prix))
                }
                return echapperCSV(col.cle.texte(pour: o))
            }
            lignes.append(cells.joined(separator: ","))
        }

        let contenu = "\u{FEFF}" + lignes.joined(separator: "\n")
        // Nommé « import.csv » pour être relu tel quel par la fonction Importer.
        let csvURL = dossier.appendingPathComponent("import.csv")
        try contenu.data(using: .utf8)!.write(to: csvURL)
    }

    // MARK: - Export PDF (pour la feuille « Œuvres »)

    /// Génère un PDF paysage listant les œuvres, avec vignette photo.
    static func exporterPDF(oeuvres: [Oeuvre], colonnes: [Colonne],
                            titre: String, vers url: URL) throws {
        // Page A4 paysage : 842 x 595 points.
        let largeurPage: CGFloat = 842
        let hauteurPage: CGFloat = 595
        let marge: CGFloat = 30
        let hauteurLigne: CGFloat = 46

        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: largeurPage, height: hauteurPage)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "PDF", code: 1)
        }

        let colonnesSansPhoto = colonnes.filter {
            if case .photo = $0.cle { return false } else { return true }
        }
        let largeurPhoto: CGFloat = 44
        let largeurDispo = largeurPage - 2 * marge - largeurPhoto
        let largeurCol = largeurDispo / CGFloat(colonnesSansPhoto.count)

        let attrsTitre: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold)
        ]
        let attrsEntete: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold)
        ]
        let attrsCell: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .regular)
        ]

        func dessinerTexte(_ s: String, x: CGFloat, y: CGFloat, largeur: CGFloat,
                           attrs: [NSAttributedString.Key: Any]) {
            let rect = CGRect(x: x, y: y, width: largeur, height: hauteurLigne)
            let ns = NSAttributedString(string: s, attributes: attrs)
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx
            ns.draw(with: rect, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin])
            NSGraphicsContext.restoreGraphicsState()
        }

        var index = 0
        while index < oeuvres.count || index == 0 {
            ctx.beginPDFPage(nil)

            // Titre
            dessinerTexte(titre, x: marge, y: hauteurPage - marge - 8,
                          largeur: largeurPage - 2*marge, attrs: attrsTitre)

            var y = hauteurPage - marge - 40

            // En-tête colonnes
            var x = marge + largeurPhoto
            dessinerTexte("Photo", x: marge, y: y, largeur: largeurPhoto, attrs: attrsEntete)
            for col in colonnesSansPhoto {
                dessinerTexte(col.titre, x: x, y: y, largeur: largeurCol, attrs: attrsEntete)
                x += largeurCol
            }
            y -= hauteurLigne * 0.5
            ctx.setStrokeColor(NSColor.gray.cgColor)
            ctx.move(to: CGPoint(x: marge, y: y))
            ctx.addLine(to: CGPoint(x: largeurPage - marge, y: y))
            ctx.strokePath()
            y -= 4

            // Lignes de cette page
            while index < oeuvres.count && y > marge + hauteurLigne {
                let o = oeuvres[index]
                y -= hauteurLigne

                // Vignette
                if !o.photoNom.isEmpty, let img = PhotoStore.chargerImage(nom: o.photoNom),
                   let tiff = img.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let cg = rep.cgImage {
                    let r = CGRect(x: marge, y: y + 2, width: 40, height: 40)
                    ctx.draw(cg, in: r)
                }

                // Cellules texte
                var cx = marge + largeurPhoto
                for col in colonnesSansPhoto {
                    let val: String
                    if case .prix = col.cle {
                        val = formaterEuros(o.prix)
                    } else {
                        val = col.cle.texte(pour: o)
                    }
                    dessinerTexte(val, x: cx, y: y, largeur: largeurCol - 4, attrs: attrsCell)
                    cx += largeurCol
                }
                index += 1
            }

            ctx.endPDFPage()
            if index >= oeuvres.count { break }
        }

        ctx.closePDF()
        try (pdfData as Data).write(to: url)
    }
}

#endif
