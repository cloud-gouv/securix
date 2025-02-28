{ config, lib, ... }:
let
  anssiLib = import ../lib { inherit lib; };
in 
  anssiLib.mkAlwaysEnabledRule {
    number = 3;
    description = "Secure Boot";
    reason = "Sécurix nécessite toujours la présence d'UEFI Secure Boot.";
    inherit config;
  }
