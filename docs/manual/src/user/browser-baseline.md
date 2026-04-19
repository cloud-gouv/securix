<!--
SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Baseline navigateur sur Sécurix

Les postes Sécurix embarquent **Firefox ESR** (*Extended Support
Release*) comme navigateur par défaut, épinglé via
`programs.firefox.package = pkgs.firefox-esr;` dans
`modules/tools/firefox.nix`.

Cette page explique le choix, et la façon dont la baseline évolue
dans le temps.

## Pourquoi Firefox ESR plutôt que le canal Release

Firefox est publié sur deux canaux en parallèle :

| Canal | Cadence | Évolution fonctionnelle | Audience |
|---|---|---|---|
| **Release** (`pkgs.firefox`) | ~1 major / 4 semaines + dot-releases hebdo | Chaque version embarque de nouvelles features et changements UI | Utilisateurs grand public qui veulent les dernières features |
| **Extended Support Release** (`pkgs.firefox-esr`) | ~1 major / an, dot-releases security-only entre-temps | Pas de features nouvelles une fois le major coupé ; uniquement les correctifs de sécurité | Grands parcs, postes d'administration, gouvernement / éducation |

Pour un poste Sécurix, trois propriétés du canal ESR en font le
défaut approprié :

1. **Dot-releases security-only.** Entre deux majors ESR, le
   canal ne livre que les backports CVE. Pas de nouveau code
   feature, pas de refonte d'UI, pas de bascule de policies (voir
   la polémique Firefox 128 / PPA —
   `dom.private-attribution.submission.enabled` activé par défaut
   en cours de major sur Release, ce qu'ESR évite).
2. **Surface des policies entreprise prévisible.** Les clés de
   `policies.json` changent rarement dans un major ESR. La
   politique de durcissement Sécurix reste valide ~12 mois par
   cycle ESR.
3. **Fenêtre de chevauchement.** Chaque nouveau ESR N+1 livre
   environ 3 mois en parallèle d'ESR N. Cette fenêtre est le
   temps dont on dispose pour tester le prochain major, porter
   les policies dont la clé a changé, et migrer le parc sans
   perdre les correctifs de sécurité.

## Ce que signifie "baseline ESR" en pratique

Sécurix épingle `pkgs.firefox-esr`. À l'écriture de ce document,
cela pointe sur **Firefox ESR 140.9.1esr** (supporté en sécurité
par Mozilla jusqu'à ~mi-2026). Quand nixpkgs bumpera `firefox-esr`
sur le prochain major ESR — probablement ESR 148 ou plus, quand
Mozilla fera tourner la branche ESR — Sécurix suivra au bump de
canal suivant.

**Pas de pin dur sur un major ESR** (ex. `firefox-esr-140`) :
nixpkgs retire les attributs ESR historiques dès que Mozilla cesse
le support sécurité (ESR 128 a déjà disparu de nixpkgs 25.11 après
l'arrêt des patches Mozilla). Un pin dur laisserait Sécurix sans
correctifs de sécurité quelques mois après chaque bump.

Le compromis est qu'un bump de canal nixpkgs peut déplacer
silencieusement le major ESR sous-jacent. Mitigation :

- La CI doit builder `tests.full` contre le nouvel ESR et remonter
  les erreurs d'évaluation de policies (toute clé de policy
  retirée upstream fait échouer le build).
- Les release notes signalent les bumps ESR.

## Baseline de configuration de référence

La baseline de durcissement Firefox sur Sécurix suit deux
références publiques :

- **ANSSI — *Recommandations pour le déploiement sécurisé du
  navigateur Mozilla Firefox sous Windows*** (guide, *pas* une
  certification CSPN ; les préférences sont indépendantes de l'OS
  malgré le cadrage Windows du document). Voir
  <https://www.ssi.gouv.fr/entreprise/guide/recommandations-pour-le-deploiement-securise-du-navigateur-mozilla-firefox-sous-windows/>
- **Documentation des policies entreprise Mozilla** —
  <https://mozilla.github.io/policy-templates/>

> **Précision sur le statut de certification.** Firefox ESR n'est
> **pas** actuellement certifié CSPN par l'ANSSI (aucun certificat
> listé au catalogue `cyber.gouv.fr/produits-certifies` à la date
> 2026-04). Ce qui existe est le guide de déploiement ci-dessus,
> qui est un ensemble de recommandations de durcissement publié
> par l'ANSSI — une référence de baseline utile, mais pas une
> certification formelle de niveau cryptographique. La posture
> Sécurix est *"alignée sur le guide ANSSI de déploiement"* ; elle
> n'est *pas* *"certifiée CSPN"*.

