<!--
SPDX-FileCopyrightText: 2026 Quentin Cazier <cazierquentin@gmail.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Scellement du journal

Le scellement du journal (Forward Secure Sealing, FSS) permet à un administrateur de vérifier qu'un journal système n'a pas été modifié après coup. Une clé de scellement reste sur la machine et change automatiquement, une clé de vérification est conservée hors de la machine. Cela répond en partie aux recommandations R76 et R77 de l'ANSSI.

## Activer

```nix
securix.journaldFSS.enable = true;
```

Le journal est alors stocké de façon persistante et scellé.

## À l'installation

Quand l'option est active, `autoinstall-terminal` génère les clés dans le système installé, une fois la copie du système terminée. Il affiche la clé de vérification et un QR code, puis attend une confirmation. Notez la clé ou scannez le QR code : elle n'est pas conservée sur la machine et ne peut pas être retrouvée.

## Vérifier un journal

Sur la machine, avec la clé de vérification :

```sh
journalctl --verify --verify-key=<clé>
```

Chaque fichier vérifié est marqué `PASS` ou `FAIL`.

## Machines déjà installées

Activez l'option, déployez la configuration, puis générez les clés en tant que root :

```sh
journalctl --setup-keys
journalctl --rotate
```

La rotation ouvre un nouveau fichier de journal, scellé. Les fichiers antérieurs restent non scellés.

## Limites

La vérification peut échouer à tort sur des fichiers archivés quand des entrées portent un horodatage postérieur au dernier scellement, voir le ticket systemd 17833. Conservez l'intervalle de scellement par défaut de quinze minutes.

Si la clé de vérification est perdue, générez une nouvelle paire avec `journalctl --setup-keys --force`. Les fichiers scellés avec l'ancienne clé ne sont plus vérifiables.
