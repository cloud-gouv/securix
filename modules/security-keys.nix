# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

# We mostly use Yubikeys.
{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.yubikey-personalization
    pkgs.yubikey-manager
  ];
  services.udev.packages = [
    pkgs.yubikey-personalization
    pkgs.yubikey-manager
  ];

  # GPG support.
  # TODO: we don't have a need for GPG keys yet.
  programs.gnupg.agent.enable = false;

  # Smart card support.
  services.pcscd.enable = true;

  # For user SSH via Yubikey.
  services.yubikey-agent.enable = true;
}
