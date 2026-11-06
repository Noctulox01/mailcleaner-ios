# MailCleaner — app iOS

App iOS native (Swift / SwiftUI) qui affiche MailCleaner (`https://mailcleaner.fr/app`) dans un
WKWebView. Le site n'est pas modifié : l'app est un projet séparé.

Ce que fait l'app :
- s'ouvre directement sur l'écran de connexion de MailCleaner ;
- garde la session (cookies) entre deux lancements ;
- tirer vers le bas pour rafraîchir, balayer pour revenir en arrière ;
- barre de progression pendant le chargement ;
- écran « Connexion impossible » avec un bouton Réessayer quand il n'y a pas de réseau ;
- les liens vers d'autres sites, `mailto:` et `tel:` s'ouvrent dans Safari ou l'app concernée ;
- mode clair ou sombre selon le réglage de l'iPhone, iPhone et iPad, iOS 15 minimum.

---

## 1. Obtenir le `.ipa` sans Mac (GitHub Actions, gratuit)

1. Crée un compte sur <https://github.com> si tu n'en as pas.
2. Crée un **nouveau dépôt** (privé, c'est possible), par exemple `mailcleaner-ios`.
3. Envoie dans ce dépôt **le contenu du dossier `ios-app`**. Le fichier `project.yml` doit être à
   la racine du dépôt.
   - Le plus simple, sans ligne de commande : sur la page du dépôt, « Add file » → « Upload files »,
     puis glisse-dépose le contenu de `ios-app`.
   - Attention : le dossier `.github` est caché sous Windows et l'upload web l'oublie facilement.
     S'il manque, crée le fichier à la main sur GitHub (« Add file » → « Create new file »,
     nom : `.github/workflows/ios.yml`) et colle-y le contenu de `ios-app/.github/workflows/ios.yml`.
4. Ouvre l'onglet **Actions** du dépôt. Le build « Build IPA » démarre tout seul ; tu peux aussi le
   lancer avec « Run workflow ». Il dure environ 5 à 10 minutes.
5. Quand il est vert ✅, clique dessus et télécharge, en bas de la page, l'artefact
   **MailCleaner-ipa**. C'est un zip qui contient `MailCleaner-unsigned.ipa`.

## 2. Installer le `.ipa` sur ton iPhone

Ce `.ipa` n'est **pas signé**, et un iPhone refuse une app non signée. Un outil de sideload la
signe avec **ton identifiant Apple** au moment de l'installation.

**Avec Sideloadly (Windows) :**
1. Installe **iTunes** et **iCloud** en version « site Apple » (pas la version Microsoft Store),
   puis **Sideloadly** depuis <https://sideloadly.io>.
2. Branche l'iPhone en USB et accepte « Faire confiance à cet ordinateur ».
3. Dans Sideloadly : glisse `MailCleaner-unsigned.ipa`, saisis ton identifiant Apple, clique
   **Start**.
4. Sur l'iPhone : **Réglages → Général → VPN et gestion de l'appareil** → ton identifiant Apple →
   **Faire confiance**.
5. Sur iOS 16 ou plus récent, active aussi **Réglages → Confidentialité et sécurité → Mode
   développeur**. L'iPhone redémarre.

Limites d'un identifiant Apple **gratuit** :
- l'app **expire au bout de 7 jours**. Il faut la réinstaller avec Sideloadly (tes données restent) ;
- 3 apps installées ainsi en même temps au maximum.

Avec un compte Apple Developer payant (99 €/an), l'app reste valable 1 an.

## 3. Variante avec un Mac

```bash
brew install xcodegen
cd ios-app
xcodegen generate
open MailCleaner.xcodeproj
```
Dans Xcode : cible **MailCleaner** → **Signing & Capabilities** → choisis ton **Team** (ton
identifiant Apple). Si Xcode refuse l'identifiant `fr.mailcleaner.app`, remplace-le par un
identifiant unique, par exemple `fr.tonnom.mailcleaner`. Branche l'iPhone et clique ▶. L'app est
installée directement, sans passer par un `.ipa`.

## 4. Changer l'adresse du serveur

Dans `Sources/Config.swift`, modifie `siteURL`, puis relance le build. Pour un serveur local, mets
par exemple `http://192.168.1.20:5000/app`. Dans ce cas, il faut aussi autoriser le HTTP non
chiffré dans `Info.plist` (`NSAppTransportSecurity` → `NSAllowsLocalNetworking`).

## Fichiers

| Fichier | Rôle |
|---|---|
| `project.yml` | Description du projet ; XcodeGen en tire le `.xcodeproj` |
| `Sources/MailCleanerApp.swift` | Point d'entrée de l'app |
| `Sources/WebContainerView.swift` | Écran principal : page web, progression, erreur |
| `Sources/WebView.swift` | WKWebView : session, liens externes, tirer pour rafraîchir |
| `Sources/WebModel.swift` | État partagé (chargement, erreur) |
| `Sources/Config.swift` | Adresse du serveur |
| `Resources/Info.plist` | Nom affiché, orientations, réglages iOS |
| `Resources/Assets.xcassets` | Icône (reprise du logo MailCleaner) |
| `.github/workflows/ios.yml` | Build automatique du `.ipa` sur un Mac GitHub |
