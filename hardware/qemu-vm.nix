# SPDX-FileCopyrightText: 2026 darkone@darkone.yt
#
# SPDX-License-Identifier: MIT

# Configuration minimale pour VM QEMU/KVM

{ lib, pkgs, ... }:
{
  # Kernel d'usage général, pas de durcissement spécifique au matériel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Pilotes virtio pour disques et réseau
  boot.initrd.kernelModules = [
    "virtio"
    "virtio_pci"
    "virtio_blk"
    "virtio_net"
  ];

  # Pas de microcode AMD/Intel nécessaire
  hardware.cpu.amd.updateMicrocode = false;
  hardware.cpu.intel.updateMicrocode = false;

  # Pas de firmware supplémentaire pour VM
  hardware.firmware = lib.mkForce [ ];

  # Support de base pour l'interface graphique QEMU
  services.xserver.videoDrivers = [
    "virtio"
    "fbdev"
  ];

  # Optimisations VM
  services.qemuGuest.enable = true;

  # Pas de TPM2 émulé par défaut (TODO)
  security.tpm2.enable = lib.mkForce false;

  # Pas d'agent SSH TPM pour la VM (TODO)
  securix.ssh.tpm-agent.hostKeys = lib.mkForce false;
  securix.ssh.tpm-agent.sshKeys = lib.mkForce false;
}
