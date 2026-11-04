<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="">
</p>

<h1 align="center">CloudShelf</h1>

<p align="center">
  <b>Vos stockages en ligne, montés comme des disques dans le Finder.</b><br>
  Dropbox, Google Drive, OneDrive, S3, NAS… en un clic, à pleine vitesse, sur un moteur rclone optimisé.
</p>

<p align="center">
  <img alt="macOS 15 ou plus récent" src="https://img.shields.io/badge/macOS-15%2B-111?logo=apple&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-111">
  <img alt="Swift 6 et SwiftUI" src="https://img.shields.io/badge/Swift%206-SwiftUI-F05138?logo=swift&logoColor=white">
  <img alt="rclone 1.75.2" src="https://img.shields.io/badge/rclone-1.75.2-3F79AD">
  <a href="LICENSE"><img alt="Licence MIT" src="https://img.shields.io/badge/licence-MIT-2EA44F"></a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/drives-dark.png">
    <img src="docs/images/drives-light.png" width="920" alt="Fenêtre principale de CloudShelf : cinq lecteurs, dont une médiathèque Dropbox lue à 104 Mo/s">
  </picture>
</p>

CloudShelf transforme chaque compte en ligne en un lecteur du Finder, comme RaiDrive sous Windows. L'app est native, en SwiftUI, et pilote [rclone](https://rclone.org) : un processus par lecteur, réglé pour le service et pour l'usage, avec le débit affiché en direct.

## Points forts

- **Rapide.** Le moteur rclone fourni avec l'app répartit 16 connexions entre les fichiers lus. Sur Dropbox, une lecture monte à 60 Mo/s, et plusieurs lectures saturent une ligne à 110 Mo/s.
- **Deux façons de monter.** macFUSE lit directement depuis le réseau, sans rien écrire sur le disque. Le client NFS intégré à macOS ne demande aucune installation.
- **Un profil par usage.** *Streaming* pour Emby, Plex et Jellyfin, *Documents* pour le travail courant, *Sauvegarde* pour les grosses copies.
- **Toujours là.** CloudShelf s'ouvre à l'ouverture de session, fenêtre fermée, et monte vos lecteurs. Fermer la fenêtre retire l'icône du Dock mais laisse l'app dans la barre des menus. Elle s'arrête seulement quand vous choisissez Quitter.
- **Le débit en direct.** Un graphique dans la barre des menus, une page Activité, et un test de débit par lecteur.
- **Vos envois protégés.** CloudShelf garde dans le cache tout fichier pas encore envoyé, même quand vous videz le cache, et prévient avant de démonter ou de quitter.
- **Les tags du Finder.** Sur les lecteurs macFUSE, les tags et les couleurs posés dans le Finder restent sur le Mac. `~/Cloud/Tags` les rassemble, un dossier par tag avec un alias par élément, à épingler dans la barre latérale : Spotlight n'indexe pas ces lecteurs, et la section Tags du Finder ne les voit pas.
- **Le disque protégé.** Quand l'espace libre baisse, CloudShelf vide le cache du lecteur qui en libère le plus, sans toucher aux envois en attente.
- **Sans surprise.** Reconnexion automatique si rclone s'arrête ou si le réseau manque au montage, lecteurs repris tels quels après un arrêt brutal de l'app, éjection depuis le Finder respectée, limite de débit appliquée à chaud, fichiers `.DS_Store` et `._*` tenus à l'écart du cloud.
- **Privé.** Aucun serveur, aucune télémétrie : vos identifiants restent dans `rclone.conf`, sur votre Mac.

## En images

<table>
  <tr>
    <td width="50%" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/detail-dark.png">
        <img src="docs/images/detail-light.png" alt="Fiche d'un lecteur : débit, cache, espace libre et réglages">
      </picture>
      <p align="center"><b>Fiche du lecteur</b><br><sub>Profil, cache, limite de débit, méthode de montage</sub></p>
    </td>
    <td width="50%" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/activity-dark.png">
        <img src="docs/images/activity-light.png" alt="Page Activité : débit des 60 dernières secondes et envois en cours">
      </picture>
      <p align="center"><b>Activité</b><br><sub>Débit des 60 dernières secondes, lecteur par lecteur</sub></p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/add-dark.png">
        <img src="docs/images/add-light.png" alt="Ajout d'un lecteur : liste des services et options">
      </picture>
      <p align="center"><b>Ajout d'un lecteur</b><br><sub>Connexion par le navigateur pour les services OAuth</sub></p>
    </td>
    <td width="50%" align="center" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/panel-dark.png">
        <img src="docs/images/panel-light.png" width="300" alt="Panneau de la barre des menus avec le graphique de débit">
      </picture>
      <p align="center"><b>Barre des menus</b><br><sub>Débit, lecteurs et envois d'un coup d'œil</sub></p>
    </td>
  </tr>
