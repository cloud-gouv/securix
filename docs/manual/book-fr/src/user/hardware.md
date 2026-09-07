<!--
SPDX-FileCopyrightText: 2026 Antoine Eiche <antoine.eiche@lewocorp.eu>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Profils matériels

L'équipe SécurixOS maintient un ensemble de profils matériels dans le répertoire `hardware`. Ces profils matériels ont été testés manuellement et sont utilisés en environnement réel.

> [!WARNING]
> Actuellement, l'équipe n'accepte pas les contributions matérielles de la communauté qu'elle ne peut pas tester et valider en continu.

Cependant, si votre matériel n'est pas pris en charge, vous pouvez toujours l'utiliser dans SécurixOS en créant et en important votre propre module dans votre configuration, comme pris en charge par la [fonctionnalité de types d'options extensibles de NixOS](https://nixos.org/manual/nixos/stable/#sec-option-declarations-eot). Un fichier de module matériel SécurixOS `votre-materiel.nix` ressemble à :

```nix
{ pkgs, lib, config, ...}:
{
  options.securix.self.machine.hardwareSKU = mkOption {
    type = lib.types.enum ["votre-nom-materiel"];
  }
  config = lib.mkIf (config.securix.self.machine.hardwareSKU == "votre-nom-materiel") {
    # La configuration NixOS de votre matériel qui peut être générée par nixos-generate-config
  }
}
```

Dans votre configuration SécurixOS, vous pouvez ensuite importer ce fichier et activer votre configuration matérielle :

```nix
{
  imports = [ ./votre-materiel.nix ];
  config = {
    securix.self.machine.hardwareSKU = "votre-nom-materiel";
  }
}
```
