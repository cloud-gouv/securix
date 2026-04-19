# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

# We mostly use Yubikeys.
{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.yubikey-personalization
    pkgs.yubikey-manager
    # Ships `pamu2fcfg` so operators can enrol their FIDO2 key on
    # the workstation without an ad-hoc `nix-shell -p pam_u2f`.
    # See `docs/manual/src/user/enroll-security-key.md`.
    pkgs.pam_u2f
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