Les préférences et policies effectivement appliquées par-dessus
cette baseline sont couvertes dans une page complémentaire,
`browser-hardening.md` (introduite par un changement ultérieur
— voir l'historique de commits de `modules/tools/firefox.nix`).

## Ce que ce pin **ne change pas**

- Le bloc `programs.firefox.policies` existant dans
  `modules/tools/firefox.nix` (homepage dashboard, bookmarks,
  `DisableTelemetry`, `DisablePocket`, `DisableFirefoxAccounts`,
  uBlock Origin + Bitwarden pré-installés, `NoDefaultBookmarks`,
  etc.) s'applique à l'identique sur ESR — la surface de policies
  entreprise est partagée entre les canaux Release et ESR.
- `programs.firefox.nativeMessagingHosts.packages` (actuellement
  `tridactyl-native`) continue de fonctionner.
- Les profils utilisateurs migrés depuis une installation
  précédente Firefox Release continuent de fonctionner ; un
  downgrade de profil Firefox est non-trivial, mais ne devrait
  pas s'appliquer ici car ESR 140 est une version numérique
  postérieure à tout Release qu'aurait pu utiliser le parc
  (140.x > 128.x, etc.).

## Ce que cette baseline ne durcit PAS encore

Basculer de canal règle le problème de cadence des changements.
Cela ne verrouille **pas** la surface d'attaque visible de
l'utilisateur. ESR 140.9.1 livre toujours les défauts suivants
actifs, et le bloc `programs.firefox.policies` actuel n'en traite
qu'une partie. Les opérateurs doivent lire ce tableau comme
l'état intermédiaire entre le changement de canal (cette page)
et le durcissement complet à venir dans `browser-hardening.md`.

| Feature | Défaut ESR 140.9.1 | Traité par `firefox.nix` actuel | Statut |
|---|---|---|---|
| Télémétrie (Glean) | activée | `DisableTelemetry` | ✅ |
| Pocket | activé | `DisablePocket` | ✅ |
| Firefox Accounts / Sync | activé | `DisableFirefoxAccounts` | ✅ |
| Studies / Normandy | activés | `DisableFirefoxStudies` | ✅ |
| EME (Widevine) | activé | `EncryptedMediaExtensions=false` | ✅ |
| Gestionnaire de mots de passe | activé | `PasswordManagerEnabled=false` | ✅ |
| **PPA** — default-on depuis FF 128 | activé | ❌ | **lacune** |
| **WebRTC** avec host ICE candidates (fuite IP LAN / VPN) | activé | ❌ | **lacune** |
| **DoH (TRR)** — auto-opt-in par région, contourne DNS entreprise | conditionnel | ❌ | **lacune** |
| **Safe Browsing** — pingue `shavar.services.mozilla.com` | activé | ❌ | **lacune** |
| **Autoplay** audio / vidéo | conditionnel | ❌ | **lacune** |
| **Géolocalisation** — Google Location Services | activée, prompt | ❌ | **lacune** |
| **Connexions spéculatives / DNS prefetch** | activées | ❌ | **lacune** |
| **Suggestions de recherche** — requête au moteur à chaque frappe | activées | ❌ | **lacune** |
| **Persistance des permissions caméra / micro** | activée | ❌ | **lacune** |

Tant que ces lacunes ne sont pas fermées, un poste Sécurix sur
cette baseline fuit encore les IPs internes via WebRTC, fait
tourner PPA, contacte Safe Browsing et persiste les permissions
caméra / micro entre sessions. Celles-ci sont traitées dans le
changement de durcissement suivant qui introduit
`browser-hardening.md`.

## Risques résiduels qu'aucune configuration navigateur ne couvre

Même un `policies.json` complètement durci ne ferme pas toutes
les classes d'attaque liées au navigateur. Les risques résiduels
suivants appartiennent à d'autres couches de défense et doivent
être planifiés par le RSSI de l'entité qui déploie.

| Risque résiduel | Couche de défense à ajouter | Priorité |
|---|---|---|
| RCE codec dans la stack WebRTC (0-day / N-day — libwebp, libvpx, libopus…) | Gestion des patches ESR ; SLA ≤ 7 jours de l'avis Mozilla au déploiement parc ; veille CERT-FR + Mozilla advisories | 🔴 Critique |
| Tunnel C2 via TURN public post-exploitation | Allowlist firewall UDP 3478 / 5349 + allowlist DNS des domaines STUN / TURN approuvés | 🔴 Critique |
| Sandbox content-process affaibli si `kernel.unprivileged_userns_clone=0` | Décision Wave Q2 + détection Tetragon DNS-evasion (PR #146) en compensation + isolation réseau renforcée | 🟠 Majeur |
| Usage nomade sans proxy entreprise (le navigateur échappe à l'audit DNS + proxy) | VPN always-on tunnelisant l'UDP + forcer TURN-over-TCP pour audit | 🟠 Majeur |
| Fingerprinting résiduel (deviceId stable, liste de codecs SDP) | Profil utilisateur unique par poste ; homogénéité du parc pour que la forme SDP ne soit pas discriminante | 🟢 Accepté résiduel |
| Social engineering sur le prompt caméra / micro | Formation sensibilisation 10 min + piqûre annuelle | 🟡 Organisationnel |

## Ce qu'il faut surveiller après le pin

- **Compatibilité des extensions** : ESR conserve une fenêtre de
  support plus longue pour les APIs WebExtension. Les extensions
  connues bonnes (uBlock Origin, Bitwarden) marchent sur ESR. Des
  extensions propres qui dépendent d'APIs expérimentales peuvent
  échouer — tester avant d'ajouter au parc via `ExtensionSettings`.
- **Clés de policies entreprise** : si une policy Mozilla upstream
  est renommée, le canal ESR porte le renommage plus tard que
  Release. Les logs de build remonteront l'erreur d'évaluation.
- **Bulletins de sécurité** : suivre
  <https://www.mozilla.org/en-US/security/advisories/> et
  <https://www.cert.ssi.gouv.fr/> pour les annonces CVE. La SLA
  Sécurix sur les patches de sécurité doit viser ≤ 7 jours entre
  la publication Mozilla et le déploiement parc.