</table>

## Services pris en charge

| Cloud | Serveurs et NAS |
| --- | --- |
| Dropbox · Google Drive · OneDrive · Box · MEGA · Proton Drive · kDrive · compatibles S3 (AWS, Backblaze, Wasabi, R2) | WebDAV · SFTP · FTP et FTPS · SMB · Synology · QNAP · Nextcloud et ownCloud |

Les remotes déjà présents dans votre `rclone.conf` sont importés au premier lancement, en lecture seule. Le chiffrement rclone crypt se coche à l'ajout d'un lecteur.

## Performances

Mesuré sur un compte Dropbox réel, avec une ligne d'environ 110 Mo/s :

| Mesure | Résultat |
| --- | --- |
| Lecture d'un seul fichier | 60 Mo/s |
| Deux fichiers lus en même temps | 71 Mo/s au total |
| Plusieurs lectures | 100 à 110 Mo/s, le plafond de la ligne |
| Envoi d'un fichier de 1 Go | 31 s, contre 56 s avec les réglages par défaut de rclone |
| Envoi de 50 petits fichiers | 15 s, contre 40 s |

Dropbox accepte environ 16 téléchargements simultanés par compte et refuse ou ralentit au-delà. Le moteur de CloudShelf reste sous cette limite tout en donnant à chaque fichier lu autant de connexions qu'il peut en utiliser.

Sur Google Drive, avec une ligne montante de 76 Mo/s, les envois passent par blocs de 64 Mo, 8 fichiers à la fois : 73 Mo/s, contre 45 Mo/s avec les réglages par défaut de rclone.

## Fonctionnement

```mermaid
flowchart LR
    Finder["Finder, Emby, Plex"] -- "macFUSE ou NFS" --> Mount["rclone mount<br>un processus par lecteur"]
    App["CloudShelf"] -- "lance et surveille par l'API rc" --> Mount
    Mount -- HTTPS --> Cloud[("Dropbox, Google Drive, S3…")]
```

- Chaque lecteur a son propre processus rclone, son propre dossier de cache et son serveur de contrôle sur `127.0.0.1`, protégé par un mot de passe tiré à chaque lancement.
- L'app lit le débit, les envois et l'état du cache par l'API rc de rclone, une fois par seconde.
- Les réglages de montage sont regroupés dans `MountOptions` ([Drive.swift](CloudShelf/Model/Drive.swift)), avec la mesure qui justifie chacun.

### Le moteur rclone modifié

CloudShelf embarque rclone 1.75.2 avec huit correctifs, dans [`rclone-patches/`](rclone-patches) :

| Correctif | Rôle |
| --- | --- |
| [**Connexions partagées**](rclone-patches/0001-vfs-shared-read-streams.patch) | Ajoute `--vfs-read-chunk-streams-total`, un budget de connexions partagé par tous les fichiers ouverts. Une lecture démarre avec 4 connexions et en prend davantage tant qu'elle attend le réseau. |
| [**Octets reçus**](rclone-patches/0002-core-downloaded.patch) | Ajoute l'appel rc `core/downloaded`, qui compte les octets reçus du réseau. `core/stats` ne les compte qu'une fois lus par l'app, ce que macFUSE fait par paquets de plusieurs centaines de mégaoctets. |
| [**Attributs macOS**](rclone-patches/0003-cmount-discard-xattrs-macos.patch) | Accepte les attributs étendus sans les garder, comme le cloud. Sinon macOS les range dans des fichiers `._`, que le montage interdit, et la copie d'un fichier téléchargé ou tagué échoue avec « Operation not permitted ». |
| [**Fichiers `._` et `.DS_Store` en NFS**](rclone-patches/0004-serve-nfs-macos-files-in-memory.patch) | En NFS, macOS range les attributs dans des fichiers `._`, et le Finder écrit des `.DS_Store`. Quand les filtres les excluent, le serveur NFS les garde en mémoire au lieu de les envoyer au cloud. CloudShelf monte aussi en NFS avec des verrous locaux, sans lesquels macOS refuse d'écrire les fichiers `._`. |
| [**Fichiers `._` et `.DS_Store` avec macFUSE**](rclone-patches/0005-cmount-macos-files-in-memory.patch) | L'option `noappledouble` de macFUSE refuse de créer ces fichiers, et le Finder abandonne alors la copie de tout dossier qui contient un `.DS_Store` (erreur -8062). rclone les garde en mémoire à la place de macFUSE, sans les montrer dans les listes ni les envoyer au cloud. |
| [**Écritures sur un disque presque plein**](rclone-patches/0006-vfs-wait-for-uploads-when-disk-low.patch) | Les fichiers écrits passent par le cache local avant d'être envoyés. Le Finder écrit plus vite que la connexion n'envoie, et une grosse copie remplissait le disque, puis échouait (erreur -36). Sous `--vfs-cache-min-free-space`, chaque écriture attend que les envois en cours libèrent de la place, 10 s au plus : la copie ralentit à la vitesse d'envoi au lieu d'échouer. |
| [**Lecture interrompue**](rclone-patches/0007-vfs-close-before-end-is-not-an-error.patch) | Fermer un fichier avant la fin, comme une vidéo arrêtée, abandonne les blocs lus d'avance. rclone le comptait comme une erreur de transfert, et le journal se remplissait d'erreurs « stream abandoned ». |
| [**Tags du Finder**](rclone-patches/0008-cmount-keep-finder-tags.patch) | Le cloud ne garde pas les attributs étendus, et le correctif 0003 les écarte. Les tags, l'étiquette de couleur et le commentaire du Finder sont gardés à la place sur le Mac, à côté du cache du lecteur, et suivent leurs fichiers renommés ou supprimés depuis le montage. Ils ne sont pas envoyés au cloud. Avec macFUSE uniquement. |

