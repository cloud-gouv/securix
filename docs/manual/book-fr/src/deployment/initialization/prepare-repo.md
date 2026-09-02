<!--
SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Préparer le dépôt `securix-$org` ou `bureautix-$org`

Nous prendrons l'exemple de l'organisation `acme`, pour préparer le dépôt `securix-acme`, il y a deux possibilités :

* Créer sa hiérarchie et sa structure de toute pièce si on comprend bien les APIs fournies par le projet SécurixOS pour l'instantiation, il est aussi tout à fait possible de consommer les modules utiles directement et d'ignorer toutes les abstractions du projet
* Suivre un template d'exemple comme `bureautix-example`

Nous proposons d'expliquer comment travailler avec le second pour le reste de ce guide.

## Forker `bureautix-example`

<https://github.com/cloud-gouv/bureautix-example> se trouve un exemple factice d'application du kit du projet SécurixOS.

Pour s'en emparer, il est possible de le forker directement sur GitHub puis de le rendre privé (mais attention, ça laisse des traces du côté de la base de données GitHub), ou bien de le cloner puis de le repousser vers un nouveau dépôt indépendant qui est privé dès le départ.

La structure du dépôt se décompose ainsi :

```
bureautix-example/
├── common/                         # Configurations partagées (toutes machines)
│   ├── admins.nix                  # Administrateurs système via FIDO2
│   ├── filesystems.nix             # Choix du modèle de partition
│   ├── pam_u2f.nix                 # Authentification YubiKey/U2F
│   ├── printing.nix                # Drivers d'impression
│   └── tools.nix                   # Outils communs (curl, vim, htop...)
│
├── defaults/                       # Profils matériels
│   └── x280.nix                    # ThinkPad X280 (modèle de référence)
│
├── developer/                      # Profil développeur
│   └── virtualisation.nix          # Docker, KVM, libvirtd
│
├── inventory/                      # Inventaire statique
│   ├── machines/
│   │   └── PC140V35.nix            # Configuration d'une machine spécifique
│   └── users/
│       ├── alice.nix               # Comptes utilisateurs (exemples)
│       ├── bob.nix
│       └── heloise.nix
│
├── netboot/                        # Démarrage réseau PXE
│   ├── Caddyfile                   # Serveur web Caddy
│   └── shell.nix                   # Environnement netboot
│
├── npins/                          # Épinglage des dépendances
│   └── sources.json                # Versions figées des sources
│
├── pkgs/                           # Paquets Nix spécifiques à Sécurix
│   └── nixos-installer/
│       └── installer.py            # Script d'installation NixOS
│
├── workflows/                      # CI/CD pour GitHub
│   ├── build-toplevels.nix         # Construction des configurations
│   └── pre-commit.nix              # Contrôle de la qualité
│
├── default.nix                     # Point d'entrée principal Nix
├── shell.nix                       # Environnement de développement
├── treefmt.toml                    # Formatage automatique
├── README.md                       # Documentation en anglais
└── README.fr.md                    # Documentation en français
```
