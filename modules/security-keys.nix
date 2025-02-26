# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

# We mostly use Yubikeys.
{ pkgs, ... }: {
  environment.systemPackages = [ pkgs.yubikey-personalization pkgs.yubikey-manager ];
  services.udev.packages = [ pkgs.yubikey-personalization pkgs.yubikey-manager ];

  # GPG support.
  # TODO: we don't have a need for GPG keys yet.
  programs.gnupg.agent.enable = false;

  # Smart card support.
  services.pcscd.enable = true;

  # Lock all sessions if a Yubikey is unplugged.
  services.udev.extraRules = ''
      ACTION=="remove",\
       ENV{ID_BUS}=="usb",\
       ENV{ID_MODEL_ID}=="0407",\
       ENV{ID_VENDOR_ID}=="1050",\
       ENV{ID_VENDOR}=="Yubico",\
       RUN+="${pkgs.systemd}/bin/loginctl lock-sessions"
  '';

  # For user SSH via Yubikey.
  services.yubikey-agent.enable = true;
}
