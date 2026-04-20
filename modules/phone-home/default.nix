# SPDX-FileCopyrightText: 2026 Mihai Saveanu <darkangel@ladomotique.eu>
#
# SPDX-License-Identifier: MIT

# Phone Home module for Securix fleet management.
# At boot, auto-detects hardware, reads SSH public key,
# and announces to a central server for automated onboarding.
# Periodic heartbeat reports machine health.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.securix.phoneHome;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    mkDefault
    ;

  phoneHomeScript = pkgs.writeShellScript "securix-phone-home" ''
    set -euo pipefail

    SERVER_URL="${cfg.serverUrl}"
    MACHINE_ID="$(cat /etc/machine-id 2>/dev/null || echo unknown)"

    # Hardware detection from DMI/SMBIOS
    SERIAL="$(cat /sys/class/dmi/id/product_serial 2>/dev/null || echo unknown)"
    PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)"
    VENDOR="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo unknown)"
    BOARD="$(cat /sys/class/dmi/id/board_name 2>/dev/null || echo unknown)"
    BIOS_VERSION="$(cat /sys/class/dmi/id/bios_version 2>/dev/null || echo unknown)"

    # CPU
    CPU_MODEL="$(${pkgs.gnugrep}/bin/grep -m1 'model name' /proc/cpuinfo | ${pkgs.gnused}/bin/sed 's/.*: //' || echo unknown)"
    CPU_CORES="$(${pkgs.gnugrep}/bin/grep -c '^processor' /proc/cpuinfo || echo 0)"

    # RAM
    RAM_KB="$(${pkgs.gnugrep}/bin/grep MemTotal /proc/meminfo | ${pkgs.gawk}/bin/awk '{print $2}')"
    RAM_MB="$((RAM_KB / 1024))"

    # Disk
    DISK_INFO="$(${pkgs.util-linux}/bin/lsblk -J -b -o NAME,SIZE,TYPE,MODEL 2>/dev/null | ${pkgs.jq}/bin/jq -c '[.blockdevices[] | select(.type=="disk") | {name, size: (.size / 1073741824 | floor | tostring + "GB"), model}]' 2>/dev/null || echo '[]')"

    # Network interfaces
    NET_INFO="$(${pkgs.coreutils}/bin/ls /sys/class/net/ | ${pkgs.gnugrep}/bin/grep -v lo | while read iface; do
      mac="$(cat /sys/class/net/$iface/address 2>/dev/null || echo "")"
      printf '{"name":"%s","mac":"%s"},' "$iface" "$mac"
    done | ${pkgs.gnused}/bin/sed 's/,$//' | ${pkgs.gawk}/bin/awk '{print "["$0"]"}')"

    # SSH public key (TPM or standard)
    SSH_PUBKEY=""
    for keyfile in /etc/ssh/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_rsa_key.pub; do
      if [ -f "$keyfile" ]; then
        SSH_PUBKEY="$(cat "$keyfile")"
        break
      fi
    done

    # NixOS version
    NIXOS_VERSION="$(cat /etc/os-release 2>/dev/null | ${pkgs.gnugrep}/bin/grep VERSION_ID | ${pkgs.gnused}/bin/sed 's/VERSION_ID=//' | tr -d '"' || echo unknown)"

    # Hostname
    HOSTNAME="$(${pkgs.nettools}/bin/hostname 2>/dev/null || cat /proc/sys/kernel/hostname)"

    # Build payload
    PAYLOAD="$(${pkgs.jq}/bin/jq -n \
      --arg machine_id "$MACHINE_ID" \
      --arg serial "$SERIAL" \
      --arg product "$PRODUCT" \
      --arg vendor "$VENDOR" \
      --arg board "$BOARD" \
      --arg bios_version "$BIOS_VERSION" \
      --arg cpu_model "$CPU_MODEL" \
      --argjson cpu_cores "$CPU_CORES" \
      --argjson ram_mb "$RAM_MB" \
      --argjson disks "$DISK_INFO" \
      --argjson network "$NET_INFO" \
      --arg ssh_pubkey "$SSH_PUBKEY" \
      --arg nixos_version "$NIXOS_VERSION" \
      --arg hostname "$HOSTNAME" \
      --arg edition "${config.securix.self.edition}" \
      '{
        machine_id: $machine_id,
        serial: $serial,
        product: $product,
        vendor: $vendor,
        board: $board,
        bios_version: $bios_version,
        cpu_model: $cpu_model,
        cpu_cores: $cpu_cores,
        ram_mb: $ram_mb,
        disks: $disks,
        network: $network,
        ssh_pubkey: $ssh_pubkey,
        nixos_version: $nixos_version,
        hostname: $hostname,
        edition: $edition,
        event: "announce"
      }')"

    # Send announce with retries
    for i in 1 2 3 4 5; do
      if ${pkgs.curl}/bin/curl -sf -X POST "$SERVER_URL/api/phone-home/announce" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" --connect-timeout 5 --max-time 10; then
        echo "[phone-home] Announced OK to $SERVER_URL"
        exit 0
      fi
      echo "[phone-home] Retry $i..."
      sleep 5
    done

    echo "[phone-home] Failed to announce after 5 retries"
    exit 1
  '';

  heartbeatScript = pkgs.writeShellScript "securix-heartbeat" ''
    set -euo pipefail

    SERVER_URL="${cfg.serverUrl}"
    MACHINE_ID="$(cat /etc/machine-id 2>/dev/null || echo unknown)"

    # CPU usage from /proc/stat
    read_cpu() {
      ${pkgs.gawk}/bin/awk '/^cpu / {u=$2+$4; t=$2+$3+$4+$5+$6+$7+$8; print u, t}' /proc/stat
    }

    CPU1=($(read_cpu))
    sleep 1
    CPU2=($(read_cpu))
    CPU_PCT="$(echo "scale=1; (''${CPU2[0]}-''${CPU1[0]})*100/(''${CPU2[1]}-''${CPU1[1]})" | ${pkgs.bc}/bin/bc 2>/dev/null || echo -1)"

    # Memory
    MEM_TOTAL="$(${pkgs.gnugrep}/bin/grep MemTotal /proc/meminfo | ${pkgs.gawk}/bin/awk '{print $2}')"
    MEM_AVAIL="$(${pkgs.gnugrep}/bin/grep MemAvailable /proc/meminfo | ${pkgs.gawk}/bin/awk '{print $2}')"
    MEM_PCT="$(echo "scale=1; ($MEM_TOTAL-$MEM_AVAIL)*100/$MEM_TOTAL" | ${pkgs.bc}/bin/bc 2>/dev/null || echo -1)"

    # Disk usage root
    DISK_PCT="$(${pkgs.coreutils}/bin/df / | ${pkgs.gawk}/bin/awk 'NR==2 {gsub(/%/,""); print $5}')"

    # Uptime
    UPTIME_S="$(${pkgs.coreutils}/bin/cut -d. -f1 /proc/uptime)"

    PAYLOAD="$(${pkgs.jq}/bin/jq -n \
      --arg machine_id "$MACHINE_ID" \
      --argjson cpu_pct "''${CPU_PCT:--1}" \
      --argjson mem_pct "''${MEM_PCT:--1}" \
      --argjson disk_pct "''${DISK_PCT:-0}" \
      --argjson uptime_s "''${UPTIME_S:-0}" \
      '{
        machine_id: $machine_id,
        cpu_pct: $cpu_pct,
        mem_pct: $mem_pct,
        disk_pct: $disk_pct,
        uptime_s: $uptime_s,
        event: "heartbeat"
      }')"

    ${pkgs.curl}/bin/curl -sf -X POST "$SERVER_URL/api/phone-home/heartbeat" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" --connect-timeout 5 --max-time 10 || true
  '';

