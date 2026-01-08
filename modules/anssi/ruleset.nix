{ lib, ... }:
let
  loadRules = files:
    lib.mergeAttrsList (map (file: import file) files);
in
loadRules [
]
