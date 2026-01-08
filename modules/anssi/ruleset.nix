{ lib, ... }:
let
  loadRules = files:
    lib.mergeAttrsList (map (file: import file) files);
in
loadRules [
  ./preboot.nix
  ./kernel-options.nix
  # ./kernel.nix
  # ./vfs.nix
  # ./users.nix
  # ./apparmor.nix
  # ./selinux.nix
  # ./journaling.nix
  # ./runtime-minimization.nix
  # ./hardening.nix
  # ./nss-hardening.nix
  # ./integrity.nix
  # ./mta.nix
]
