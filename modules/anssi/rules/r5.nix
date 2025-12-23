{ lib, ... }:
let
  anssiLib = import ../lib { inherit lib; };
in 
  anssiLib.mkNotApplicableRule {
    number = 5;
    description = "Mot de passe sur le chargeur d'amorçage";
    reason = "Secure Boot étant toujours activé, les drapeaux d'amorçage ne sont pas modifiables, le mot de passe n'est pas nécessaire ainsi.";
  }
