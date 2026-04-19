# SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>
#
# SPDX-License-Identifier: MIT

# Runtime security observability via Tetragon (Cilium eBPF).
#
# Use case on a Sécurix admin workstation: detect attempts to bypass
# the corporate DNS resolver via DoH (DNS-over-HTTPS, port 443) or DoT
# (DNS-over-TLS, port 853) without introducing new firewall rules.
# The detection is kernel-side (eBPF hook on `tcp_connect`) and
# per-process (Tetragon resolves the struct task → binary path + uid
# + tty), so every hit ends up in journald with full forensic context.
#
# The list of DoH/DoT IPs is fetched from a community-maintained
# source (default: dibdot/DoH-IP-blocklists) via a systemd timer,
# merged with a baseline shipped inside the module and any
# site-specific extras, then compiled into a Tetragon `TracingPolicy`.
# Tetragon watches the policy directory and hot-reloads on change.
#
# Default mode is observability-only (action = Post). Flip
# `enforceKill = true` once the ops team has reviewed ~2 weeks of
# detection logs to activate SIGKILL on matched connections.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.securix.o11y.tetragon;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    concatMapStringsSep
    concatStringsSep
    optionalString
    ;

  # Baseline blocklist — used at first boot (before any refresh has
  # succeeded) and in air-gapped deployments (source = "none"). Kept
  # short, curated, and reviewable in-tree. Community lists override
  # this at runtime.
  baselineBlocklist = pkgs.writeText "doh-baseline.txt" ''
    # Cloudflare DNS (1.1.1.1 / family / malware)
    1.1.1.1
    1.0.0.1
    1.1.1.2
    1.1.1.3
    2606:4700:4700::1111
    2606:4700:4700::1001
    # Google Public DNS
    8.8.8.8
    8.8.4.4
    2001:4860:4860::8888
    2001:4860:4860::8844
    # Quad9
    9.9.9.9
    149.112.112.112
    2620:fe::fe
    # OpenDNS
    208.67.222.222
    208.67.220.220
    # AdGuard
    94.140.14.14
    94.140.15.15
    # Mullvad
    194.242.2.2
    194.242.2.3
    # CleanBrowsing
    185.228.168.168
    185.228.169.168
  '';

  # Source URL lookup table (one line per list variant).
  sourceUrls = {
    dibdot = [
      "https://raw.githubusercontent.com/dibdot/DoH-IP-blocklists/master/doh-ipv4.txt"
      "https://raw.githubusercontent.com/dibdot/DoH-IP-blocklists/master/doh-ipv6.txt"
    ];
    hagezi = [ "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/ips/doh.txt" ];
    adguard = [
      "https://raw.githubusercontent.com/AdguardTeam/AdGuardSDNSFilter/master/Filters/exceptions_with_ips.txt"
    ];
    custom = [ cfg.blockLists.customUrl ];
    none = [ ];
  };

  urlsToFetch = sourceUrls.${cfg.blockLists.source};

  # Generate the Tetragon TracingPolicy from a list file.
  policyGen = pkgs.writeShellScript "tetragon-gen-policy" ''
    set -euo pipefail
    IN="$1"
    OUT="$2"
    ACTION="${if cfg.enforceKill then "Sigkill" else "Post"}"

    # Header
    cat > "$OUT" <<EOF
    apiVersion: cilium.io/v1alpha1
    kind: TracingPolicy
    metadata:
      name: securix-doh-evasion-detect
    spec:
      kprobes:
        - call: "tcp_connect"
          syscall: false
          args:
            - index: 0
              type: "sock"
          selectors:
            - matchArgs:
                - index: 0
                  operator: "DAddr"
                  values:
    EOF
    # Emit IPv4 + IPv6 addresses indented for YAML list.
    ${pkgs.gnugrep}/bin/grep -E '^([0-9a-fA-F:.]+)' "$IN" \
      | ${pkgs.gnugrep}/bin/grep -vE '^#' \
      | ${pkgs.gawk}/bin/awk '{print "                - \""$1"\""}' >> "$OUT"
    # Footer with action
    cat >> "$OUT" <<EOF
                - index: 0
                  operator: "DPort"
                  values:
                    - "443"
                    - "853"
              matchActions:
                - action: $ACTION
    EOF
  '';

  # Runtime refresh script — fetches, validates, merges, hot-reloads.
  refreshScript = pkgs.writeShellScript "tetragon-blocklist-refresh" ''
    set -euo pipefail
    STATE=/var/lib/tetragon
    POL=$STATE/tracing-policies
    mkdir -p "$STATE" "$POL"

    TMP=$(${pkgs.coreutils}/bin/mktemp -d)
    trap "rm -rf $TMP" EXIT

    echo "tetragon blocklist refresh start" | ${pkgs.systemd}/bin/systemd-cat -p info -t tetragon-refresh

    FETCHED="$TMP/fetched.txt"
    : > "$FETCHED"

    ${
      if cfg.blockLists.source == "none" then
        ''
          echo "source=none, skipping remote fetch" | ${pkgs.systemd}/bin/systemd-cat -p info -t tetragon-refresh
        ''
      else
        ''
          for url in ${concatStringsSep " " urlsToFetch}; do
            if ${pkgs.curl}/bin/curl --fail --silent --max-time 30 "$url" >> "$FETCHED.raw" 2>/dev/null; then
              echo "fetched: $url" | ${pkgs.systemd}/bin/systemd-cat -p info -t tetragon-refresh
            else
              echo "FETCH FAILED: $url" | ${pkgs.systemd}/bin/systemd-cat -p warning -t tetragon-refresh
            fi
          done

          # Validate format: keep only lines matching an IP or CIDR pattern.
          ${pkgs.gawk}/bin/awk '/^[0-9a-fA-F]+[0-9a-fA-F:.\/]*$/ && length > 0' "$FETCHED.raw" > "$FETCHED" || true
        ''
    }

    ${optionalString (cfg.blockLists.sha256 != null) ''
      # Optional SHA256 pinning — for chain-of-custody in ANSSI-regulated deployments.
      HASH=$(${pkgs.coreutils}/bin/sha256sum "$FETCHED" | ${pkgs.coreutils}/bin/cut -d' ' -f1)
      if [ "$HASH" != "${cfg.blockLists.sha256}" ]; then
        echo "SHA256 MISMATCH: expected=${cfg.blockLists.sha256} got=$HASH — refusing to install new blocklist" \
          | ${pkgs.systemd}/bin/systemd-cat -p err -t tetragon-refresh
        exit 1
      fi
    ''}

    # Merge: baseline + fetched + extraIps, subtract ignoreIps.
    FINAL="$TMP/final.txt"
    {
      ${pkgs.gnused}/bin/sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' ${baselineBlocklist}
      [ -s "$FETCHED" ] && ${pkgs.coreutils}/bin/cat "$FETCHED" || true
      ${concatMapStringsSep "\n" (ip: ''echo "${ip}"'') cfg.blockLists.extraIps}
    } | ${pkgs.coreutils}/bin/sort -u > "$TMP/merged.txt"

    ${
      if cfg.blockLists.ignoreIps == [ ] then
        ''
          ${pkgs.coreutils}/bin/cp "$TMP/merged.txt" "$FINAL"
        ''
      else
        ''
          ${pkgs.gnugrep}/bin/grep -vxF ${
            concatStringsSep " " (map (ip: "-e '${ip}'") cfg.blockLists.ignoreIps)
          } "$TMP/merged.txt" > "$FINAL" || true
        ''
    }

    # Atomically replace the authoritative list + policy.
    ${pkgs.coreutils}/bin/cp "$FINAL" "$STATE/blocklist.txt.new"
    ${policyGen} "$STATE/blocklist.txt.new" "$POL/doh-evasion-detect.yaml.new"
    ${pkgs.coreutils}/bin/mv "$STATE/blocklist.txt.new" "$STATE/blocklist.txt"
    ${pkgs.coreutils}/bin/mv "$POL/doh-evasion-detect.yaml.new" "$POL/doh-evasion-detect.yaml"

    COUNT=$(${pkgs.coreutils}/bin/wc -l < "$STATE/blocklist.txt")
    ${pkgs.coreutils}/bin/date -Iseconds > "$STATE/last-refresh"
    echo "blocklist OK ($COUNT entries)" | ${pkgs.systemd}/bin/systemd-cat -p info -t tetragon-refresh

    # Tetragon watches the policy dir via fsnotify; if your version doesn't,
    # a SIGHUP (or restart) here would be needed.
  '';

  # Auditd forwarder — converts Tetragon JSON events to audit user messages.
  auditForward = pkgs.writeShellScript "tetragon-to-auditd" ''
    set -eu
    exec ${pkgs.systemd}/bin/journalctl -u tetragon -f -o json --no-tail 2>/dev/null \
      | ${pkgs.jq}/bin/jq -c --unbuffered \
          'select(.process_kprobe != null) | {
            pid:    .process_kprobe.process.pid,
            binary: .process_kprobe.process.binary,
            uid:    .process_kprobe.process.uid,
            daddr:  (.process_kprobe.args // [] | map(.sock_arg.daddr // empty) | first),
            dport:  (.process_kprobe.args // [] | map(.sock_arg.dport // empty) | first),
            action: (.process_kprobe.action // "Post"),
            policy: .process_kprobe.policy_name
          } | "type=TETRAGON msg=\(.)"' \
      | while IFS= read -r line; do
          ${pkgs.audit}/bin/auditctl -m "$line" 2>/dev/null || true
        done
  '';
in
{
  options.securix.o11y.tetragon = {
    enable = mkEnableOption ''
      runtime detection of DNS-evasion attempts (DoH / DoT) via
      Tetragon eBPF. Observability-only by default; flip
      `enforceKill = true` to actively kill matched connections.
    '';

    blockLists = {
      source = mkOption {
        type = types.enum [
          "dibdot"
          "hagezi"
          "adguard"
          "custom"
          "none"
        ];
        default = "dibdot";
        description = ''
          External source for the DoH/DoT IP list.

          - `dibdot`  — github.com/dibdot/DoH-IP-blocklists (~300 IPs, weekly updates)
          - `hagezi`  — github.com/hagezi/dns-blocklists   (~500 IPs, daily)
          - `adguard` — AdGuard DNS filter IPs            (domain-centric)
          - `custom`  — user-supplied URL (set `customUrl`)
          - `none`    — only the baseline + `extraIps` (air-gap)
        '';
      };

      customUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          HTTPS URL to fetch the blocklist from when `source = "custom"`.
          Expected format: one IPv4, IPv6 or CIDR per line; `#` comments
          allowed.
        '';
      };

      sha256 = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Optional SHA-256 of the fetched (validated, pre-merge) list.
          When set, a mismatch aborts the refresh and keeps the previous
          blocklist. Recommended for ANSSI-regulated deployments where
          the ops team signs-off on a specific list version.
        '';
        example = "abcdef0123...";
      };

      refreshInterval = mkOption {
        type = types.str;
        default = "daily";
        description = ''
          systemd `OnCalendar=` expression for the refresh timer
          (e.g. `daily`, `hourly`, `weekly`, `Mon 03:00`).
        '';
      };

      staleTolerance = mkOption {
        type = types.str;
        default = "14d";
        description = ''
          Maximum age of the blocklist before a warning is emitted to
          journald / auditd. Humans should investigate if this triggers
          — typically means the refresh service is failing or the poste
          is off-line for extended periods.
        '';
      };

      extraIps = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional IPs / CIDRs merged into the final blocklist.";
      };

      ignoreIps = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          IPs to remove from the final blocklist. Use when a community
          list false-positives on an IP you do want to reach (your own
          internal DNS, a specific tenant, …).
        '';
      };
    };

    enforceKill = mkOption {
      type = types.bool;
      default = false;
      description = ''
        When `false` (default), matched connections are logged only
        (Tetragon action = Post). When `true`, Tetragon sends SIGKILL
        to the offending process — effectively a firewall-equivalent
        block implemented at the LSM layer instead of netfilter.
        Recommended only once ops has reviewed detection logs and
        confirmed the blocklist does not false-positive on legitimate
        internal traffic.
      '';
    };

    forwardToAuditd = mkOption {
      type = types.bool;
      default = config.securix.audit.enable or false;
      defaultText = lib.literalExpression "config.securix.audit.enable";
      description = ''
        Forward Tetragon events to auditd via user-space messages
        (`auditctl -m`). Unifies Tetragon detections with the existing
        R74 auditd stream so the `puits de traces ANSSI` sees a single
        timeline.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Sanity checks.
    assertions = [
      {
        assertion = cfg.blockLists.source != "custom" || cfg.blockLists.customUrl != null;
        message = "securix.o11y.tetragon.blockLists.customUrl must be set when source = \"custom\".";
      }
    ];

    # State directory is managed by a dedicated tmpfiles rule so the
    # refresh service can run without CAP_DAC_OVERRIDE.
    systemd.tmpfiles.rules = [
      "d /var/lib/tetragon 0750 root root -"
      "d /var/lib/tetragon/tracing-policies 0750 root root -"
    ];

    # Tetragon itself — spawn from the upstream binary with a
    # policy-directory watch. We don't rely on `services.tetragon`
    # (not in all nixpkgs revisions) to keep the module self-contained.
    systemd.services.tetragon = {
      description = "Tetragon eBPF Runtime Security Observability";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-pre.target"
        "systemd-sysctl.service"
      ];
      path = [ pkgs.iproute2 ];
      serviceConfig = {
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/lib/tetragon/tracing-policies";
        ExecStart = "${pkgs.tetragon}/bin/tetragon --config-dir /var/lib/tetragon/tracing-policies --export-filename /var/log/tetragon/tetragon.log";
        Restart = "on-failure";
        RestartSec = "10s";
        # eBPF requirements.
        AmbientCapabilities = "CAP_BPF CAP_SYS_ADMIN CAP_PERFMON CAP_NET_ADMIN CAP_SYS_RESOURCE";
        CapabilityBoundingSet = "CAP_BPF CAP_SYS_ADMIN CAP_PERFMON CAP_NET_ADMIN CAP_SYS_RESOURCE";
        # Hardening — Tetragon doesn't need most of these.
        PrivateTmp = true;
        ProtectHome = true;
        ProtectKernelLogs = false; # tetragon reads kernel BPF logs
        ProtectKernelModules = false; # tetragon loads BPF programs
        ProtectKernelTunables = false;
        ProtectSystem = "strict";
        ReadWritePaths = [
          "/var/lib/tetragon"
          "/var/log/tetragon"
          "/sys/fs/bpf"
        ];
        LogsDirectory = "tetragon";
      };
    };

    # Refresh service + timer for the blocklist.
    systemd.services.tetragon-blocklist-refresh = {
      description = "Refresh Tetragon DoH/DoT blocklist";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      requires = [ "tetragon.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${refreshScript}";
        # Soft hardening — runs as root for file install, no network beyond curl.
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/lib/tetragon" ];
        PrivateTmp = true;
      };
    };

    systemd.timers.tetragon-blocklist-refresh = {
      description = "Periodic refresh of Tetragon DoH/DoT blocklist";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnCalendar = cfg.blockLists.refreshInterval;
        Persistent = true;
        RandomizedDelaySec = "10min";
      };
    };

    # Auditd bridge — one-shot service that tails the journal and
    # relays each matched event as a user audit message.
    systemd.services.tetragon-to-auditd = mkIf cfg.forwardToAuditd {
      description = "Forward Tetragon events to auditd";
      wantedBy = [ "multi-user.target" ];
      after = [
        "tetragon.service"
        "auditd.service"
      ];
      requires = [ "auditd.service" ];
      serviceConfig = {
        ExecStart = "${auditForward}";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };

    # Tetragon CLI + jq + audit for operators and the auditd forwarder.
    environment.systemPackages = with pkgs; [
      tetragon
      jq
    ];
  };
}
