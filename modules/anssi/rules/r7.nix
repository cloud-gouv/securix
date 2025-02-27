{ config, lib, ... }:
let
  anssiLib = import ../lib { inherit lib; };
in 
  anssiLib.mkRule {
    number = 7;
    description = "IO memory management unit";
    module.boot.kernelParams = [
      "iommu=force"
    ];
    inherit config;
  }
