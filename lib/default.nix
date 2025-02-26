# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ defaultTags, edition, sources, lib, pkgs, ... }:
let
  inherit (lib) filterAttrs mapAttrs' hasSuffix removeSuffix nameValuePair optional concatStringsSep genList length mapAttrs concatMap mapAttrsToList;
  autoImport = inventoryFile: 
  let
    fnOrAttrs = import inventoryFile;
  in 
    assert builtins.isFunction fnOrAttrs || builtins.isAttrs fnOrAttrs;
    if builtins.isFunction fnOrAttrs then fnOrAttrs { inherit pkgs; } else fnOrAttrs;
in
rec {
  # This will build a Markdown table. 
  # Inputs:
  # [ [ col1 col2 … colN ] [ col1 … colN ] … ]
  # Outputs: a string which represents the table in Markdown.
  mkMarkdownTable = header: rows:
  let
    mkMarkdownTableLine = line:
    concatStringsSep "|" 
    ([ "" ] ++ line ++ [ "" ]);
    mkMarkdownTableLineSeparator = line:
    mkMarkdownTableLine (genList (_: "-") (length line));
  in
    concatStringsSep "\n" ([
      (mkMarkdownTableLine header)
      (mkMarkdownTableLineSeparator header)
    ] ++ map mkMarkdownTableLine rows);

  # This will build a network matrix table
  # Inputs:
  #   [ { cidr, from, to, protos } ]
  # Outputs:
  #  a string which represents the table in Markdown. 
  mkMarkdownNetworkMatrixTable = lines: 
    mkMarkdownTable 
    [ "Sous-réseau CIDR" "Port source" "Port destination" "Protocoles" ]
    (map ({ cidr, from, to, protos }: 
      [ cidr (toString from) (concatStringsSep ", " (map toString to)) (concatStringsSep "," protos) ]) lines);

  # This will read the user-specific inventory and return an attribute set of { $user = $module }
  # This can be used to further customize the final OS image.
  readInventory = dir: 
  let
    customizations = filterAttrs (name: type: type == "regular" && hasSuffix ".nix" name) (builtins.readDir dir);
  in 
    mapAttrs' (name: _: nameValuePair (removeSuffix ".nix" name) (autoImport "${dir}/${name}")) customizations;

  # This will build an ISO installer that will automatically partition the target system.
  # FIXME: 
  # - LUKS2 should probably get enrolled with the Yubikey as well (?).
  # - We should enroll a static set of PK/KEK which comes from the image.
  # - Secure Boot key should not be created on the disk. 
  #   - db signer should be pre-provisioned on the Yubikey and enrolled in the system.
  #   - sign the first generation with it.
  # - Upgrade process will need the Yubikey for signing.
  buildInstallerImage = mainDisk: modules: 
  let
    targetSystem = (pkgs.nixos modules);
    targetSystemFormatScript = targetSystem.config.system.build.formatScript;
    targetSystemMountScript = targetSystem.config.system.build.mountScript;
    targetSystemClosure = targetSystem.config.system.build.toplevel;
  in
  (pkgs.nixos [
    ({ config, modulesPath, ... }: {
      imports = [
        "${modulesPath}/installer/cd-dvd/installation-cd-base.nix"
      ];

      # Reset the original message.
      services.getty.helpLine = lib.mkForce ''
        This is the Securix live offline installer image edition ${edition}.

        This installer will install your system in ${mainDisk}, if that's not what you want,
        contact the system administrators.

        Run: `autoinstall-terminal` to start the automatic installation process.
      '';
      services.getty.autologinUser = lib.mkForce "root";

      networking.hostName = "m${toString targetSystem.config.securix.self.inventoryId}";
      boot.kernelParams = [ "console=ttyS0,115200" "console=tty0" ];
      system.nixos.distroId = "securix";
      system.nixos.tags = [ 
        # Taint with the inventory ID not to mis-install the wrong inventory image.
        "m${toString targetSystem.config.securix.self.inventoryId}" "installer"
      ] 
      ++ defaultTags 
      # Taint developer images.
      ++ optional targetSystem.config.securix.self.developer "developer";
      isoImage.storeContents = [
        targetSystemClosure
      ];

      time.timeZone = "Europe/Paris";
      console = {
        # Let the kernel be smart.
        font = null;
        keyMap = "fr";
      };

      environment.systemPackages = [
        (pkgs.writeShellScriptBin "autoinstall-terminal" ''
        #!/usr/bin/env bash

        log() {
          local level="$1"
          local msg="$2"
          case "$level" in
            info)
              ${pkgs.gum}/bin/gum log -t rfc822 -l info "$msg"
              ;;
            warn)
              ${pkgs.gum}/bin/gum log -t rfc822 -l warn "$msg"
              ;;
            error)
              ${pkgs.gum}/bin/gum log -t rfc822 -l error "$msg"
              ;;
            *)
              ${pkgs.gum}/bin/gum log -t rfc822 -l debug "$msg"
              ;;
          esac
        }

        log_info() {
          local msg="$1"
          log info "$msg"
        }

        log_warn() {
          local msg="$1"
          log warn "$msg"
        }

        log_error() {
          local msg="$1"
          log error "$msg"
          }

        box_message() {
          local msg="$1"
          ${pkgs.gum}/bin/gum style --border "rounded" --padding "1" --foreground "yellow" "$msg"
        }

        umount -R /mnt || true

        box_message "Welcome in the Securix automatic installer."
        log_info "Here is the list of current block devices."
        lsblk

        ${pkgs.systemd}/bin/udevadm settle
        log_info "${mainDisk} will be re-initialized and formatted, please confirm this is the right target."
        ${pkgs.gum}/bin/gum confirm "Proceed with reformatting?" || { log_warn "Operation cancelled."; exit 0; }

        wipefs -fa "${mainDisk}" ; sudo dd if=/dev/zero of="${mainDisk}" bs=4M count=1024;
        log_info "${mainDisk} re-initialized and formatted."

        ${pkgs.systemd}/bin/udevadm settle
        box_message "Repartitioning ${mainDisk}..."
        ${targetSystemFormatScript}
        box_message "Mounting ${mainDisk}..."
        ${targetSystemMountScript}
        box_message "Provisioning Secure Boot keys..."
        ${pkgs.sbctl}/bin/sbctl create-keys --database-path /mnt/etc/secureboot --export /mnt/etc/secureboot/keys
        box_message "Burning the image on ${mainDisk}..."
        ${config.system.build.nixos-install}/bin/nixos-install --no-channel-copy -j $(nproc) --option substituters "" --system "${targetSystemClosure}"
        box_message "Enrolling Secure Boot keys..."
        ${pkgs.nixos-enter}/bin/nixos-enter --command "sbctl enroll-keys"
        lsblk
        log_info "Installation is complete. You can now reboot in the installed system."
        '')
      ];
    })
  ]).config.system.build.isoImage;

  # Build the artifact images for the Securix OS for a given machine.
  mkTerminal = { name, userSpecificModule, vpnProfiles, extraOperators ? { }, modules, edition, mainDisk }:
  let
    allModules = [
      userSpecificModule 
      ../modules
      ../hardware
      # For Secure Boot.
      (import sources.lanzaboote).nixosModules.lanzaboote
      "${sources.agenix}/modules/age.nix"
      {
        securix.self.identifier = name;
        securix.self.edition = edition;
        _module.args.operators = mapAttrs' (fileName: cfg: nameValuePair cfg.securix.self.username cfg.securix.self) extraOperators;
        _module.args.vpnProfiles = vpnProfiles;

        age.identityPaths = [
          # FIXME: age ne sait pas encore utiliser le TPM2 pour déchiffrer des secrets
          # utiliser https://github.com/Foxboron/age-plugin-tpm dans le futur.
          "/etc/ssh/ssh_host_ed25519_key"
        ];

        # TODO: when we will have build capacity, we can re-enable it.
        # Otherwise, it's too expensive in rebuilds!
        documentation.man.man-db.enable = false;
      }
    ] ++ modules;
  in
  {
    installer = buildInstallerImage mainDisk allModules;
    system = pkgs.nixos allModules;
  };

  # Build all artifacts images for the Securix OS.
  mkTerminals = { users, vpn-profiles, edition, mainDisk }: baseSystem: 

  mapAttrs (name: userSpecificModule: mkTerminal {
    inherit name userSpecificModule edition mainDisk;
    # TODO: unify the naming for vpn-profiles...
    vpnProfiles = vpn-profiles;
    # All the users themselves.
    extraOperators = users;
    modules = [ baseSystem ];
  }) users;

  # Build all documentation outputs for the Securix OS.
  mkDocs = { users, vpn-profiles, terminals }: {
    bastions =
    let
      # TODO: move flow information inside the VPN profiles.
      mkAnySrcFlow = proto: ports: { from = "*"; to = ports; protos = [ proto ]; };
      defaultFlows = [
        (mkAnySrcFlow "tcp" [ 22 80 443 ])
      ];
      mkFlows = subnets: concatMap (cidr:
        map (flow: { inherit cidr; inherit (flow) from to protos; }) defaultFlows 
      ) subnets;
  in
      pkgs.writeText "bastions.md" ''
        # Documentation des flux

        ${concatStringsSep "\n\n" (map (vpn: ''
          # ${vpn}

          ${mkMarkdownNetworkMatrixTable (mkFlows vpn-profiles.${vpn}.remoteSubnets)}
        '') (builtins.attrNames vpn-profiles))}
      '';
    inventory =
    let
      configs = mapAttrs (username: { system, ... }: system.config) terminals;
      mkUserReport = user: config: ''
        ## Inventaire de `${user}`

        Email: ${config.securix.self.email}
        Machine: ${config.securix.self.hardwareSKU}
        Numéro: ${toString config.securix.self.inventoryId}
      '';
    in
    pkgs.writeText "inventory.md" ''
      # Inventaire des terminaux en circulation

      ${concatStringsSep "\n" (mapAttrsToList mkUserReport configs)}
    '';
  };
}
