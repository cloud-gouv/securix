# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  defaultTags,
  edition,
  sources,
  lib,
  pkgs,
  ...
}@args:
let
  inherit (lib)
    filterAttrs
    mapAttrs'
    hasSuffix
    removeSuffix
    nameValuePair
    optional
    concatStringsSep
    genList
    length
    mapAttrs
    concatMap
    mapAttrsToList
    optionalAttrs
    ;
  autoImport =
    inventoryFile:
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
  mkMarkdownTable =
    header: rows:
    let
      mkMarkdownTableLine = line: concatStringsSep "|" ([ "" ] ++ line ++ [ "" ]);
      mkMarkdownTableLineSeparator = line: mkMarkdownTableLine (genList (_: "-") (length line));
    in
    concatStringsSep "\n" (
      [
        (mkMarkdownTableLine header)
        (mkMarkdownTableLineSeparator header)
      ]
      ++ map mkMarkdownTableLine rows
    );

  # This will build a network matrix table
  # Inputs:
  #   [ { cidr, from, to, protos } ]
  # Outputs:
  #  a string which represents the table in Markdown.
  mkMarkdownNetworkMatrixTable =
    lines:
    mkMarkdownTable [ "Sous-réseau CIDR" "Port source" "Port destination" "Protocoles" ] (
      map (
        {
          cidr,
          from,
          to,
          protos,
        }:
        [
          cidr
          (toString from)
          (concatStringsSep ", " (map toString to))
          (concatStringsSep "," protos)
        ]
      ) lines
    );

  # This will read the user-specific inventory and return an attribute set of { $user = $module }
  # This can be used to further customize the final OS image.
  readInventory =
    dir:
    let
      customizations = filterAttrs (name: type: type == "regular" && hasSuffix ".nix" name) (
        builtins.readDir dir
      );
    in
    mapAttrs' (
      name: _: nameValuePair (removeSuffix ".nix" name) (autoImport "${dir}/${name}")
    ) customizations;

  # This will read the 2nd generation of inventory for Bureautix based systems.
  # A 2nd generation inventory contains:
  # - machines/ directory with ideally a serial-number like identifier as a filename dot nix, e.g. `000000000.nix`
  # - users/ directory with all users specific configuration.
  # The reader will look for each machines, find all users relevant to return.
  # Expected return: { <serial number>.userModules.<user module name> = { }; ... }
  # You can take this output and build all terminals with it.
  readInventory2 =
    # `layout` is for reserved for future improvements of the inventory system.
    {
      dir,
      layout ? "v1",
    }:
    let
      readFilesFromSubDir =
        subdir:
        filterAttrs (name: type: type == "regular" && hasSuffix ".nix" name) (
          builtins.readDir "${dir}/${subdir}"
        );
      machines = readFilesFromSubDir "machines";
    in
    mapAttrs' (
      name: _:
      nameValuePair (removeSuffix ".nix" name) rec {
        machineModule = autoImport "${dir}/machines/${name}";
        # NOTE: this is an abuse of the module system, we should not perform a direct access here...
        # We should rather aim to make the machine module autonomous and perform an evaluation at the right moment.
        userModules = map (
          username:
          if !builtins.pathExists "${dir}/users/${username}.nix" then
            throw "User '${username}' does not exist in the inventory but is referenced by machine '${name}'!"
          else
            autoImport "${dir}/users/${username}.nix"
        ) machineModule.securix.self.machine.users;
      }
    ) machines;

  # This will build an ISO installer that will automatically partition the target system.
  # FIXME:
  # - LUKS2 should probably get enrolled with the Yubikey as well (?).
  # - We should enroll a static set of PK/KEK which comes from the image.
  # - Secure Boot key should not be created on the disk.
  #   - db signer should be pre-provisioned on the Yubikey and enrolled in the system.
  #   - sign the first generation with it.
  # - Upgrade process will need the Yubikey for signing.
  buildInstallerSystem =
    # Put `compression` to `null` to disable it.
    {
      targetSystem,
      extraInstallerModules ? [ ],
      consoleKeymap ? "fr",
      # Takes precedence over the default install script.
      installScript ? null,
    }:
    let
      targetSystemFormatScript = targetSystem.config.system.build.formatScript;
      targetSystemMountScript = targetSystem.config.system.build.mountScript;
      targetSystemClosure = targetSystem.config.system.build.toplevel;
      mainDisk = targetSystem.config.securix.self.mainDisk;

      # These are the scripts fragments that depends on whether we are a generic installer or not.
      diskProcedureScript = ''
        box_message "Repartitioning ${mainDisk}..."
        ${targetSystemFormatScript}
        box_message "Mounting ${mainDisk}..."
        ${targetSystemMountScript}
      '';
      installProcedureScript =
        config:
        if installScript != null then
          installScript
        else
          ''
            ${config.system.build.nixos-install}/bin/nixos-install --no-channel-copy -j $(nproc) --option substituters "" --system "${targetSystemClosure}"
          '';
    in
    pkgs.nixos (
      extraInstallerModules
      ++ [
        (
          {
            pkgs,
            config,
            lib,
            ...
          }:
          {
            networking.hostName = lib.mkDefault "generic-installer";
            # Reset the original message.
            services.getty.helpLine = lib.mkForce ''
              This is the Securix live offline installer image edition ${edition}.

              This installer will install your system in ${mainDisk}, if that's not what you want,
              contact the system administrators.

              Run: `autoinstall-terminal` to start the automatic installation process.
            '';
            services.getty.autologinUser = lib.mkForce "root";

            boot.kernelParams = [
              "console=ttyS0,115200"
              "console=tty0"
            ];
            system.nixos.distroId = lib.mkDefault "securix";
            system.nixos.tags = [ "installer" ] ++ defaultTags;

            time.timeZone = "Europe/Paris";
            console = {
              # Let the kernel be smart.
              font = null;
              keyMap = consoleKeymap;
            };

            environment.systemPackages = [
              (pkgs.writeShellScriptBin "autoinstall-terminal" (
                ''
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
                  ${diskProcedureScript}
                  box_message "Provisioning Secure Boot keys..."
                ''
                + (
                  if lib.versionOlder pkgs.sbctl.version "0.15" then
                    ''
                      ${pkgs.sbctl}/bin/sbctl create-keys --database-path /mnt/etc/secureboot --export /mnt/etc/secureboot/keys
                    ''
                  else
                    ''
                      ${pkgs.sbctl}/bin/sbctl create-keys --database-path /mnt/etc/secureboot/GUID --export /mnt/etc/secureboot/keys --disable-landlock
                    ''
                )
                + ''
                  box_message "Burning the image on ${mainDisk}..."
                  ${installProcedureScript config}
                  box_message "Enrolling Secure Boot keys..."
                  ${pkgs.nixos-enter}/bin/nixos-enter --command "sbctl enroll-keys"
                  lsblk
                  log_info "Installation is complete. You can now reboot in the installed system."
                ''
              ))
            ];
          }
        )
      ]
    );

  # This produces directly an ISO to flash on a USB/CD/DVD to install further the system.
  buildUSBInstaller =
    {
      modules,
      extraInstallerModules ? [ ],
      consoleKeymap ? "fr",
      installScript ? null,
      compression ? "zstd -Xcompression-level 6",
    }@args:
    let
      targetSystem = pkgs.nixos modules;
      targetSystemClosure = targetSystem.config.system.build.toplevel;
    in
    buildInstallerSystem (
      (removeAttrs args [
        "modules"
        "compression"
      ])
      // {
        inherit targetSystem;
        extraInstallerModules = extraInstallerModules ++ [
          (
            { lib, modulesPath, ... }:
            {
              imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-base.nix" ];
              # This is an intermediate priority override, normal override is 100, mkDefault is 1000. We take the middle here.
              networking.hostName = lib.mkOverride 500 "m${toString targetSystem.config.securix.self.inventoryId}";
              system.nixos.tags =
                [ "m${toString targetSystem.config.securix.self.inventoryId}" ]
                # Taint developer images.
                ++ optional targetSystem.config.securix.self.developer "developer";

              isoImage.storeContents = [ targetSystemClosure ];
              isoImage.squashfsCompression = compression;
            }
          )
        ];
      }
    );
  buildUSBInstallerISO = args: (buildUSBInstaller args).config.system.build.isoImage;
  # Deprecated alias
  buildInstallerImage = lib.warn "`buildInstallerImage` is deprecated, prefer `buildUSBInstallerISO` to it." buildUSBInstallerISO;

  # This produces directly a system toplevel which will contain netboot information (iPXE script)
  # that you can use to network boot the installer.
  buildNetbootInstaller =
    {
      extraInstallerModules ? [ ],
      consoleKeymap ? "fr",
      baseModules,
      installScript,
    }@args:
    buildInstallerSystem (
      (removeAttrs args [ "baseModules" ])
      // {
        targetSystem = pkgs.nixos baseModules;
        extraInstallerModules = extraInstallerModules ++ [
          {
            boot.loader.grub.enable = false;
            boot.initrd.availableKernelModules = [ "cdc_ncm" ];
            system.nixos.tags = [ "netinstaller" ];
          }
        ];
      }
    );

  # Build the artifact images for the Securix OS for a given machine.
  mkTerminal =
    {
      name,
      userSpecificModule,
      vpnProfiles,
      extraOperators ? { },
      modules,
      edition ? args.edition,
      compression ? "zstd -Xcompression-level 6",
    }:
    let
      allModules = [
        userSpecificModule
        ../modules
        ../hardware
        # For Secure Boot.
        (import sources.lanzaboote).nixosModules.lanzaboote
        "${sources.disko}/module.nix"
        "${sources.agenix}/modules/age.nix"
        {
          securix.self.machine.identifier = name;
          securix.self.edition = edition;
          _module.args.operators = mapAttrs' (
            fileName: cfg: nameValuePair cfg.securix.self.username cfg.securix.self
          ) extraOperators;
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
      modules = allModules;
      partitioningModules = [
        "${sources.disko}/module.nix"
        ../modules/filesystems
        ../modules/self.nix
      ];
      installer = buildUSBInstallerISO {
        modules = allModules;
        inherit compression;
      };
      system = pkgs.nixos allModules;
    };

  # Build all artifacts images for the Securix OS.
  mkTerminals =
    {
      users,
      vpn-profiles,
      edition,
      compression ? "zstd -Xcompression-level 6",
    }:
    baseSystem:

    mapAttrs (
      name: userSpecificModule:
      mkTerminal {
        inherit
          name
          userSpecificModule
          edition
          compression
          ;
        # TODO: unify the naming for vpn-profiles...
        vpnProfiles = vpn-profiles;
        # All the users themselves.
        extraOperators = users;
        modules = [ baseSystem ];
      }
    ) users;

  # Build all documentation outputs for the Securix OS.
  mkDocs =
    {
      users,
      vpn-profiles,
      terminals,
    }:
    {
      bastions =
        let
          # TODO: move flow information inside the VPN profiles.
          mkAnySrcFlow = proto: ports: {
            from = "*";
            to = ports;
            protos = [ proto ];
          };
          defaultFlows = [
            (mkAnySrcFlow "tcp" [
              22
              80
              443
            ])
          ];
          mkFlows =
            subnets:
            concatMap (
              cidr:
              map (flow: {
                inherit cidr;
                inherit (flow) from to protos;
              }) defaultFlows
            ) subnets;
        in
        pkgs.writeText "bastions.md" ''
          # Documentation des flux

          ${concatStringsSep "\n\n" (
            map (vpn: ''
              # ${vpn}

              ${mkMarkdownNetworkMatrixTable (mkFlows vpn-profiles.${vpn}.remoteSubnets)}
            '') (builtins.attrNames vpn-profiles)
          )}
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
