{ pkgs, ... }:

let
  yubikeysManagerUI = pkgs.writeShellScriptBin "yubikeys-manager-ui" ''
    export PATH="${pkgs.lib.makeBinPath [ pkgs.yubikey-manager pkgs.cryptsetup ]}:$PATH"

    PYTHON_INTERP="${pkgs.python3.withPackages (ps: [ ps.tkinter ])}/bin/python3"

    exec $PYTHON_INTERP ${./enrollement_yubi.py} "$@"
  '';
in
{
  environment.systemPackages = [ yubikeysManagerUI ];
}