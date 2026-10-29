<!--
SPDX-FileCopyrightText: 2026 Quentin Cazier <cazierquentin@gmail.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Scellement du journal

Le scellement du journal (Forward Secure Sealing, FSS) permet à un administrateur de vérifier qu'un journal système n'a pas été modifié après coup. Une clé de scellement reste sur la machine et change automatiquement, une clé de vérification est conservée hors de la machine. Cela répond en partie aux recommandations R76 et R77 de l'ANSSI.

## Activer

Les clés sont générées par l'installateur, l'interrupteur est donc une option de l'installateur, passée à `buildUSBInstallerISO` ou `buildNetbootInstaller` :

```nix
preprovisionOptions = {
  secureBoot = "self-contained";
  tpm2HostKeys = true;
  ageHostKeys = true;
  skipPreflightChecks = false;
  journaldFSS = true;
};
```

Les autres options gardent ici leurs valeurs par défaut. Le stockage persistant et le scellement sont déjà les valeurs par défaut de journald, rien ne change dans le système installé lui-même.

## À l'installation

Quand l'option est active, `autoinstall-terminal` génère les clés dans le système installé, une fois la copie du système terminée. Il affiche la clé de vérification et un QR code, puis attend une confirmation. Notez la clé ou scannez le QR code : elle n'est pas conservée sur la machine et ne peut pas être retrouvée.

## Vérifier un journal

La clé de vérification permet aussi de recalculer les clés de scellement : elle ne doit jamais être saisie sur la machine elle-même. Copiez les fichiers `.journal` de `/var/log/journal/<machine-id>/` vers une machine de confiance, par exemple avec une clé USB ou `scp`, puis vérifiez-les depuis cette machine :

```sh
journalctl --verify --verify-key=<clé> --directory=<copie>
```

Le fichier `fss` du même dossier est la clé de scellement, inutile de le copier. Chaque fichier vérifié est marqué `PASS` ou `FAIL`. Le test `tests/journald-fss.nix` déroule toute la séquence, de l'installation à la vérification d'une copie.

## Machines déjà installées

Activez l'option, déployez la configuration, puis générez les clés en tant que root :

```sh
journalctl --setup-keys
journalctl --rotate
```

La première commande affiche la clé de vérification et un QR code : conservez la clé hors de la machine, en lieu sûr. La rotation ouvre un nouveau fichier de journal, scellé. Les fichiers antérieurs restent non scellés.

## Limites

La vérification peut échouer à tort sur des fichiers archivés quand des entrées portent un horodatage postérieur au dernier scellement, par exemple quand l'horloge a reculé et que journald a archivé le fichier, ce qui peut arriver au premier démarrage. Voir le ticket systemd 17833. Conservez l'intervalle de scellement par défaut de quinze minutes.

Si la clé de vérification est perdue, générez une nouvelle paire avec `journalctl --setup-keys --force`. Les fichiers scellés avec l'ancienne clé ne sont plus vérifiables.
