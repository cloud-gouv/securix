# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ lib, rustPlatform }:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "securix-hints";
  version = "0.1.0";

  src = lib.cleanSourceWith {
    src = ../rust;
    filter = path: _type: builtins.baseNameOf path != "target";
  };

  cargoLock.lockFile = ../rust/Cargo.lock;

  strictDeps = true;

  meta = {
    description = "Hints about the state of the machine, shown to the user";
    homepage = "https://github.com/cloud-gouv/securix";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = with lib.maintainers; [ raitobezarius ];
    mainProgram = "securix-hintd";
  };
})
