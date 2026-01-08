# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

let
  mkSysctlChecker =
    lib: attrs:
    let
      mkCheckSingularSysctl = attr: expectedValue: ''
        # Check for sysctl '${attr}'
        actual_value=$(sysctl -n "${attr}")
        if [[ "$actual_value" -ne "${toString expectedValue}" ]]; then
          echo "Check failed for ${attr}: expected ${toString expectedValue}, got $actual_value"
          exit 1
        else
          echo "Check passed for ${attr}"
        fi
      '';
    in
    ''
      ${lib.concatStringsSep "\n" (
        map (name: mkCheckSingularSysctl name attrs.${name}) (lib.attrNames attrs)
      )}
    '';
in
{
  R8 = {
    name = "R8_MemoryBootOptions";
    anssiRef = "R8 – Paramétrer les options de configuration de la mémoire";
    description = "Set memory options at boot";
    severity = "intermediary";
    category = "base";

    config = _: {
      boot.kernelParams = [
        "l1tf=full,force" # Enable full mitigation for L1 Terminal Fault (L1TF), including disabling SMT
        "page_poison=on" # Enable poisoning of freed pages to detect leaks
        "pti=on" # Force use of Page Table Isolation (PTI) for Meltdown vulnerability
        "slab_nomerge=yes" # Disable slab cache merging to complicate heap overflow attacks
        "slub_debug=FZP" # Enable slab cache debugging with specific tests
        "spec_store_bypass_disable=seccomp" # Use seccomp mitigation for Spectre v4
        "spectre_v2=on" # Force Spectre v2 mitigation
        "mds=full,nosmt" # Enable full mitigation for MDS and disable SMT (requires microcode update)
        "mce=0" # Force kernel panic on uncorrected Machine Check exceptions
        "page_alloc.shuffle=1" # Enable page allocator randomization
        "rng_core.default_quality=500" # Set HWRNG quality for TPM-based CSPRNG initialization
      ];
    };

    checkScript =
      pkgs:
      pkgs.writeShellScript "check-R8" ''
        # The kernel boot parameters we expect to check
        EXPECTED_PARAMS=(
          "l1tf=full,force"
          "page_poison=on"
          "pti=on"
          "slab_nomerge=yes"
          "slub_debug=FZP"
          "spec_store_bypass_disable=seccomp"
          "spectre_v2=on"
          "mds=full,nosmt"
          "mce=0"
          "page_alloc.shuffle=1"
          "rng_core.default_quality=500"
        )

        # Get the current kernel parameters from /proc/cmdline
        ACTUAL_PARAMS=$(cat /proc/cmdline)

        # Check if each expected parameter is in the actual kernel parameters
        for param in "''${EXPECTED_PARAMS[@]}"; do
          if echo "$ACTUAL_PARAMS" | grep -q "$param"; then
            echo "Kernel parameter '$param' is correctly set."
          else
            echo "WARNING: Kernel parameter '$param' is NOT set."
            exit 1
          fi
        done

        # Additionally, check specific parameters from /proc/cpuinfo (for cpu-related parameters)
        echo "Checking CPU-specific parameters..."

        # Check if SMT (Hyper-Threading) is disabled, as required by "mds=full,nosmt"
        if grep -q "nosmt" <<< "$ACTUAL_PARAMS"; then
          if grep -q "siblings" /proc/cpuinfo && ! grep -q "HT" /proc/cpuinfo; then
            echo "SMT is disabled (as expected for mds=full,nosmt)."
          else
            echo "WARNING: SMT is still enabled, but 'mds=full,nosmt' was passed."
          fi
        fi

        # Check if Page Table Isolation (PTI) is enabled (from /proc/cpuinfo)
        if grep -q "pti" <<< "$ACTUAL_PARAMS"; then
          if grep -q "pti" /proc/cpuinfo; then
            echo "PTI is enabled (as expected for pti=on)."
          else
            echo "WARNING: PTI is not enabled, despite pti=on being passed."
          fi
        fi

        exit 0
      '';
  };

  R9 =
    let
      sysctls = {
        # Restrict access to dmesg buffer
        "kernel.dmesg_restrict" = "1";

        # Hide kernel addresses in /proc and other interfaces, even for privileged users
        "kernel.kptr_restrict" = "2";

        # Set process ID maximum
        "kernel.pid_max" = "1048576"; # 2^20

        # Restrict perf subsystem usage
        "kernel.perf_cpu_time_max_percent" = "1";
        "kernel.perf_event_max_sample_rate" = "1";

        # Restrict access to perf_event_open system call
        "kernel.perf_event_paranoid" = "2";

        # Enable Address Space Layout Randomization (ASLR)
        "kernel.randomize_va_space" = "2";

        # Disable Magic SysRq key (prevents magical system requests)
        "kernel.sysrq" = "0";

        # Restrict use of BPF (Berkeley Packet Filter) to privileged users
        "kernel.unprivileged_bpf_disabled" = "1";

        # Kernel panic on unexpected kernel behavior (e.g., oops)
        "kernel.panic_on_oops" = "1";
      };
    in
    {
      name = "R9_KernelOptions";
      anssiRef = "R9 – Paramétrer les options de configuration du noyau";
      description = "Tune kernel configuration options";
      severity = "intermediary";
      category = "base";

      config = _: { boot.kernel.sysctl = sysctls; };

      checkScript =
        pkgs:
        pkgs.writeShellScript "check-R9" ''
          ${mkSysctlChecker pkgs.lib sysctls}
        '';
    };

  R10 = {
    name = "R10_DisableKernelModuleLoading";
    anssiRef = "R10 – Désactiver le chargement des modules noyau";
    description = "Disable loading of kernel modules";
    severity = "reinforced";
    category = "base";
    tags = [ "disable-kernel-module-loading" ];

    config = _: { boot.kernel.sysctl."kernel.modules_disabled" = "1"; };

    checkScript =
      pkgs:
      pkgs.writeShellScript "check-R10" ''
        ${mkSysctlChecker pkgs.lib { "kernel.modules_disabled" = 1; }}
      '';
  };

  R11 = {
    name = "R11_ConfigureYamaLSM";
    anssiRef = "R11 – Activer et configurer le LSM Yama";
    description = "Enable and configure the Yama Linux Security Module";
    severity = "intermediary";
    category = "base";

    config = _: { boot.kernel.sysctl."kernel.yama.ptrace_scope" = "1"; };

    checkScript =
      pkgs:
      pkgs.writeShellScript "check-R11" ''
        ${mkSysctlChecker pkgs.lib { "kernel.yama.ptrace_scope" = 1; }}
      '';
  };

  R12 =
    let
      ipv4_sysctls = {
        # Harden the JIT compiler for BPF
        "net.core.bpf_jit_harden" = "2";

        # Disable IP forwarding (no routing between interfaces)
        "net.ipv4.ip_forward" = "0";

        # Reject packets with source address 127/8 (loopback network)
        "net.ipv4.conf.all.accept_local" = "0";

        # Disable ICMP redirects (prevents potential traffic redirection)
        "net.ipv4.conf.all.accept_redirects" = "0";
        "net.ipv4.conf.default.accept_redirects" = "0";
        "net.ipv4.conf.all.secure_redirects" = "0";
        "net.ipv4.conf.default.secure_redirects" = "0";

        # Disable shared media detection (useful for preventing misconfiguration)
        "net.ipv4.conf.all.shared_media" = "0";
        "net.ipv4.conf.default.shared_media" = "0";

        # Disable kernel ARP management across interfaces (security for high-availability setups)
        "net.ipv4.conf.all.arp_filter" = "1";

        # Respond to ARP requests only if source and destination are on the same network
        "net.ipv4.conf.all.arp_ignore" = "2";

        # Refuse routing of packets with loopback addresses as source or destination
        "net.ipv4.conf.all.route_localnet" = "0";

        # Drop Gratuitous ARP (prevents ARP poisoning attacks)
        "net.ipv4.conf.all.drop_gratuitous_arp" = "1";

        # Perform Reverse Path Filtering (checks if the source is reachable via the interface it came from)
        "net.ipv4.conf.default.rp_filter" = "1";
        "net.ipv4.conf.all.rp_filter" = "1";

        # Disable sending ICMP redirects (normal for routers but unnecessary for end hosts)
        "net.ipv4.conf.default.send_redirects" = "0";
        "net.ipv4.conf.all.send_redirects" = "0";

        # Ignore bogus ICMP error responses (RFC 1122)
        "net.ipv4.icmp_ignore_bogus_error_responses" = "1";

        # Increase the range for ephemeral ports (for better security)
        "net.ipv4.ip_local_port_range" = "32768 65535";

        # Enable RFC 1337 compliance (prevents TCP timestamp attacks)
        "net.ipv4.tcp_rfc1337" = "1";

        # Enable SYN cookies (prevents SYN flood attacks)
        "net.ipv4.tcp_syncookies" = "1";
      };
    in
    {
      name = "R12_IPv4Networking";
      anssiRef = "R12 – Paramétrer les options de configuration du réseau IPv4";
      description = "Configure IPv4 network options";
      severity = "intermediary";
      category = "base";

      config = _: { boot.kernel.sysctl = ipv4_sysctls; };

      checkScript =
        pkgs:
        pkgs.writeShellScript "check-R12" ''
          ${mkSysctlChecker pkgs.lib ipv4_sysctls}
        '';
    };

  R13 =
    let
      sysctls = {
        # Disable IPv6 on all interfaces by default
        "net.ipv6.conf.default.disable_ipv6" = "1";

        # Disable IPv6 on all interfaces
        "net.ipv6.conf.all.disable_ipv6" = "1";
      };
    in
    {
      name = "R13_DisableIPv6";
      anssiRef = "R13 – Désactiver le plan IPv6";
      description = "Disable IPv6";
      severity = "intermediary";
      category = "base";
      tags = [ "no-ipv6" ];

      config = _: { boot.kernel.sysctl = sysctls; };

      checkScript =
        pkgs:
        pkgs.writeShellScript "check-R13" ''
          ${mkSysctlChecker pkgs.lib sysctls}
        '';
    };

  R14 =
    let
      sysctls = {
        # Disable coredumps for setuid executables
        "fs.suid_dumpable" = "0";

        # Prevent opening FIFOs and regular files not owned by the user in sticky directories
        "fs.protected_fifos" = "2";
        "fs.protected_regular" = "2";

        # Restrict the creation of symbolic links to files owned by the user
        "fs.protected_symlinks" = "1";

        # Restrict the creation of hard links to files owned by the user
        "fs.protected_hardlinks" = "1";
      };
    in
    {
      name = "R14_FilesystemConfig";
      anssiRef = "R14 – Paramétrer les options de configuration des systèmes de fichiers";
      description = "Tune filesystem configuration options";
      severity = "intermediary";
      category = "base";

      config = _: { boot.kernel.sysctl = sysctls; };

      checkScript =
        pkgs:
        pkgs.writeShellScript "check-R14" ''
          ${mkSysctlChecker pkgs.lib sysctls}
        '';
    };
}
