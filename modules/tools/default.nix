# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ pkgs, ... }:
{
  imports = [ ./firefox.nix ];

  programs.mtr.enable = true;

  environment.systemPackages = with pkgs; [
    # Text editors
    vscodium
    vim
    # TPM2
    tpm2-tools
    # A TPM-backed agent for SSH keys
    ssh-tpm-agent
    # VNC remoting
    tigervnc
    # Some good terminals.
    alacritty
    # Uncomment when NixOS 25.05 is used.
    # ghostty
    kitty
    tmux # Multiplexer
    screen # Multiplexer
    # Scripting
    python3
    gum # TUI scripting
    # PKI
    certstrap # Certificate bootstrap for CAs
    openssl # Generic purpose certificate tooling
    step-ca # CA tooling
    opensc # PKCS#11 tooling
    # Misc
    termdown # Time counter
    fd # `find` alternative.
    ripgrep # super fast `grep`
    ripgrep-all # multi-format fast `grep`
    pwgen # Password generator.
    rofi-rbw-wayland # Rofi menu for rbw.
    tree # Tree display
    gnupg # PGP
    connect # for using ssh with a proxy
    jq # Lightweight and flexible command-line JSON processor
    yq # Same as jq but for YAML
    # Git, the full tooling.
    gitFull
    git-lfs
    git-absorb
    git-gr
    lazygit
    jujutsu
    # Serial console work.
    minicom
    picocom
    # To send files securly to another endpoint.
    magic-wormhole-rs
    # iPXE / PXE operations
    pixiecore
    # Unzipping
    unzip
    # To calculate things
    libqalculate
    # Troubleshooting
    iperf3
    tcpdump
    dnsutils
    conntrack-tools
    pwru # Packet, where are you? - eBPF tooling
    strace
    gdb
    # Network calculators
    sipcalc
    ipv6calc
    # D-Bus debugging
    d-spy
    # Offline documentation
    linux-manual
    glibcInfo
    man-pages
    man-pages-posix
    # Browser
    firefox
  ];
}
