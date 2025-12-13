# SPDX-FileCopyrightText: 2025 Elias Coppens <elias.coppens@numerique.gouv.fr>
# SPDX-FileContributor: Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  stdenv,
  darwin,
  c-ares,
  python3,
  lua5_4,
  capnproto,
  cmake,
  openssl,
}:

rustPlatform.buildRustPackage rec {
  pname = "g3";
  version = "v1.10.4";

  src = fetchFromGitHub {
    owner = "bytedance";
    repo = "g3";
    rev = "g3proxy-${version}";
    hash = "sha256-uafKYyzjGdtC+oMJG1wWOvgkSht/wTOzyODcPoTfOnU=";
  };

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
  };

  cargoHash = "sha256-sK2xSlkJLR2ApILQVvTKmHKXvkWRwHdUSJ/Xy5TsLp8=";

  nativeBuildInputs = [
    pkg-config
    rustPlatform.bindgenHook
    python3
    capnproto
    cmake
  ];

  buildInputs = [
    c-ares
    lua5_4
    openssl
  ]
  ++ lib.optionals stdenv.isDarwin [ darwin.apple_sdk.frameworks.Security ];

  meta = {
    description = "Enterprise-oriented Generic Proxy Solutions";
    homepage = "https://github.com/bytedance/g3";
    changelog = "https://github.com/bytedance/g3/blob/${src.rev}/CHANGELOG.md";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ raitobezarius ];
    mainProgram = "g3proxy";
  };
}
