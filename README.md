# MailCleaner — app iPhone (native)

Application iOS native écrite en Swift et SwiftUI. Elle se connecte à l'API d'un serveur MailCleaner et
affiche tout avec des écrans iOS natifs : ce n'est pas un site web dans une fenêtre. Le site n'est pas
modifié.

## Fonctions

- **Connexion et inscription**, avec **double authentification** : application d'authentification,
  code par e-mail ou code de secours. On peut faire confiance à l'iPhone pendant 30 jours.
- **Accueil** : statistiques, boîtes mail connectées, progression des analyses en direct.
- **Ajout de boîte** iCloud, Gmail ou Outlook, avec les étapes et la **vidéo explicative** pour créer
  un mot de passe d'application. Outlook se connecte avec Microsoft quand le serveur le permet.
- **Détail d'une boîte** : nombre de messages par dossier, vidage de la corbeille et des indésirables,
  analyse, application des règles, déconnexion.
- **Nettoyer** : expéditeurs triés par volume, recherche, filtres (newsletters, volumineux), sélection
  multiple. On supprime, bloque, se désabonne ou protège un expéditeur en le balayant ou par appui long.
- **Règles** : expéditeurs bloqués, mots-clés, expéditeurs protégés, protection automatique des contacts.
- **Activité** : historique des actions.
- **Compte** : prénom, mot de passe, double authentification (QR code généré sur le téléphone,
  ouverture directe dans l'app d'authentification, codes de secours), abonnement et clé d'activation,
  export des données, suppression du compte.
- Vérification anti-afflux du serveur résolue automatiquement par l'app.
- Mode sombre, Dynamic Type, VoiceOver.

## Serveur

Par défaut, l'app vise `http://192.168.137.1:5002`, c'est-à-dire le PC vu depuis son point d'accès
sans fil Windows. Pour changer l'adresse : sur l'écran de connexion, touchez l'icône serveur en haut à
droite. Le bouton « Tester la connexion » vérifie que le serveur répond.

## Compilation

Chaque envoi sur GitHub déclenche le build « Build IPA » (onglet **Actions**). Il produit
`MailCleaner-unsigned.ipa`, à télécharger dans les artefacts du build puis à installer avec Sideloadly.

Sur un Mac :
```bash
brew install xcodegen
xcodegen generate
open MailCleaner.xcodeproj
```

## Organisation du code

| Dossier | Contenu |
|---|---|
| `Sources/App` | Point d'entrée, navigation principale |
| `Sources/Core` | Client de l'API, modèles, état global, suivi des tâches, QR codes, formats |
| `Sources/Views/Auth` | Connexion, inscription, double authentification, réglage du serveur |
| `Sources/Views/Home` | Accueil, ajout d'une boîte, détail d'une boîte |
| `Sources/Views/Clean` | Expéditeurs et nettoyage |
| `Sources/Views/Rules` | Règles |
| `Sources/Views/Activity` | Historique |
| `Sources/Views/Account` | Compte, mot de passe, double authentification, abonnement |
| `Sources/Views/Components` | Composants visuels partagés |