## Compiler

**Prérequis :** macOS 15 ou plus récent sur Apple Silicon, Xcode 26, [Go](https://go.dev/dl/) 1.26 et [macFUSE](https://macfuse.github.io) 5, nécessaire pour compiler le moteur.

```bash
git clone https://github.com/LFR-54/CloudShelf.git
cd CloudShelf
scripts/build-rclone.sh
xcodebuild -project CloudShelf.xcodeproj -scheme CloudShelf -configuration Release -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Release/CloudShelf.app
```

`build-rclone.sh` télécharge rclone 1.75.2, applique les correctifs et produit `build/rclone/rclone`, que Xcode copie dans l'app.

**Pour monter avec macFUSE**, autorisez son extension dans Réglages Système › Confidentialité et sécurité. Sur Apple Silicon, macOS demande d'abord de passer en sécurité réduite depuis le mode de récupération. Sans macFUSE, choisissez « NFS intégré » dans la fiche du lecteur.

## Google Drive : utilisez votre propre clé

rclone se connecte par défaut à Google Drive avec une clé partagée par tous ses utilisateurs. Google limite souvent cette clé, ce qui ralentit le montage et la navigation, et rclone annonce son retrait courant 2026. Avec votre propre clé, gratuite, vous avez votre propre quota.

1. Créez un client OAuth de type « Application de bureau » dans Google Cloud, en suivant le [guide de rclone](https://rclone.org/drive/#making-your-own-client-id), puis publiez l'application pour que l'accès ne soit pas coupé au bout de 7 jours.
2. Dans CloudShelf, ouvrez la fiche du lecteur, puis **Clé Google › Utiliser ma clé…**. Collez l'ID client et le code secret, ou importez le fichier JSON téléchargé à la création du client.
3. Autorisez CloudShelf dans le navigateur. Le lecteur est remonté avec la nouvelle clé.

Pour un nouveau lecteur, cochez « Utiliser ma propre clé Google » avant de vous connecter.

## Confidentialité

CloudShelf ne collecte rien et ne passe par aucun serveur : votre Mac échange directement avec les services que vous connectez. Les détails sont dans les [règles de confidentialité](https://lfr-54.github.io/CloudShelf/confidentialite.html).

## Licence

CloudShelf est publié sous [licence MIT](LICENSE). rclone est un logiciel de Nick Craig-Wood et de ses contributeurs, sous licence MIT ; les correctifs de `rclone-patches/` sont publiés sous la même licence. macFUSE n'est pas inclus et garde sa propre licence.

Les logos des services appartiennent à leurs propriétaires et servent seulement à les reconnaître. Ils viennent de [Wikimedia Commons](https://commons.wikimedia.org), recadrés sur leur symbole : celui de Nextcloud vient d'openDesk, sous licence Apache 2.0, et les autres sont dans le domaine public. L'icône de kDrive est © Infomaniak, redessinée d'après celle de l'app [ios-kDrive](https://github.com/Infomaniak/ios-kDrive), sous licence GPL-3.0.
