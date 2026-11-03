import Foundation

struct Release: Identifiable {
    struct Note {
        let text: String
        var bold = false
        var security = false
    }

    enum Category: String, CaseIterable {
        case new, improved, fixed

        var title: String {
            switch self {
            case .new: "Nouveautés"
            case .improved: "Améliorations"
            case .fixed: "Corrections de bogues"
            }
        }

        var filter: String {
            switch self {
            case .new: "Nouveautés"
            case .improved: "Améliorations"
            case .fixed: "Corrections"
            }
        }
    }

    var id: String { version }
    let version: String
    let date: String
    let year: Int
    var latest = false
    var security = false
    let engine: String
    let notes: [Category: [Note]]

    static let all: [Release] = [
        Release(version: "0.1", date: "2 nov. 2026", year: 2026, latest: true, engine: "rclone 1.75.2", notes: [
            .new: [
                Note(text: "Remotes rclone montés comme disques dans le Finder, avec macFUSE ou le client NFS de macOS", bold: true),
                Note(text: "Moteur rclone inclus, qui partage 16 connexions entre les fichiers lus : 60 à 80 Mo/s sur un seul fichier Dropbox"),
                Note(text: "Panneau dans la barre des menus : débit de la dernière minute, lecteurs et envois en cours"),
                Note(text: "Ajout de lecteur : Dropbox, Google Drive, OneDrive, Box, MEGA, Proton Drive, S3, WebDAV, SFTP, FTP et SMB"),
                Note(text: "Fiche lecteur : profil, cache, limite de débit, test de débit et journal"),
                Note(text: "Renommer, dupliquer ou supprimer un lecteur depuis la liste ou sa fiche"),
                Note(text: "Google Drive avec votre propre clé Google, saisie ou importée depuis son fichier JSON"),
                Note(text: "Après un plantage ou un arrêt forcé de CloudShelf, les lecteurs restés montés sont repris au lancement")
            ],
            .improved: [
                Note(text: "Avec macFUSE, les fichiers lus ne passent plus par le disque : regarder une vidéo n'occupe aucun cache", bold: true),
                Note(text: "Envois vers Dropbox par blocs de 128 Mo, 16 fichiers à la fois : 1 Go en 31 s au lieu de 56"),
                Note(text: "Envois vers Google Drive par blocs de 64 Mo, 8 fichiers à la fois : 73 Mo/s au lieu de 45"),
                Note(text: "Débit affiché tel qu'il passe sur le réseau, et non quand les apps lisent les données"),
                Note(text: "Fenêtre utilisable dès 840 × 580 points"),
                Note(text: "Lecture et écriture affichées séparément sur chaque lecteur"),
                Note(text: "Barre d'espace colorée selon le remplissage : orange à 75 %, rouge à 90 %"),
                Note(text: "Un lecteur qui ne joint pas son serveur au montage, comme à l'ouverture de session avant le réseau, réessaie pendant deux minutes et demie"),
                Note(text: "La mesure du cache ne ralentit plus l'interface, et un serveur lent ne fige plus le débit affiché"),
                Note(text: "Le journal d'un lecteur repart de zéro au-delà de 20 Mo, en gardant le précédent")
            ],
            .fixed: [
                Note(text: "Vider le cache, supprimer un lecteur ou déplacer le cache pouvait effacer des fichiers pas encore envoyés", bold: true),
                Note(text: "Le cache pouvait remplir le disque pendant une longue lecture : il est vidé sous 3 Go libres"),
                Note(text: "Un montage resté actif après l'arrêt brutal de rclone bloquait le Finder"),
                Note(text: "Le dossier d'un lecteur démonté restait dans ~/Cloud"),
                Note(text: "Changer de service dans la fenêtre d'ajout la fermait puis la rouvrait"),
                Note(text: "Un montage Google Drive freiné par Google échouait au bout de 30 secondes au lieu d'attendre rclone"),
                Note(text: "Copier un fichier téléchargé ou tagué sur un lecteur échouait avec « Operation not permitted », et pouvait laisser un fichier vide en NFS"),
                Note(text: "Copier un dossier avec le Finder échouait avec l'erreur -8062 et laissait la copie incomplète"),
                Note(text: "Après avoir quitté l'app, remonter un lecteur macFUSE pouvait échouer avec « Resource busy »"),
                Note(text: "Une grosse copie vers un lecteur pouvait remplir le disque du Mac et échouer avec l'erreur -36 : elle ralentit désormais à la vitesse d'envoi"),
                Note(text: "Éjecter un lecteur depuis le Finder le remontait cinq secondes plus tard"),
                Note(text: "Démonter un lecteur macFUSE pendant qu'un fichier était ouvert pouvait bloquer rclone, et l'app qui lisait le fichier, pendant de longues minutes"),
                Note(text: "Un lecteur dont rclone ne s'arrêtait pas restait sur « Démontage… » et ne pouvait plus être monté"),
                Note(text: "Monter un lecteur sur un dossier déjà monté par ailleurs faisait tourner deux rclone sur le même cache"),
                Note(text: "La protection du disque pouvait remonter un lecteur au milieu d'une copie"),
                Note(text: "L'erreur affichée après un arrêt de rclone pouvait dater d'un montage précédent"),
                Note(text: "Fermer une vidéo avant la fin inscrivait une erreur « stream abandoned » dans le journal"),
                Note(text: "Un lecteur nommé « .. » se montait sur le dossier parent"),
                Note(text: "Un réglage qui demande un remontage n'était appliqué qu'au montage suivant"),
                Note(text: "Les séparateurs du panneau de la barre des menus disparaissaient sur un fond sombre")
            ]
        ])
    ]
}
