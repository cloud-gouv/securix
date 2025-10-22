# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ pkgs, ... }:
{
  imports = [ ./firefox.nix ];

  programs.mtr.enable = true;

  environment.systemPackages = with pkgs; [
    # Text editors
    neovim
    emacs
    vscodium
    vim
    # TPM2
    tpm2-tools
    # Terraform operations
    opentofu
    # Vault-like operations
    # Uncomment when we have upgraded to NixOS 25.05.
    # openbao
    # AWS S3 operations
    rclone
    awscli2
    s3cmd
    restic
    # Bastion
    teleport_16
    # OpenStack CLI - contient: heat, designate, barbican, etc.
    openstackclient-full
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
    bitwarden-cli # Bitwarden CLI.
    rbw # Caching Bitwarden CLI.
    rofi-rbw-wayland # Rofi menu for rbw.
    tree # Tree display
    gnupg # PGP
    connect # for using ssh with a proxy
    jq # Lightweight and flexible command-line JSON processor
    # Git, the full tooling.
    gitAndTools.gitFull
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
    tshark
    wireshark
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
