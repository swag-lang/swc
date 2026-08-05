# sCrypt

sCrypt est une application Windows x64 écrite entièrement en Swag. Elle crée un conteneur chiffré
et le présente comme un lecteur logique normal à l’Explorateur et aux autres applications. Le
lecteur disparaît lorsque `sCrypt.exe` est fermé.

L’interface utilisateur et tous les messages affichés par l’application sont en anglais.

## Portable, sans installation préalable

Le dossier livré contient tout ce qui est nécessaire. L’utilisateur n’a pas à installer WinFsp,
MSVC, un runtime C/C++ ni un service permanent.

La GUI et le système de fichiers s’exécutent avec le jeton normal de l’utilisateur. C’est essentiel
pour que la lettre montée soit visible dans le même namespace Windows que l’Explorateur. Au premier
montage, un second mode du même `sCrypt.exe`, le guardian, demande une élévation UAC uniquement pour
démarrer le pilote portable. Il reste en arrière-plan jusqu’à la fermeture de la GUI, puis
désenregistre le runtime même si le lecteur a déjà été démonté.

Le guardian copie les binaires officiels signés de WinFsp livrés avec l’application dans un dossier
temporaire et enregistre une identité side-by-side privée pendant l’exécution. Les fichiers sont
supprimés à la fermeture ; si l’Explorateur conserve exceptionnellement la DLL chargée, leur
suppression est planifiée au prochain redémarrage. Cela ne crée pas de produit dans « Applications
installées ».

Si WinFsp est déjà présent sur la machine, sCrypt peut utiliser cette copie. Sinon, il utilise la
copie portable incluse. Le code de sCrypt et toute l’intégration WinFsp sont en Swag : il n’existe
aucun wrapper, pont ou source C/C++ dans le projet. Les DLL et pilote WinFsp restent bien sûr des
composants tiers officiels non modifiés et signés.

## Construire et tester

Le seul prérequis de développement est Windows x64 avec le compilateur Swag construit dans ce
dépôt. Depuis la racine du dépôt :

```powershell
tools\manage-applications-workspace.bat dm build -m sCrypt -bc release
tools\manage-applications-workspace.bat dm test -m sCrypt
tools\manage-applications-workspace.bat dm smoke -m sCrypt
tools\test-scrypt-integration.bat dm
```

Le build produit directement le dossier portable :

```text
bin\apps\.output\sCrypt\executable\release\x86_64\sCrypt.exe
```

Copiez ce dossier où vous le souhaitez et lancez `sCrypt.exe`. Aucun setup ni archive ZIP n’est
requis.

## Utilisation

1. Lancez normalement `sCrypt.exe`, sans utiliser « Run as administrator ».
2. Pour créer un conteneur, choisissez un nouveau chemin, une taille et un mot de passe avec sa
   confirmation. Un fichier existant n’est jamais écrasé.
3. Pour monter un conteneur, sélectionnez-le, saisissez son mot de passe et choisissez une lettre
   disponible, par exemple `A:` ou `X:`. Acceptez la demande UAC du guardian WinFsp si elle apparaît.
4. Utilisez le lecteur normalement depuis Windows.
5. Cliquez sur **Unmount** ou fermez sCrypt. Les écritures sont synchronisées et la lettre
   disparaît.

La création remplit la totalité du conteneur avec l’aléa cryptographique de Windows. Un grand
volume prend donc un temps proportionnel à sa taille.

## Architecture et portabilité

```text
std/gui FormLayoutCtrl + PasswordEdit ---> mainwindow.swg <--- vaultcard.swg
                                                  |
std/core Crypto + File + Jobs                     v
             |                    volume/{format,volume,node,nodeindex,blockallocator}
             |                                    |
             v                                    v
      Core.Crypto (BCrypt)     winfsp/{callbacks,bridge,winfspmount,guardian}.win32.swg
                                                  |
                                                  v
                                           WinFsp officiel
```

- `std/core` fournit Argon2id, ChaCha20-Poly1305, BLAKE2b, ChaCha20, HMAC-SHA-256,
  PBKDF2-HMAC-SHA-256, la comparaison en temps constant, l’effacement sécurisé, l’aléa
  cryptographique et les opérations positionnées de `FileStream`. Les algorithmes sont généraux ; seul le très petit adaptateur système de
  `Core.Crypto` appelle le générateur `BCryptGenRandom` et `RtlZeroMemory`. `bcrypt.dll` fait
  partie de Windows et n’ajoute aucun composant à distribuer ou installer. La même couche
  standard fournit l’horloge UTC et la liste des lettres de lecteur disponibles ; sCrypt ne
  contient plus les bindings Windows correspondants.
