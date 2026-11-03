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
                Note(text: "Renommer, dupliquer ou supprimer un lecteur depuis la liste ou sa fiche")
            ],
            .improved: [
                Note(text: "Avec macFUSE, les fichiers lus ne passent plus par le disque : regarder une vidéo n'occupe aucun cache", bold: true),
                Note(text: "Envois vers Dropbox par blocs de 128 Mo, 16 fichiers à la fois : 1 Go en 31 s au lieu de 56"),
                Note(text: "Débit affiché tel qu'il passe sur le réseau, et non quand les apps lisent les données"),
                Note(text: "Fenêtre utilisable dès 840 × 580 points"),
                Note(text: "Lecture et écriture affichées séparément sur chaque lecteur"),
                Note(text: "Barre d'espace colorée selon le remplissage : orange à 75 %, rouge à 90 %")
            ],
            .fixed: [
                Note(text: "Vider le cache, supprimer un lecteur ou déplacer le cache pouvait effacer des fichiers pas encore envoyés", bold: true),
                Note(text: "Le cache pouvait remplir le disque pendant une longue lecture : il est vidé sous 3 Go libres"),
                Note(text: "Un montage resté actif après l'arrêt brutal de rclone bloquait le Finder"),
                Note(text: "Le dossier d'un lecteur démonté restait dans ~/Cloud"),
                Note(text: "Changer de service dans la fenêtre d'ajout la fermait puis la rouvrait"),
                Note(text: "Les séparateurs du panneau de la barre des menus disparaissaient sur un fond sombre")
            ]
        ])
    ]
}
