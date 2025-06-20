{ lib, ... }:
let
  anssiLib = import ../lib { inherit lib; };
in 
  anssiLib.mkExternalRule {
    number = 1;
    description = "Support matériel";
    reason = "Le support matériel est hors du périmètre Sécurix.";
  }