- `std/gui.PasswordEdit` conserve le mot de passe dans un stockage fixe effacé à la destruction ;
  le `EditBox` visible ne reçoit que des caractères de masque.
- `std/gui.FormLayoutCtrl` construit les champs et les arrange sans coordonnées fixes : chaque
  appel `addTextField`, `addPasswordField` ou `addChoiceField` crée son contrôle, ajoute la ligne
  étiquetée et rend le contrôle déjà typé ; `addRowAction` et `addRowChoice` complètent la ligne
  précédente. sCrypt décrit ainsi ses deux cartes sans identifiant textuel ni recherche de champ.
  `FormDlg` réutilise le même formulaire pour les boîtes modales. Le sélecteur de fichiers
  standard fournit historique, précédent, suivant, parent, actualisation, fil d’Ariane et
  raccourcis clavier.
- `main.swg` ne fait que démarrer l’application. `mainwindow.swg` possède l’état de la fenêtre,
  ses deux cartes et l’opération de fond ; `vaultcard.swg` fournit le panneau titré partagé par
  les deux cartes.
- `volume/crypto.swg` ne conserve que la dérivation des clés et l’authentification contextuelle
  propres au format. `volume/format.swg`, `volume/node.swg`, `volume/nodeindex.swg` et
  `volume/blockallocator.swg` isolent respectivement la sérialisation, les nœuds, l’index logique
  et l’allocation de blocs. `volume/volume.swg` réunit le cycle de vie persistant, les blocs
  chiffrés et les opérations de fichiers, et `volume/error.swg` porte le vocabulaire d’erreur.
- `winfsp/abi.win32.swg` déclare l’ABI et `winfsp/runtime.win32.swg` charge WinFsp dynamiquement
  en préparant son runtime portable. `winfsp/status.win32.swg`, `winfsp/callbacks.win32.swg`,
  `winfsp/bridge.win32.swg`, `winfsp/winfspmount.win32.swg` et `winfsp/mountedvolume.win32.swg`
  séparent les statuts NT, les opérations testables, l’adaptation ABI, le cycle de montage et le
  volume monté. `winfsp/guardian.win32.swg` porte le second mode élevé du même exécutable.
- Les déclarations propres à l’application et au volume restent directement dans le module. Seuls
  les vocabulaires qui forment une frontière réelle utilisent un namespace : `Crypto`, `WinFsp`
  et le harnais `Integration`. Le préfixe redondant `SCrypt` n’est pas répliqué dans chaque nom.

Un portage vers un autre OS fournit les backends système de `Core.Crypto`, `Core.Time` et
`Core.File`, puis remplace la couche WinFsp et le sélecteur de point de montage, sans modifier les
algorithmes, le format du conteneur, le widget de mot de passe ni le système de fichiers logique.

## Format et propriétés de sécurité

- une clé maîtresse aléatoire de 64 octets, tirée à la création et jamais dérivée d’un mot de
  passe ; les clés de chiffrement et de localisation en sont dérivées par BLAKE2b avec séparation
  de domaine ;
- quatre emplacements de clé, chacun portant son propre sel, son profil de coût et la clé maîtresse
  enveloppée par la clé dérivée de son mot de passe. Changer un mot de passe réécrit un seul
  emplacement ; plusieurs mots de passe peuvent coexister et l’un d’eux peut être révoqué ;
- Argon2id, RFC 9106, par défaut m = 256 Mio, t = 3, p = 4. Les paramètres sont enregistrés par
  emplacement, donc relever le coût plus tard n’invalide aucun mot de passe existant ;
- deux emplacements de métadonnées alternés et authentifiés pour tolérer une interruption de
  checkpoint ; entre deux checkpoints, chaque modification n’ajoute qu’un petit enregistrement au
  journal circulaire, relu à l’ouverture ;
- la table des entrées vit dans des blocs chiffrés indexés par l’en-tête, et non dans l’en-tête
  lui-même : le nombre de fichiers n’est plus plafonné par la taille d’un emplacement ;
