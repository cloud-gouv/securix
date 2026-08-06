# SPDX-FileCopyrightText: 2026 Pauline Legrand <pauline.legrand@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.chromium;
in

{
  ###### interface

  options = {
    programs.chromium = {
      enable = lib.mkEnableOption "policies for chromium based browsers like Chromium, Google Chrome or Brave";

      extraOptsRecommended = lib.mkOption {
        type = lib.types.attrs;
        description = ''
          Extra chromium policy options in recommended. A list of available policies
          can be found in the Chrome Enterprise documentation:
          <https://cloud.google.com/docs/chrome-enterprise/policies/>
          Make sure the selected policy is supported on Linux and your browser version.
        '';
        default = { };
        example = lib.literalExpression ''
          {
            "BrowserSignin" = 0;
            "SyncDisabled" = true;
            "PasswordManagerEnabled" = false;
            "SpellcheckEnabled" = true;
            "SpellcheckLanguage" = [
              "de"
              "en-US"
            ];
          }
        '';
      };
    };
  };

  ###### implementation

  config = {
    environment.etc = lib.mkIf cfg.enable {
      "chromium/policies/recommended/extra.json" = lib.mkIf (cfg.extraOptsRecommended != { }) {
        text = builtins.toJSON cfg.extraOptsRecommended;
      };
      "opt/chrome/policies/recommended/extra.json" = lib.mkIf (cfg.extraOptsRecommended != { }) {
        text = builtins.toJSON cfg.extraOptsRecommended;
      };
      "brave/policies/recommended/extra.json" = lib.mkIf (cfg.extraOptsRecommended != { }) {
        text = builtins.toJSON cfg.extraOptsRecommended;
      };
    };
  };
}
