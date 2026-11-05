# Docklume

App macOS native (SwiftUI, macOS 15+, Apple Silicon) qui monte des stockages cloud comme disques dans le Finder, à la
manière de RaiDrive sous Windows, avec un rclone patché inclus. Priorité au débit, puis à une interface native.
S'appelait CloudShelf jusqu'à la 0.2 : le nom était une marque déposée par d'autres.

## Règles de travail

- Tout ce que lit l'utilisateur est en français : messages, récapitulatifs, questions, boutons, étapes de tâches.
  Le code, ses commentaires et les messages de commit restent en anglais.
- Pas de remplissage : réponses denses et factuelles, commentaires seulement quand l'intention n'est pas évidente,
  textes d'interface courts, ton Apple.
- Committer ou pousser seulement à la demande.
- Interface : garder la disposition de `design/maquette.html` (barre latérale de navigation, liste de cartes de
  lecteurs, fenêtre d'ajout en deux colonnes), à l'échelle 1 px CSS = 1 pt. La variante qui listait les lecteurs dans
  la barre latérale (`maquette-v2.html`) a été refusée. Le panneau de la barre des menus ouvre ou monte un lecteur,
  sans jamais le démonter. Les notes de version suivent la frise de raidrive.com/release-notes. Logo officiel :
  `design/logo-docklume-2048.png`.
- Quitter, recompiler ou relancer l'app de l'utilisateur démonte ses lecteurs : vérifier les envois en attente et
  demander avant.
- Écrire dans le cloud de l'utilisateur seulement avec son accord, dans un dossier de test, purgé ensuite vers la
  corbeille du service.
- Captures publiées (README, site) : comptes de démo uniquement, jamais de vrais e-mails ni identifiants.
- Ne jamais afficher ni committer `rclone.conf` (jetons, clé Google).
- Benchmarks et montages de test : délai dur (`perl -e 'alarm 120; exec @ARGV' …`), un point de montage par essai.

## Compiler

1. Moteur : `scripts/build-rclone.sh` (Go dans `~/.local/go` ou le PATH, macFUSE installé). Clone rclone v1.75.2
   dans `rclone/`, applique `rclone-patches/`, produit `build/rclone/rclone` en version `v1.75.2-docklume.N`.
   Incrémenter `BUILD` quand un patch change.
2. App : `xcodebuild -project Docklume.xcodeproj -scheme Docklume -configuration Debug -derivedDataPath build/DerivedData build`.
   La phase « Embed rclone » copie le moteur dans `Contents/MacOS` (supprimer puis copier : macOS tue un binaire signé
   réécrit sur place).
3. Vérification rapide sans Xcode : `swiftc -Onone` sur les sources, comme dans `tools/` (environ 15 s).

`build/` et `rclone/` sont ignorés par git. L'app est signée ad hoc (`CODE_SIGN_IDENTITY "-"`) : chaque build est une
nouvelle app pour macOS, qui redemande l'accès aux volumes réseau. Signature Apple Development et notarisation : pas
encore faites.

## Organisation

- `App/` : `DocklumeApp` (l'AppDelegate possède DriveStore et AppState, gère Dock, barre des menus et ouverture de
  session), `FormerName` (reprise unique des données de CloudShelf).
- `Engine/` : `Rclone` (trouve le moteur, inclus d'abord), `MountSession` (un process `rclone mount` ou `nfsmount` par
  lecteur, rc sur 127.0.0.1 avec identifiants par variables d'environnement, arrêt, reprise des orphelins),
  `RemoteControl`, `CacheFolder` (purge et déplacement qui gardent les fichiers pas encore envoyés et `finderMeta`),
  `DiskSpace`, `SpeedProbe`, `TagShortcuts`, `Accounts`.
- `Model/` : `Drive` (état, et `MountOptions` : tous les drapeaux rclone avec leurs mesures en commentaire),
  `DriveStore` (catalogue, montages, protection du disque), `Provider`, `Preferences`, `ConnectionDraft`,
  `OAuthClient`, `Releases` (notes de version affichées dans l'app).
- `Views/` : `Theme` (jetons), `Controls` (contrôles maison), `MainWindow`, `Pages/`, `Dialogs/`, `MenuBarPanel`.
- Données : `~/Library/Application Support/Docklume/drives.json`, `~/Library/Caches/Docklume/<id>` (cache VFS et
  `finderMeta`), `~/Library/Logs/Docklume/<id>.log`. Montages dans `~/Cloud/<nom>`. Au premier lancement, les remotes
  de `rclone.conf` sont importés en lecture seule ; ceux créés par l'app y sont écrits et supprimés avec leur dernier
  lecteur.

## Patches rclone (`rclone-patches/`)

| Patch | Rôle |
|---|---|
| 0001 | `--vfs-read-chunk-streams-total` : 16 flux partagés entre les fichiers lus (Dropbox refuse plus d'environ 16 téléchargements simultanés par compte) |
| 0002 | rc `core/downloaded` : octets réellement reçus, pour le débit en lecture (`core/stats` ne bouge que quand l'app lit) |
| 0003 | macFUSE : attributs étendus acceptés au lieu de ENOSYS, sinon copier un fichier téléchargé ou tagué échoue (EPERM) |
| 0004 | NFS : `._*` et `.DS_Store` gardés en mémoire, jamais envoyés |
| 0005 | macFUSE : idem, et `noappledouble` retiré (erreur Finder -8062 sur la copie d'un dossier) |
| 0006 | VFS : une écriture attend quand le disque est bas et que des envois sont en attente (sinon disque plein, erreur -36) |
| 0007 | VFS : fermer un fichier avant la fin n'est plus une erreur (« stream abandoned ») |
| 0008 | macFUSE : tags, FinderInfo et commentaires du Finder gardés dans `<cache>/finderMeta` |

## Choix mesurés

Les valeurs et leurs mesures sont en commentaire dans `MountOptions` (`Model/Drive.swift`). Ne pas les changer sans
remesurer. L'essentiel :

- Dropbox : blocs de 8 Mo ou moins → `too_many_requests` ; 64M × 4 a figé un montage macFUSE. Lecture en 32M sur
  macFUSE, 16M sur NFS, 16 flux partagés avec le moteur inclus.
- NFS a besoin du cache `full` (sans cache, chaque lecture NFS rouvre le fichier). macFUSE lit sans disque, en
  `--vfs-cache-mode writes`.
- Envois : Dropbox en blocs de 128M sur 16 transferts, Google Drive en 64M sur 8.
- rclone ne libère pas un fichier en cours de lecture en NFS : sous 3 Go libres (`DiskSpace.floor`), l'app remonte le
  lecteur avec un cache vidé, sauf si des envois sont en attente ou des fichiers modifiés attendent sur le disque.
- La clé Google partagée de rclone est limitée et en fin de vie : l'app accepte une clé Google personnelle
  (`GoogleKeyDialog`).

## Comportements macOS à connaître

- Arrêt macFUSE : `/sbin/umount`, puis `umount -f`, SIGINT en dernier recours (SIGINT seul laissait rclone bloqué
  10 à 15 min). NFS : SIGINT. Un point de montage resté occupé se règle par rmdir puis mkdir.
- Une éjection depuis le Finder fait sortir rclone avec le code 0 : pas de remontage automatique.
- Au lancement, l'app reprend les rclone orphelins (ppid 1) dont `--cache-dir` correspond à un lecteur.
- NFS : `--option locallocks` est obligatoire (le serveur rclone n'a pas de NLM). NFS ne garde pas les tags.
- Spotlight n'indexe pas macFUSE, donc la liste Tags du Finder ne montre rien : l'app tient `~/Cloud/Tags/<tag>/`,
  des alias marqués par l'attribut `fr.docklume.target`, et ne supprime que les siens.
- App de fond : `LSUIElement = true`, car des utilitaires comme Vorssaint quittent les apps du Dock restées sans
  fenêtre. Politique `.regular` au lancement, `.accessory` à la fermeture de la fenêtre. Revenir dans le Dock en étant
  active demande `deactivate` puis `activate` en différé.
- kDrive en WebDAV : `https://<ID>.connect.kdrive.infomaniak.com`, avec l'ID qui suit `/drive/` dans l'adresse web
  (le premier nombre est l'organisation).

## Vérifier

- `tools/tests/run.sh` : reprise des données de CloudShelf et des alias de tags, sur de faux dossiers personnels.
- `tools/screenshots/render.sh` : refait `docs/images` (README et site) avec des comptes de démo et liste les images
  qui ont changé. Copier ensuite les images voulues dans `docs/images`.
- Tests sans toucher aux lecteurs de l'utilisateur : `RCLONE_CONFIG` vers un fichier temporaire avec un remote
  `local`, `rclone serve webdav` ou `serve http --bwlimit 30M` pour simuler un serveur, RAM disk
  (`hdiutil attach -nomount ram://N` puis `diskutil erasevolume`) pour le disque plein.
- Copie Finder : `osascript -e 'tell application "Finder" to duplicate (POSIX file A as alias) to (POSIX file B as alias) with replacing'`
  renvoie le code d'erreur du Finder.
- Les nouvelles tentatives de rclone sur un quota Google ne sont journalisées qu'en DEBUG.

## Publier

- Dépôt public `LFR-54/Docklume` (MIT). Site GitHub Pages dans `docs/` (lfr-54.github.io/Docklume), dont
  `confidentialite.html` pour l'écran de consentement Google.
- Nouvelle version : `MARKETING_VERSION` et `CURRENT_PROJECT_VERSION` dans le projet, `Model/Releases.swift` (la
  dernière avec `latest: true`), README.
- Logos : `brand-*.imageset` en PDF vectoriel tirés de Wikimedia Commons (OneDrive en PNG), crédités dans le README.
  L'icône kDrive est redessinée depuis les calques de Infomaniak/ios-kDrive (GPL-3.0).
