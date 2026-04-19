<!--
SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Durcissement du navigateur Sécurix

Cette page documente le durcissement appliqué par Sécurix au-dessus
de la baseline `firefox-esr` (voir `browser-baseline.md`). Elle
couvre :

- le modèle de menace pour un poste d'administration,
- l'analyse détaillée de la surface WebRTC et des CVE associées,
- la stratégie de mitigation en trois couches,
- la configuration effectivement appliquée dans
  `modules/tools/firefox.nix`,
- une matrice de couverture sécuritaire zone par zone,
- les implications concrètes pour l'administrateur utilisateur
  du poste et pour le RSSI de l'entité déployante.

---

## 1. Modèle de menace

Un poste Sécurix est utilisé par un administrateur de SI gouvernemental
pour opérer de l'infrastructure sensible. Les caractéristiques qui
guident le durcissement :

- **Surface réseau variable** : le poste voyage (déplacements
  inter-sites, salons, déplacements à l'étranger). Il passe par des
  réseaux Wi-Fi non maîtrisés.
- **Authentification forte** : FIDO2 / U2F est le facteur primaire
  (cf. `modules/pam/u2f.nix`). Le navigateur n'est pas l'outil
  d'authentification principal, mais il peut y participer via
  WebAuthn pour des portails gouvernementaux.
- **Visio nécessaire** : Jitsi, BigBlueButton, parfois Teams-web
  pour les échanges inter-ministériels. La visio passe par
  WebRTC — désactiver WebRTC casserait l'usage opérationnel.
- **Pas de streaming grand public** : pas de YouTube, pas de
  Netflix. EME (Widevine) est désactivé.
- **Confidentialité des IPs internes** : le poste ne doit pas
  laisser fuiter ses adresses IP de LAN / VPN vers des sites tiers.
- **Traçabilité** : le RSSI doit pouvoir auditer le flux DNS et
  le flux réseau sortant du navigateur, a minima sur le parc fixe.

Le modèle d'attaquant considéré :

- **Tracker / adtech** — volonté d'identifier l'utilisateur
  (fingerprinting, IP leak) pour monétisation.
- **Acteur opportuniste** — volonté d'exploiter une CVE
  navigateur ou un composant (WebRTC codec, JS engine) pour
  obtenir code-exec sur le poste.
- **Acteur étatique ciblé** — volonté de pivoter depuis une
  compromission initiale (phishing, watering hole) vers un canal
  C2 persistant, en bypassant les mécanismes d'audit (DNS, proxy).

Les défenses dites "privacy by default" (pas de télémétrie, pas
d'accounts) sont déjà en place dans le bloc `policies` historique
de Sécurix. Ce durcissement-ci ajoute les couches manquantes sur
la surface réseau active du navigateur.

---

## 2. Surface d'attaque WebRTC

WebRTC ne se résume pas à "RTCPeerConnection pour faire de la
visio". C'est une stack complète qui expose **quatre surfaces
distinctes**, chacune avec son vecteur.

### 2.1 Fuite d'IP via ICE / STUN (privacy leak)

L'API `RTCPeerConnection` oblige le navigateur à collecter des
**ICE candidates** (toutes les adresses par lesquelles il pourrait
être joint) avant même qu'un appel ne démarre :

- `host` candidates → IP locales (`192.168.x.x`, `10.x.x.x`, IPv6
  globale, VPN interne).
- `srflx` candidates → IP publique vue par un serveur STUN (contacté
  en UDP).
- `relay` candidates → via TURN.

**Problème** : une page peut créer une `RTCPeerConnection` **sans
prompt utilisateur** — pas de permission requise pour simplement
collecter les candidates (la permission caméra / micro n'arrive
qu'après, lors du `getUserMedia`). Un tracker peut donc récupérer
les IPs locales et publiques silencieusement.

Depuis Firefox 70, les host candidates sont obfusquées en mDNS
(UUID aléatoire), **mais uniquement côté API JS** — la résolution
mDNS expose toujours l'existence de la machine sur le LAN. Et
`srflx` reste en clair si STUN est joignable.

**Impact Sécurix** : un admin sur réseau gouvernemental voit fuir
son IP interne (10.x.y.z, routable VPN) vers n'importe quel site
visité qui veut juste savoir.

### 2.2 Exploit de la stack média (sandbox escape)

WebRTC inclut :

- **Codecs audio** : Opus, G.711.
- **Codecs vidéo** : VP8, VP9, AV1, H.264 (via libavcodec ou
  OpenH264).
- **Parsing RTP / SRTP / DTLS**.
- **Traitement SDP** (offer / answer).

C'est **des milliers de lignes de C++ qui parsent des paquets
réseau non-authentifiés**. Historiquement c'est la surface la plus
riche en bugs mémoire du navigateur :

| CVE | Date | Composant | Impact |
|---|---|---|---|
| CVE-2023-4863 | 2023-09 | libwebp (heap overflow) | RCE exploité in-the-wild (Pegasus, Chrome 0-day). Firefox impacté via rendu d'images. |
| CVE-2024-9680 | 2024-10 | Animation timeline UAF | RCE exploité in-the-wild. Firefox ESR patch d'urgence. Chaînable WebRTC. |
| CVE-2022-26485 | 2022-03 | XSLT (pas WebRTC direct) | Exploité en production contre journalistes. |
| CVE-2019-11708 | 2019-06 | IPC sandbox escape | Chaîné avec RCE content-process (WebRTC le premier cran). |
| CVE-2018-18500 | 2018-10 | SDP parser | Crash + potentiel RCE. |

**Point clé** : le WebRTC stack est dans le **content process**.
Un RCE WebRTC → attaquant dans le sandbox content. Pour s'évader,
il faut un second bug (sandbox escape). Si
`kernel.unprivileged_userns_clone = 0`, le sandbox content-process
ne peut même pas démarrer correctement sur Firefox (fallback
chroot-only ou non-sandboxé) : l'arbitrage sera tranché dans la
Wave Q2 Sécurix.

### 2.3 Fingerprinting device-level

Même sans permission caméra / micro,
`navigator.mediaDevices.enumerateDevices()` retourne :

- Liste des caméras / micros avec label anonymisé (sauf si
  permission déjà donnée — alors label = "USB Camera 2.0").
- **`deviceId` stable par profil** → fingerprint persistant
  cross-session sur le même site.
- Nombre de devices → fingerprint machine.

Combiné avec codec support + RTT STUN + timezone → identification
quasi-unique.

### 2.4 Tunnel C2 post-exploit

Post-compromission, WebRTC est un vecteur d'exfiltration de choix :

- UDP direct avec NAT hole-punching → bypass proxy HTTPS système.
- DTLS encapsule n'importe quel payload.
- Pas de SNI observable par middlebox.
- TURN-over-TCP-443 ressemble à du TLS normal.

Un malware qui a code-exec dans le content process (ou en escape)
peut ouvrir un tunnel C2 via STUN / TURN publics sans toucher aux
DNS loggés.

---

## 3. Stratégie de mitigation en trois couches

Il n'existe **pas** de pref Firefox qui dirait "WebRTC API activée
pour `meet.jit.si` uniquement". L'API est globale. On doit composer
trois couches.

### 3.1 Couche A — prefs globales pour réduire la surface IP-leak

Configurée dans `policies.json / Preferences`, toutes en
`Status = "locked"` :

| Pref | Valeur | Effet |
|---|---|---|
| `media.peerconnection.enabled` | `true` | API reste disponible (sinon visio KO). |
| `media.peerconnection.ice.no_host` | `true` | **Zéro host candidate** → pas de fuite IP LAN / VPN. |
| `media.peerconnection.ice.default_address_only` | `true` | Une seule interface sortante → pas d'énumération multi-NIC. |
| `media.peerconnection.ice.proxy_only_if_behind_proxy` | `true` | Force TURN si proxy système configuré. |
| `media.peerconnection.identity.enabled` | `false` | Feature morte, surface code inutile. |
| `media.navigator.enabled` | `true` | `enumerateDevices` nécessaire pour Jitsi. |
| `media.peerconnection.turn.disable` | `false` | TURN nécessaire pour NAT symétrique en mobilité. |

**Résultat** : WebRTC fonctionne (Jitsi, BBB, Teams-web marchent),
mais sans leak d'IPs LAN / VPN et avec une seule interface srflx
au lieu de l'énumération complète.

### 3.2 Couche B — prompt caméra / micro par session

Trois états possibles par origine pour caméra / micro :

- `0 = ask` → prompt à l'utilisateur à chaque requête.
- `1 = allow` → auto-grant sans prompt.
- `2 = block` → auto-deny sans prompt.

Sécurix force l'état `ask` pour caméra / micro / partage d'écran,
et bloque dur la géolocalisation. En plus, `persistDecisions=false`
empêche "Se souvenir de cette décision" — la permission retombe à
`ask` à la fermeture de l'onglet.

| Pref | Valeur | Effet |
|---|---|---|
| `permissions.default.camera` | `0` (ask) | Prompt natif à chaque requête caméra. |
| `permissions.default.microphone` | `0` (ask) | Idem micro. |
| `permissions.default.screen` | `0` (ask) | Idem partage d'écran. |
| `permissions.default.geo` | `2` (block) | Géolocalisation bloquée dur — pas de prompt. |
| `privacy.permissionPrompts.persistDecisions` | `false` | Pas de persistance — permission tombe à la fermeture. |

Côté `Permissions` (verrouillage UI dans `about:preferences`) :

| Entrée | Option | Effet |
|---|---|---|
| `Camera` | `Locked = true` | User ne peut pas désactiver la demande depuis `about:preferences`. |
| `Microphone` | `Locked = true` | Idem. |
| `Location` | `BlockNewRequests = true`, `Locked = true` | Pas de prompt, auto-deny. |
| `Notifications` | `BlockNewRequests = true`, `Locked = true` | Pas de prompt notification. |
| `Autoplay` | `Default = "block-audio-video"`, `Locked = true` | Aucun autoplay. |

**Flux pour l'admin qui ouvre Jitsi** :

1. Jitsi appelle `getUserMedia({video, audio})`.
2. Firefox affiche la barre jaune : *"meet.jit.si demande à utiliser
   votre caméra et micro"*.
3. L'admin clique **[Autoriser]** → permission pour la session
   courante.
4. L'admin ferme l'onglet → permission retombe à `ask`.
5. Prochaine visite → nouveau prompt.

**Flux pour un site inattendu qui tente `getUserMedia`** :

1. Prompt s'affiche.
2. L'admin voit une demande suspecte → **[Bloquer]** ou **[×]**.
3. Le site ne peut pas capturer.

### 3.3 Couche C — layers réseau complémentaires

Ces mesures ne sont **pas** configurables via `policies.json` et
doivent être traitées hors scope du module Sécurix firefox — mais
elles sont listées ici parce qu'elles **sont nécessaires** pour
fermer les trous de la Couche A :

| Risque résiduel Couche A | Layer à ajouter |
|---|---|
| Srflx IP publique observable au STUN | Allowlist firewall UDP 3478 / 5349 + DNS allowlist des domaines STUN / TURN approuvés. |
| Tunnel C2 via TURN post-exploit | Même allowlist que ci-dessus — combinée avec détection SIEM sur UDP long-lived hors allowlist. |
| Bypass du proxy HTTP en mobilité | VPN always-on tunnelisant l'UDP + force TURN-over-TCP-443 pour auditer. |

---

## 4. Autres durcissements appliqués par policies.json

En dehors de WebRTC, plusieurs autres surfaces sont fermées :

### 4.1 DoH (TRR) désactivé

`network.trr.mode = 5` → DoH complètement désactivé. Raison : un
DoH activé par Firefox **bypasse le résolveur DNS entreprise** et
envoie les requêtes directement à un provider externe (Cloudflare
par défaut dans certaines régions). Dans un contexte gouvernemental
avec DNS interne logué, c'est une fuite et une perte de visibilité
SIEM.

### 4.2 PPA (Privacy-Preserving Attribution)

`dom.private-attribution.submission.enabled = false`. Cette feature
a été activée par défaut dans Firefox 128 (juillet 2024), sans
consentement explicite, ce qui a déclenché une polémique notable.
Elle envoie des informations d'attribution publicitaire agrégées à
un serveur Mozilla. Désactivée pour toute installation Sécurix.

### 4.3 Safe Browsing désactivé

Les quatre prefs `browser.safebrowsing.{malware,phishing,downloads,
downloads.remote}.enabled = false`. Safe Browsing pingue en continu
`shavar.services.mozilla.com` qui proxyfie les listes Google Safe
Browsing. Le tradeoff :

- **Côté gain privacy** : pas de métadonnées de navigation
  envoyées à Mozilla / Google.
- **Côté perte** : plus d'alerte Firefox sur site de phishing /
  malware connu.

Compensation partielle : uBlock Origin pré-installé filtre la
majorité des domaines malveillants connus via les listes
EasyPrivacy / NoCoin / etc.

### 4.4 Géolocalisation désactivée

`geo.enabled = false` + `geo.provider.use_geoclue = false` (Linux).
Et `permissions.default.geo = 2` au niveau permissions. Pas d'appel
aux Google Location Services — même si une application tente une
requête, elle échoue sans prompt.

### 4.5 Connexions spéculatives / DNS prefetch

Quatre prefs désactivées (`network.prefetch-next`,
`network.dns.disablePrefetch`, `network.predictor.enabled`,
`network.http.speculative-parallel-limit=0`). Chaque fois que la
souris survole un lien, Firefox peut pré-résoudre le DNS et
pré-ouvrir une connexion TCP / TLS. C'est une fuite passive de
comportement vers les domaines non-cliqués.

### 4.6 Suggestions de recherche

`browser.search.suggest.enabled = false` et
`browser.urlbar.suggest.searches = false`. Sans ça, chaque frappe
dans la barre d'URL envoie une requête AJAX au moteur de recherche
par défaut, révélant la frappe en temps réel (y compris les
commandes partielles que l'utilisateur n'envoie jamais réellement).

### 4.7 Debug distant désactivé

`devtools.debugger.remote-enabled = false`. Les devtools locales
restent utilisables (F12) — seule l'écoute TCP du debugger à
distance est fermée, ce qui élimine un vecteur post-exploit pour
piloter le navigateur depuis l'extérieur.

### 4.8 Moteur de recherche par défaut

`SearchEngines.Default = "Qwant"` + `SearchEngines.Add` pour
ajouter explicitement l'entrée Qwant au profil. Non verrouillé
(pas de `Locked = true`) : l'utilisateur peut basculer sur
DuckDuckGo, Google, Startpage, etc. selon ses besoins
opérationnels.

Le choix Qwant apporte :

- **Souveraineté numérique** : moteur français, infrastructure en
  UE, pas de soumission au CLOUD Act américain.
- **Politique no-tracking déclarée** : pas de profilage
  publicitaire, pas de log IP utilisateur permanent.
- **Cohérent avec le contexte gouvernemental** : aligné avec les
  recommandations DINUM sur les services numériques d'État.
- **Fallback intégré** : l'entrée `SearchEngines.Add` garantit la
  présence de Qwant même si le pack de langue FR n'est pas actif
  (edge case : poste en locale `en-US`). Sans cette précaution,
  un `Default = "Qwant"` sur un profil non-FR fait silencieusement
  retomber Firefox sur Google.

Pour un déploiement qui préfère explicitement un autre moteur
(DuckDuckGo pour recherches en anglais sur de la doc technique,
Startpage pour un proxy Google neutre, etc.), surcharger
`SearchEngines.Default` dans une couche locale au-dessus de ce
module suffit. Le binding `qw` (alias déclaré pour Qwant) est
accessible depuis la barre d'URL : `qw <requête>` cherche sur
Qwant indépendamment du moteur par défaut.

### 4.9 New Tab — pas de contenu sponsorisé

`browser.newtabpage.activity-stream.showSponsored = false` et
`showSponsoredTopSites = false`. La page de nouvel onglet, qui
redirige vers le dashboard local Sécurix, n'affiche plus les
"top sites sponsorisés" Mozilla.

### 4.10 Capture formulaire désactivée

`signon.formlessCapture.enabled = false`. Complément de
`PasswordManagerEnabled=false` — empêche la capture passive de
valeurs saisies dans des formulaires qui ne sont pas explicitement
`<form>`. Utile contre les exfiltrations d'identifiants coincés
dans des widgets JS non-standard.

### 4.11 Fingerprinting resistance (opt-in)

Activé seulement si `securix.firefox.hardenFingerprinting = true`.
Deux prefs :

- `privacy.resistFingerprinting = true`
- `privacy.resistFingerprinting.letterboxing = true`

Normalise timezone (toujours UTC), écran (letterboxing pour
masquer la taille réelle), canvas, audio, liste de polices.
Puissant mais **casse** de nombreux sites gouvernementaux
(portails qui vérifient la cohérence timezone-locale, anti-fraude
bancaire), d'où l'opt-in par déploiement.

---

## 5. Matrice de couverture sécuritaire

Statut de chaque zone d'attaque après application du durcissement.

Légende : ✅ couverte / 🟡 partielle / ❌ non couverte par le
navigateur (relève d'une autre couche).

| # | Zone d'attaque | Statut | Mécanisme actif | Limitation / pourquoi | Implication admin | Implication RSSI |
|---|---|---|---|---|---|---|
| 1 | Fuite IP LAN / VPN via host candidates | ✅ | `ice.no_host=true` | Aucune. | Transparent. | Topo interne préservée. |
| 2 | Fuite IP publique via srflx / STUN | 🟡 | `default_address_only=true` — 1 interface sortante | L'IP publique reste visible au STUN contacté (nécessaire au fonctionnement ICE). | En mobilité, IP sortante observable par STUN du site. | Firewall allowlist STUN / TURN obligatoire. |
| 3 | Capture caméra / micro drive-by | ✅ | Prompt natif + `persistDecisions=false` + `Locked=true` | Social engineering reste possible. | Refuser les prompts inattendus. | Formation "prompt suspect = bloquer". |
| 4 | Fingerprinting `enumerateDevices` | 🟡 | Labels vides sans permission | `deviceId` stable par profil reste un fingerprint. | Transparent. | Accepté résiduel. Mitigation : profil unique par poste. |
| 5 | Exploit codec RCE (WebRTC stack) | ❌ | — | Dépend du patch management. | Appliquer MAJ ESR. | SLA ≤ 7 jours, veille CERT-FR. |
| 6 | Sandbox escape content-process | 🟡 | Sandbox Firefox natif (userns + seccomp + CGroups) | Dégradé si `unprivileged_userns=0` (Wave Q2). | Transparent. | Arbitrage Wave Q2. |
| 7 | Tunnel C2 post-exploit via WebRTC | ❌ | — | JS peut ouvrir `RTCPeerConnection` silencieuse vers TURN public. | Invisible. | SIEM sur UDP 3478 / 5349 hors allowlist. |
| 8 | NAT hole-punching hors proxy | 🟡 | `proxy_only_if_behind_proxy=true` | Sans proxy système, WebRTC sort direct UDP. | En mobilité, perd l'audit proxy. | VPN always-on + TURN-over-TCP. |
| 9 | Codec fingerprinting via SDP | ❌ | — | SDP expose codecs supportés. | Transparent. | Accepté résiduel. Mitigation : parc homogène. |
| 10 | Création silencieuse `RTCPeerConnection` | ❌ | — | API reste appelable. | Transparent. | Firewall DNS allowlist STUN / TURN. |
| 11 | Peer Identity WebRTC (legacy) | ✅ | `identity.enabled=false` | Aucune. | Transparent. | Validé. |
| 12 | Push de config remote (Normandy, Shield) | ✅ | `DisableFirefoxStudies`, `DisableTelemetry` | Aucune si policies à jour. | Transparent. | Validé. |
| 13 | Partage d'écran `getDisplayMedia` | ✅ | `permissions.default.screen=0` + `Locked=true` | Social engineering "partagez votre écran". | Prompt à chaque partage. | Cf. formation (ligne 3). |
| 14 | Géolocalisation (API + IP) | ✅ | `geo.enabled=false`, `permissions.default.geo=2` | IP reste observable réseau. | Transparent. | Validé côté JS API. |
| 15 | Debug distant navigateur | ✅ | `devtools.debugger.remote-enabled=false` | Devtools locales restent accessibles. | Transparent. | Validé. |
| 16 | Résolution DNS via DoH | ✅ | `network.trr.mode=5` | DNS système utilisé → loggué par DNS entreprise. | Transparent. | Permet filtrage et corrélation SIEM. |
| 17 | PPA (Private Attribution) envoi télémétrie | ✅ | `dom.private-attribution.submission.enabled=false` | Aucune. | Transparent. | Validé depuis FF 128. |
| 18 | Safe Browsing — ping Mozilla / Google | ✅ | 4 prefs `browser.safebrowsing.*.enabled=false` | Plus d'alerte phishing / malware Firefox. | Transparent. | Compensation partielle via uBlock Origin. |
| 19 | Autoplay audio / vidéo | ✅ | `Permissions.Autoplay.Default="block-audio-video"` + `media.autoplay.default=5` | Aucune. | Transparent. | Validé. |
| 20 | Connexions spéculatives / DNS prefetch | ✅ | 4 prefs réseau à `false / 0` | Aucune. | Transparent. | Réduit fuite DNS passive. |
| 21 | Suggestions de recherche live | ✅ | `browser.search.suggest.enabled=false` | User tape, aucune requête avant [Entrée]. | Suggestions ne s'affichent plus. | Aucune requête par frappe → pas de leak moteur. |
| 22 | Fingerprinting canvas / timezone / écran | 🟡 (opt-in) | `privacy.resistFingerprinting` si `securix.firefox.hardenFingerprinting=true` | Casse certains sites (intranet gov). | Dépend opt-in. | Arbitrage entité : activer pour populations sensibles. |
| 23 | Capture formulaires non-`<form>` | ✅ | `signon.formlessCapture.enabled=false` + `PasswordManagerEnabled=false` | Aucune. | Transparent. | Validé. |
| 24 | Contenu sponsorisé New Tab | ✅ | 2 prefs `showSponsored=false` | Aucune. | New Tab propre. | Validé. |

---

## 6. Ce que la matrice implique opérationnellement

### 6.1 Pour l'administrateur (utilisateur du poste)

1. **2 clics par session visio** : prompt caméra + prompt micro
   à chaque ouverture Jitsi / BBB. Irritation minime mais
   **garantit la conscience de la capture média**.
2. **Réflexe "prompt inattendu = refuser"** : si un site non-visé
   demande caméra / micro / partage d'écran, refuser
   systématiquement. Cas typiques : onglet resté ouvert, redirect
   via bannière pub compromise, tab-napping.
3. **Mobilité = vigilance +** : en déplacement (airport, hôtel),
   l'IP publique sortante fuit aux STUN (ligne 2 de la matrice).
   Éviter de visiter des sites sensibles et de faire une visio en
   parallèle.
4. **Pas de "Se souvenir de cette décision"** : la permission
   tombe à chaque fermeture d'onglet. Ne pas s'étonner du
   re-prompt.
5. **Suggestions de recherche absentes** : la barre d'URL ne
   propose plus rien en live — il faut taper l'URL complète ou
   appuyer sur [Entrée] pour chercher.
6. **Safe Browsing inactif** : pas d'avertissement Firefox sur
   site frauduleux — s'appuyer sur uBlock Origin et le bon sens
   pour la détection.

### 6.2 Pour le RSSI de l'entité

**Ce que la config browser vous donne** — posture baseline ESR +
hardening :

1. Aucun auto-grant caméra / micro / partage d'écran possible.
2. Aucune fuite IP interne (LAN / VPN) via STUN.
3. Aucun push de config remote Mozilla (Normandy / Shield).
4. Aucune requête DoH — DNS enterprise reste l'autorité.
5. Aucune télémétrie PPA.
6. Aucun ping Safe Browsing (pas de signal vers Mozilla / Google).
7. Toutes les permissions média verrouillées — l'utilisateur ne
   peut pas se bypass lui-même.

**Ce que la config browser NE vous donne PAS**, à traiter ailleurs :

| Risque résiduel | Layer de défense à ajouter | Priorité |
|---|---|---|
| Exploit codec WebRTC (0-day + N-day) | Patch mgmt ESR 140, SLA ≤ 7 j, abo Mozilla advisories, dashboard CVE | 🔴 Critique |
| Tunnel C2 via TURN public | Firewall allowlist UDP 3478 / 5349 + DNS allowlist domaines STUN / TURN légitimes | 🔴 Critique |
| Sandbox faible si `unprivileged_userns=0` | Décision Wave Q2 + compensation Tetragon DNS (PR #146) + isolation réseau | 🟠 Majeur |
| Mobilité sans proxy | VPN always-on tunnels UDP + TURN-over-TCP pour audit | 🟠 Majeur |
| Fingerprinting résiduel (deviceId, SDP codecs) | Profil utilisateur unique par poste ; homogénéité parc | 🟢 Résiduel accepté |
| Social engineering prompt | Formation 10 min + piqûre rappel annuelle | 🟡 Organisationnel |

**Ce que le RSSI doit documenter dans sa DSP / PAS** :

- Adoption de la posture Sécurix browser (baseline ESR +
  hardening) comme référence technique.
- Règles firewall complémentaires (allowlist STUN / TURN).
- SLA patch ESR.
- Plan de formation utilisateurs.
- Acceptation explicite des risques résiduels catégorie ❌.

**Ce que le RSSI doit vérifier périodiquement** :

- Versions `firefox-esr` déployées (pas de dérive vers une ESR EOL).
- Revue trimestrielle des règles firewall STUN / TURN.
- Test de la chaîne "CVE Mozilla → bump nixpkgs → déploiement" (SLA).
- Alerte SIEM sur pattern UDP STUN hors allowlist.
- Audit des sites autorisés dans les `Permissions.Camera.Allow` et
  `Microphone.Allow` (si une entité ajoute une allowlist locale
  au-dessus du default Sécurix).

---

## 7. Extensions actives sur Sécurix

Deux extensions sont pré-installées et verrouillées :

| Extension | Rôle | Source |
|---|---|---|
| **uBlock Origin** (`uBlock0@raymondhill.net`) | Blocage de trackers, annonces, domaines malveillants connus. Compensation partielle de Safe Browsing. | addons.mozilla.org signé Mozilla |
| **Bitwarden** (`{446900e4-71c2-419f-a6a7-df9c091e268b}`) | Gestionnaire de mots de passe externe (Firefox interne désactivé). | addons.mozilla.org signé Mozilla |

Toutes les autres extensions sont en `installation_mode = blocked`
(cf. `ExtensionSettings."*".installation_mode`). L'ajout d'une
extension nouvelle passe par une proposition sur le repo Sécurix.

---

## 8. Références

- ANSSI — *Recommandations pour le déploiement sécurisé du
  navigateur Mozilla Firefox sous Windows* —
  <https://www.ssi.gouv.fr/entreprise/guide/recommandations-pour-le-deploiement-securise-du-navigateur-mozilla-firefox-sous-windows/>
- Mozilla Enterprise Policies —
  <https://mozilla.github.io/policy-templates/>
- Mozilla Security Advisories —
  <https://www.mozilla.org/en-US/security/advisories/>
- CERT-FR (bulletins Firefox) — <https://www.cert.ssi.gouv.fr/>
- `policies.json` — spécification de la pref
  `dom.private-attribution.submission.enabled` (Firefox 128+).
- NIST SP 800-63B rev. 3 (2017), § 5.1.1.2.
- OWASP Top 10 — A07 Identification and Authentication Failures.
- Zhang, Monrose, Reiter — *The Security of Modern Password
  Expiration*, ACM CCS 2010 (hors scope navigateur mais cité dans
  la posture de sécurité Sécurix adjacent).
- `browser-baseline.md` — page sœur qui couvre le choix ESR, la
  stratégie d'épinglage et la baseline ANSSI.
