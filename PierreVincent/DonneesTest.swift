import Foundation
import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Générateur de données de TEST (développement).
/// Ne s'active que si la base est VIDE — il ne détruit donc jamais de données
/// existantes. Fonctionne sur Mac et iPhone. À retirer avant diffusion réelle.
enum DonneesTest {

    /// Dessine une image « lourde » (≥ 200 Ko) remplie de formes aléatoires,
    /// pour tester les performances de défilement avec de vraies images.
    /// Multiplateforme : produit une NSImage sur Mac, une UIImage sur iPhone.
    private static func imageDetaillee(graine: Int) -> ImagePlateforme? {
        let taille = CGSize(width: 800, height: 800)
        var generateur = SystemRandomNumberGenerator()

        // Fonction de dessin commune (mêmes primitives Core Graphics partout).
        func dessiner(dans ctx: CGContext) {
            // Fond dégradé simple.
            ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: taille))
            // Beaucoup de cercles colorés translucides : l'image devient riche
            // en détails, donc lourde une fois compressée (≥ 200 Ko visé).
            for _ in 0..<4000 {
                let x = Double.random(in: 0...800, using: &generateur)
                let y = Double.random(in: 0...800, using: &generateur)
                let r = Double.random(in: 4...40, using: &generateur)
                ctx.setFillColor(CGColor(
                    red: Double.random(in: 0...1, using: &generateur),
                    green: Double.random(in: 0...1, using: &generateur),
                    blue: Double.random(in: 0...1, using: &generateur),
                    alpha: 0.6))
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
        }

        #if os(macOS)
        let image = NSImage(size: taille)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            dessiner(dans: ctx)
        }
        image.unlockFocus()
        return image
        #else
        let renderer = UIGraphicsImageRenderer(size: taille)
        return renderer.image { context in
            dessiner(dans: context.cgContext)
        }
        #endif
    }

    /// Crée 5 images détaillées et renvoie leurs noms de fichier stockés.
    @MainActor
    private static func creerImagesBidon() -> [String] {
        var noms: [String] = []
        for graine in 0..<5 {
            if let img = imageDetaillee(graine: graine),
               let nom = PhotoStore.enregistrer(image: img) {
                noms.append(nom)
            }
        }
        return noms
    }

    /// Remplit la base avec des entrées bidon, si elle est vide.
    /// 100 par catégorie, sauf Tapis (10).
    @MainActor
    static func genererSiVide(context: ModelContext) {
        let descripteur = FetchDescriptor<Oeuvre>()
        let nombre = (try? context.fetchCount(descripteur)) ?? 0
        guard nombre == 0 else { return }   // base non vide : on ne touche à rien

        // 5 images bidon réutilisées en rotation sur toutes les entrées.
        let imagesBidon = creerImagesBidon()

        let types = ["Huile sur toile", "Aquarelle", "Fusain", "Encre",
                     "Acrylique", "Pastel", "Gouache", "Sanguine"]
        let formats = ["Portrait", "Paysage", "Carré", "Panoramique"]
        let vendeurs = ["Artenchères", "Drôme Enchères", "RempART",
                        "Galerie du Centre", "Vente privée", "Atelier"]
        let acheteurs = ["M. Dupont", "Mme Martin", "Collection privée",
                         "M. Bernard", "Anonyme"]
        let destinataires = ["Musée local", "Association", "Ami proche",
                             "Famille", "École d'art"]

        func dimAleatoire() -> String {
            "\(Int.random(in: 20...120)) × \(Int.random(in: 20...120)) cm"
        }

        func creer(_ feuille: Feuille, prefixe: String, combien: Int) {
            for i in 1...combien {
                let o = Oeuvre(feuille: feuille)

                // Pour les dons, le type doit contenir « Tableau » ou « Dessin »
                // (en alternance) pour que la Synthèse les compte correctement.
                if feuille == .oeuvresDonnees {
                    let categorie = (i % 2 == 0) ? "Tableau" : "Dessin"
                    o.type = "\(categorie) — \(types.randomElement()!)"
                } else {
                    o.type = "\(prefixe) \(i) — \(types.randomElement()!)"
                }

                o.dimensions = dimAleatoire()
                o.format = formats.randomElement()!
                o.remarques = i % 4 == 0 ? "Œuvre remarquable" : ""

                // Image bidon en rotation (parmi les 5).
                if !imagesBidon.isEmpty {
                    o.photoNom = imagesBidon[i % imagesBidon.count]
                }

                if feuille == .oeuvresDonnees {
                    o.destinataire = destinataires.randomElement()!
                } else {
                    o.prix = Double(Int.random(in: 1...40) * 50)   // 50 à 2000 €
                    o.vendeur = vendeurs.randomElement()!
                    o.acheteur = acheteurs.randomElement()!
                    o.date = "2025"
                }
                context.insert(o)
            }
        }

        creer(.tableauxVendus, prefixe: "Tableau", combien: 100)
        creer(.dessinsVendus,  prefixe: "Dessin",  combien: 100)
        creer(.tapisVendus,    prefixe: "Tapis",   combien: 10)
        creer(.oeuvresDonnees, prefixe: "Don",     combien: 100)

        try? context.save()
    }
}
