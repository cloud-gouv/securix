<!--
SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Prepare the `securix-$org` or `bureautix-$org` repository

We will take the example of the organization `acme`, to prepare the `securix-acme` repository, there are two possibilities:

* Create your hierarchy and structure from scratch if you understand the APIs provided by the SécurixOS project for instantiation, it is also quite possible to consume the useful modules directly and ignore all the project's abstractions
* Follow an example template like `bureautix-example`

We propose to explain how to work with the latter for the rest of this guide.

## Fork `bureautix-example`

<https://github.com/cloud-gouv/bureautix-example> is a dummy example of applying the SécurixOS kit.

To take it over, you can fork it directly on GitHub then make it private (but be careful, it leaves traces in GitHub's database), or clone it then push it to a new independent repository that is private from the start.

The repository structure is as follows:

```
bureautix-example/
├── common/                         # Shared configurations (all machines)
│   ├── admins.nix                  # System administrators via FIDO2
│   ├── filesystems.nix             # Partition model choice
│   ├── pam_u2f.nix                 # YubiKey/U2F authentication
│   ├── printing.nix                # Printing drivers
│   └── tools.nix                   # Common tools (curl, vim, htop...)
│
├── defaults/                       # Hardware profiles
│   └── x280.nix                    # ThinkPad X280 (reference model)
│
├── developer/                      # Developer profile
│   └── virtualisation.nix          # Docker, KVM, libvirtd
│
├── inventory/                      # Static inventory
│   ├── machines/
│   │   └── PC140V35.nix            # Specific machine configuration
│   └── users/
│       ├── alice.nix               # User accounts (examples)
│       ├── bob.nix
│       └── heloise.nix
│
├── netboot/                        # PXE network boot
│   ├── Caddyfile                   # Caddy web server
│   └── shell.nix                   # netboot environment
│
├── npins/                          # Dependency pinning
│   └── sources.json                # Pinned source versions
│
├── pkgs/                           # Nix packages specific to Sécurix
│   └── nixos-installer/
│       └── installer.py            # NixOS installer script
│
├── workflows/                      # CI/CD for GitHub
│   ├── build-toplevels.nix         # Building configurations
│   └── pre-commit.nix              # Quality checks
│
├── default.nix                     # Main Nix entry point
├── shell.nix                       # Development environment
├── treefmt.toml                    # Automatic formatting
├── README.md                       # Documentation in English
└── README.fr.md                    # Documentation in French
```
