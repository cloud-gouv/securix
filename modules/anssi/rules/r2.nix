{ lib, ... }:
let
  anssiLib = import ../lib { inherit lib; };
in 
  anssiLib.mkExternalRule {
    number = 2;
    description = "BIOS / UEFI";
    reason = "Sécurix ne fonctionne qu'avec UEFI et ne paramètre pas le matériel.";
  }
