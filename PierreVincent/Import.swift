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
    private static func decouper(_ ligne: String, separateur: Character) -> [String] {
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
            } else if c == separateur && !dansGuillemets {
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

    /// Découpe le texte CSV complet en lignes, en respectant les guillemets et
    /// en acceptant toutes les fins de ligne. En Swift, la séquence \r\n forme
    /// UN SEUL Character : on teste donc explicitement les retours à la ligne
    /// via `isNewline` plutôt que de comparer à "\n" ou "\r" séparément.
    private static func lignesCSV(_ texte: String) -> [String] {
        var lignes: [String] = []
        var courant = ""
        var dansGuillemets = false
        for c in texte {
            if c == "\"" {
                dansGuillemets.toggle()
                courant.append(c)
            } else if c.isNewline && !dansGuillemets {
                // Reconnaît \n, \r ET la séquence combinée \r\n (un seul Character).
                lignes.append(courant)
                courant = ""
            } else {
                courant.append(c)
            }
        }
        if !courant.isEmpty { lignes.append(courant) }
        return lignes
    }

    /// Devine le séparateur (virgule ou point-virgule) d'après la 1re ligne.
    private static func devinerSeparateur(_ premiereLigne: String) -> Character {
        let pv = premiereLigne.filter { $0 == ";" }.count
        let vg = premiereLigne.filter { $0 == "," }.count
        return pv > vg ? ";" : ","
    }

    /// Résultat lisible de l'import.
    struct Resultat { let importees: Int; let erreur: String? }

    @MainActor
    static func importer(depuis dossier: URL, context: ModelContext) -> Resultat {
        // Accès sécurisé au dossier choisi hors du bac à sable (et à son contenu).
        let accesOK = dossier.startAccessingSecurityScopedResource()
        defer { if accesOK { dossier.stopAccessingSecurityScopedResource() } }

        let csvURL = dossier.appendingPathComponent("import.csv")
        let dossierPhotos = dossier.appendingPathComponent("Photos", isDirectory: true)

        // Lecture tolérante à l'encodage : UTF-8, puis Latin-1 en secours.
        var contenu: String
        if let u = try? String(contentsOf: csvURL, encoding: .utf8) {
            contenu = u
        } else if let l = try? String(contentsOf: csvURL, encoding: .isoLatin1) {
            contenu = l
        } else {
            return Resultat(importees: 0, erreur: "Fichier import.csv introuvable ou illisible.")
        }
        if contenu.hasPrefix("\u{FEFF}") { contenu.removeFirst() }
        return traiter(contenu: contenu, dossierPhotos: dossierPhotos, context: context)
    }

    /// Importe directement un fichier CSV seul (sans dossier ni images).
    /// Utilisé pour importer un export Numbers / Excel.
    @MainActor
    static func importerCSV(fichier: URL, context: ModelContext,
                            feuilleParDefaut: Feuille = .tableauxVendus) -> Resultat {
        // Accès sécurisé au fichier choisi hors du bac à sable.
        let accesOK = fichier.startAccessingSecurityScopedResource()
        defer { if accesOK { fichier.stopAccessingSecurityScopedResource() } }

        // Lecture tolérante à l'encodage : UTF-8, puis Latin-1 en secours.
        var contenu: String
        if let u = try? String(contentsOf: fichier, encoding: .utf8) {
            contenu = u
        } else if let l = try? String(contentsOf: fichier, encoding: .isoLatin1) {
            contenu = l
        } else {
            return Resultat(importees: 0, erreur: "Fichier CSV illisible.")
        }
        if contenu.hasPrefix("\u{FEFF}") { contenu.removeFirst() }
        // Pas de dossier photos : on ignore la colonne Photo.
        return traiter(contenu: contenu, dossierPhotos: nil,
                       feuilleParDefaut: feuilleParDefaut, context: context)
    }

    /// Cœur du parsing, partagé entre l'import « dossier » et l'import « fichier ».
    /// `dossierPhotos` nil = on n'importe pas les images.
    /// `feuilleParDefaut` sert quand la colonne « Feuille » est absente.
    @MainActor
    private static func traiter(contenu: String, dossierPhotos: URL?,
                                feuilleParDefaut: Feuille = .tableauxVendus,
                                context: ModelContext) -> Resultat {
        let lignes = lignesCSV(contenu)
        guard lignes.count > 1 else {
            // Diagnostic détaillé : encodage et fins de ligne réellement lues.
            let taille = contenu.count
            let nbCR = contenu.filter { $0 == "\r" }.count
            let nbLF = contenu.filter { $0 == "\n" }.count
            let nbGuillemets = contenu.filter { $0 == "\"" }.count
            return Resultat(importees: 0,
                erreur: "Aucune donnée. Lignes : \(lignes.count), caractères : \(taille), "
                      + "CR : \(nbCR), LF : \(nbLF), guillemets : \(nbGuillemets).")
        }

        // Détecte le séparateur (virgule ou point-virgule) sur l'en-tête.
        let separateur = devinerSeparateur(lignes[0])

        let entetes = decouper(lignes[0], separateur: separateur)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        func idx(_ nom: String) -> Int? { entetes.firstIndex(of: nom) }

        let iFeuille = idx("Feuille")
        var compte = 0

        for ligne in lignes.dropFirst() {
            let champs = decouper(ligne, separateur: separateur)
            if champs.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            func val(_ nom: String) -> String {
                guard let k = idx(nom), k < champs.count else { return "" }
                return champs[k].trimmingCharacters(in: .whitespaces)
            }

            // Feuille : depuis la colonne si présente, sinon la feuille par défaut.
            let feuille: Feuille
            if let iF = iFeuille, iF < champs.count,
               let f = Feuille(rawValue: champs[iF].trimmingCharacters(in: .whitespaces)) {
                feuille = f
            } else {
                feuille = feuilleParDefaut
            }

            let o = Oeuvre(feuille: feuille)
            o.type        = val("Type")
            o.dimensions  = val("Dimensions")
            o.format      = val("Format")
            o.remarques   = val("Remarques")
            o.vendeur     = val("Vendeur")
            o.modeVente   = val("Mode de vente")
            o.acheteur    = val("Acheteur")
            o.date        = val("Date")
            o.destinataire = val("Destinataire")
            let prixTxt = val("Prix").replacingOccurrences(of: ",", with: ".")
            o.prix = Double(prixTxt) ?? 0

            // Photo : seulement si un dossier Photos a été fourni.
            if let dossierPhotos {
                let nomPhoto = val("Photo")
                if !nomPhoto.isEmpty {
                    let src = dossierPhotos.appendingPathComponent(nomPhoto)
                    if let img = NSImage(contentsOf: src),
                       let stocke = PhotoStore.enregistrer(image: img) {
                        o.photoNom = stocke
                    }
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