- données en blocs de 4 Kio, scellées en une seule passe par ChaCha20-Poly1305, RFC 8439, avec
  nonce aléatoire ; l’étiquette couvre le genre et la position de l’enregistrement ;
- écriture copy-on-write : un ancien bloc n’est recyclé qu’après publication et flush de
  l’enregistrement qui cesse de le référencer ;
- la liste des blocs libres n’est pas stockée : elle est le complément de ce que la table des
  entrées et l’index des pages référencent, et ne peut donc pas diverger ;
- aucun magic, nom, dossier, contenu, bloc libre ou taille de fichier interne n’est lisible sans
  mot de passe correct ; le reste du conteneur est initialisé avec des octets aléatoires.

Un observateur sans mot de passe voit donc un fichier de taille connue à l’apparence aléatoire,
sans magic ni marqueur sCrypt stable : même le localisateur et la longueur du header courant sont
dérivés de la clé et de l’emplacement. Cela ne rend pas l’origine impossible à attribuer. Le nom ou
l’extension du fichier, son contexte, sa taille, sa forte entropie et l’étude du code de sCrypt
peuvent toujours indiquer qu’il s’agit vraisemblablement d’un conteneur chiffré.

Le format et l’implémentation n’ont pas encore subi d’audit cryptographique indépendant. Ne les
considérez pas comme un remplacement éprouvé de VeraCrypt pour des données critiques.

## Système de fichiers exposé

Le backend implémente notamment la création et l’ouverture de fichiers et dossiers, lecture,
écriture, fichiers creux, redimensionnement, attributs et dates, renommage et remplacement,
suppression, énumération paginée des dossiers, flush, informations de volume et descripteurs de
sécurité. Les appels sont sérialisés par la stratégie de garde grossière de WinFsp.

Les extensions NTFS optionnelles ne sont pas annoncées : liens physiques, points d’analyse, flux
nommés, attributs étendus, journal USN, quotas et compression. Les opérations ordinaires de
fichiers et dossiers n’en dépendent pas.

## Tests

Les tests propres à sCrypt couvrent les altérations de nonce, tag, ciphertext et contexte,
l’effacement des clés, les fichiers sparse, append et écritures contraintes, resize/shrink/regrow,
collisions et remplacements, lecture seule, persistance des métadonnées de sécurité, validation et
corruption des deux headers. Un test dédié exerce aussi l’adaptateur WinFsp sans charger le pilote :
create, lookup, read, write, flush, resize, security, énumération de dossiers, rename, delete et
statuts d’erreur.

Les primitives déplacées sont testées à leur nouvelle frontière : les tests de `std/core`
incluent les vecteurs de référence BLAKE2b (RFC 7693), Argon2id (RFC 9106), Poly1305 et
ChaCha20-Poly1305 (RFC 8439), ainsi que HMAC-SHA-256, PBKDF2-HMAC-SHA-256 et ChaCha20, les tailles
de sortie PBKDF2 partielles, le chiffrement en place, l’aléa, l’effacement mémoire et les
opérations de fichier positionnées ; les tests de `std/gui` couvrent aussi le masquage, Unicode, sélection,
suppression, neutralisation du presse-papiers et effacement de `PasswordEdit`.

`tools\test-scrypt-integration.bat` construit une variante de test, demande l’élévation UAC et crée une sandbox
unique sous `%TEMP%`. Elle crée un conteneur chiffré de 64 Mio avec mot de passe, choisit une lettre
réellement libre, monte le lecteur avec le WinFsp portable et effectue 34 contrôles de bout en bout :
copie d’un fichier externe aléatoire dans le volume puis récupération et comparaison octet par
octet, dossiers imbriqués, fichiers vides, noms Unicode, overwrite, append, fichier sparse,
attribut lecture seule, renommage avec remplacement, suppression et énumération d’un lot de 24
fichiers. Elle impose aussi que l’hôte du système de fichiers reste non élevé et lance un second
processus non élevé qui doit voir le lecteur et pouvoir y écrire, comme l’Explorateur. Elle démonte
ensuite le lecteur, vérifie le rejet d’un mauvais mot de passe, remonte le même conteneur, contrôle
la persistance, réécrit des données, démonte et supprime entièrement sa sandbox. Le script renvoie
un code non nul au premier échec.

WinFsp - Windows File System Proxy, Copyright (C) Bill Zissimopoulos —
<https://github.com/winfsp/winfsp>
