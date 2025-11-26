# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT
{ lib, ... }:
{
  # Sécurix is usually used in France.
  time.timeZone = lib.mkDefault "Europe/Paris";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  console = {
    # Let the kernel be smart.
    font = null;
    keyMap = lib.mkDefault "fr";
  };
  services.xserver.xkb.layout = lib.mkDefault "fr";
}
