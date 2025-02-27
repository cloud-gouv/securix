{ config, lib, ... }:
let
  anssiLib = import ../lib { inherit lib; };
in 
  anssiLib.mkAlwaysEnabledRule {
    number = 6;
    description = "Protection des drapeaux d'amorçage";
    reason = "Secure Boot étant toujours activé, les drapeaux d'amorçage ne sont pas modifiables.";
    inherit config;
  }
