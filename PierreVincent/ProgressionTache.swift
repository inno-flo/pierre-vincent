import Foundation

/// Progression d'une tâche longue, affichée en pied de sidebar (macOS).
///
/// Sert à l'import de photos et à l'analyse des affinités : deux opérations
/// qui parcourent le même dossier de photos, une par une, et qui n'ont pas
/// d'autre moyen de remonter leur avancement jusqu'à la barre latérale. D'où
/// le `libelle`, seule chose qui les distingue à l'écran — un second objet
/// jumeau aurait fini par diverger de celui-ci.
///
/// Le nom de la classe reste celui d'origine : le renommer toucherait à des
/// appels qui marchent, pour un gain purement cosmétique.
///
/// **Dans son propre fichier**, et non plus dans `ImportPhotos.swift` : ce
/// dernier est entièrement sous `#if os(macOS)`, si bien que la classe
/// n'existait pas côté iOS. Le moteur d'affinités, lui, ne comporte aucun
/// `#if` — il se compile sur les deux plateformes en vue du portage, et
/// s'en servait. La classe n'a pas changé, seulement de fichier.
///
/// `@Observable` et non `ObservableObject` : ce dernier réclame
/// `import Combine` depuis Swift 6.
@MainActor
@Observable
final class ProgressionImport {
    static let partagee = ProgressionImport()
    private init() {}

    private(set) var enCours = false
    private(set) var traites = 0
    private(set) var total = 0
    /// Ce qui est annoncé à l'écran, devant le compteur : « Import », « Analyse ».
    private(set) var libelle = "Import"

    func demarrer(total: Int, libelle: String = "Import") {
        self.total = total
        self.libelle = libelle
        traites = 0
        enCours = true
    }

    func avancer() { traites += 1 }

    func terminer() {
        enCours = false
        traites = 0
        total = 0
        libelle = "Import"
    }
}
