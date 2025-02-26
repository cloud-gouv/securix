# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  # Sécurix is not meant to be used outside of France.
  time.timeZone = "Europe/Paris";
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    # Let the kernel be smart.
    font = null;
    keyMap = "fr";
  };
  services.xserver.xkb.layout = "fr";
}