in
{
  options.securix.phoneHome = {
    enable = mkEnableOption "phone-home: auto-announce and fleet heartbeat to central server";

    serverUrl = mkOption {
      type = types.str;
      description = "URL du serveur central de gestion de flotte";
      example = "https://fleet.example.com";
    };

    heartbeatInterval = mkOption {
      type = types.int;
      default = 300;
      description = "Intervalle en secondes entre les heartbeats (défaut: 5 minutes)";
      example = 60;
    };
  };

  config = mkIf cfg.enable {
    # Announce at boot after network is up
    systemd.services.securix-phone-home = {
      description = "Sécurix Phone Home — announce to fleet server";
      after = [
        "network-online.target"
        "sshd.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = phoneHomeScript;
        StandardOutput = "journal";
      };
    };

    # Periodic heartbeat
    systemd.services.securix-heartbeat = {
      description = "Sécurix Heartbeat — periodic health report";
      after = [ "securix-phone-home.service" ];
      wants = [ "securix-phone-home.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10";
        ExecStart = "${pkgs.bash}/bin/bash -c 'while true; do ${heartbeatScript}; sleep ${toString cfg.heartbeatInterval}; done'";
        StandardOutput = "journal";
      };
    };

    # Ensure required packages are available
    environment.systemPackages = with pkgs; [
      curl
      jq
      util-linux
    ];
  };
}
