# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ lib, python3Packages }:

python3Packages.buildPythonApplication (finalAttrs: {
  pname = "plasma-portail-tray-icon";
  version = "0.1.0";
  pyproject = true;

  src = ./src;

  build-system = with python3Packages; [ hatchling ];

  dependencies = with python3Packages; [
    pyside6
    varlink
  ];

  meta = {
    description = "Plasma tray icon for the Portail access proxy";
    homepage = "https://github.com/cloud-gouv/portail";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
    maintainers = with lib.maintainers; [ raitobezarius ];
    mainProgram = "tray";
  };
})
