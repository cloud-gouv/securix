{ config, lib, ... }:
let
  anssiLib = import ../lib { inherit lib; };
in 
  anssiLib.mkAlwaysEnabledRule {
    number = 4;
    description = "Suppression des clefs préchargés Secure Boot";
    reason = "Sécurix, dans son installation, priorise la suppresion des clefs préchargés Secure Boot en faveur d'un enrollement basé sur l'eventlog du TPM2.";
    inherit config;
  }
