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
5. Cliquez sur **Dismount** ou fermez sCrypt. Les écritures sont synchronisées et la lettre
   disparaît.

La création remplit la totalité du conteneur avec l’aléa cryptographique de Windows. Un grand
volume prend donc un temps proportionnel à sa taille.

## Architecture et portabilité

```text
std/gui.PasswordEdit ----------> main.swg
                                     |
std/core.Crypto + File + Time        v
             |               core/volume.swg -> core/crypto.swg
             |                       |
             v                       v
 security.win32.swg          platform/winfsp*.win32.swg -> WinFsp officiel
```

- `std/core` fournit désormais HMAC-SHA-256, PBKDF2-HMAC-SHA-256, ChaCha20, la comparaison en
  temps constant, l’effacement sécurisé, l’aléa cryptographique et les opérations positionnées de
  `FileStream`. Les algorithmes sont généraux ; seul le très petit adaptateur
  `security.win32.swg` appelle le générateur système `BCryptGenRandom` et `RtlZeroMemory`.
  `bcrypt.dll` fait partie de Windows et n’ajoute aucun composant à distribuer ou installer.
  La même couche standard fournit l’horloge UTC et la liste des lettres de lecteur disponibles ;
  sCrypt ne contient plus les bindings Windows correspondants.
- `std/gui.PasswordEdit` conserve le mot de passe dans un stockage fixe effacé à la destruction ;
  le `EditBox` visible ne reçoit que des caractères de masque.
- `core/crypto.swg` ne conserve que la dérivation des deux clés et l’authentification contextuelle
  propres au format sCrypt. `core/volume.swg` contient le système de fichiers logique et utilise
  directement `Core.File.FileStream`.
- `platform/winfspAbi.win32.swg` charge WinFsp dynamiquement, prépare son runtime portable et
  déclare directement son ABI en Swag.
- `platform/winfsp.win32.swg` adapte le système de fichiers sCrypt aux callbacks WinFsp.
- `main.swg` contient l’interface et l’orchestration. Les deux seuls fichiers `platform` restants
  sont les deux adaptateurs WinFsp Windows.

Un portage vers un autre OS fournit les backends système de `Core.Crypto`, `Core.Time` et
`Core.File`, puis remplace la couche WinFsp et le sélecteur de point de montage, sans modifier les
algorithmes, le format du conteneur, le widget de mot de passe ni le système de fichiers logique.

## Format et propriétés de sécurité

- 32 octets initiaux de sel aléatoire ;
- PBKDF2-HMAC-SHA-256, 200 000 itérations en production, produisant deux clés séparées ;
- deux en-têtes de métadonnées alternés et authentifiés pour tolérer une interruption de commit ;
- données en blocs de 4 Kio, chiffrées par ChaCha20 avec nonce aléatoire puis authentifiées par
  HMAC-SHA-256 ;
- écriture copy-on-write : un ancien bloc n’est recyclé qu’après publication et flush du nouvel
  en-tête ;
- aucun magic, nom, dossier, contenu, bloc libre ou taille de fichier interne n’est lisible sans
  mot de passe correct ; le reste du conteneur est initialisé avec des octets aléatoires.

Un observateur sans mot de passe voit donc un fichier de taille connue à l’apparence aléatoire,
sans signature sCrypt. Il reste impossible de garantir qu’aucune analyse contextuelle ne puisse
soupçonner qu’un gros fichier aléatoire est un conteneur chiffré.

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
incluent les vecteurs connus HMAC-SHA-256, PBKDF2-HMAC-SHA-256 et ChaCha20, les tailles de sortie
PBKDF2 partielles, le chiffrement en place, l’aléa, l’effacement mémoire et les opérations de
fichier positionnées ; les tests de `std/gui` couvrent aussi le masquage, Unicode, sélection,
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
