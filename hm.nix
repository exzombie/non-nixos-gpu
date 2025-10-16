# SPDX-FileCopyrightText: 2025 Jure Varlec <jure@varlec.si>
#
# SPDX-License-Identifier: MIT

{ config, lib, pkgs, ... }:

{
  options.nonNixosGpu = let
    inherit (lib) mkOption mkEnableOption types literalExpression;
  in {
    enable = mkOption {
      type = types.bool;
      default = config.targets.genericLinux.enable;
      defaultText = literalExpression "config.targets.genericLinux.enable";
      example = true;
      description = "Whether to enable non-NixOS GPU drivers.";
    };

    packages = mkOption {
      type = types.attrs;
      default = pkgs;
      defaultText = literalExpression "pkgs";
      description = "The package set where drivers are taken from.";
    };

    nvidia = {
      enable = mkEnableOption "proprietary Nvidia drivers.";

      version = mkOption {
        type = types.nullOr (types.strMatching "[0-9]{3}\\.[0-9]{3}\\.[0-9]{2}");
        default = null;
        example = literalExpression "550.163.01";
        description = ''
          The exact version of Nvidia drivers to use. This version **must**
          match the version of the driver used by the host OS.
        '';
      };

      sha256 = mkOption {
        type = types.nullOr (types.strMatching "sha256-.*=");
        default = null;
        example = literalExpression
          "sha256-hfK1D5EiYcGRegss9+H5dDr/0Aj9wPIJ9NVWP3dNUC0=";
        description = ''
          The hash of the downloaded driver file. It can be obtained by
          running, for example,

          ```sh
          nix store prefetch-file https://download.nvidia.com/XFree86/Linux-x86_64/@VERSION@/NVIDIA-Linux-x86_64-@VERSION@.run
          ```

          where `@VERSION@` is replaced with the exact driver version.
          If you are on ARM, replace Linux-x86_64 with Linux-aarch64.
        '';
      };
    };
  };

  config = let
    cfg = config.nonNixosGpu;

    # This builds the driver archive downloaded from download.nvidia.com
    nvidia = (cfg.packages.linuxPackages.nvidiaPackages.mkDriver {
      version = cfg.nvidia.version;
      sha256_64bit = cfg.nvidia.sha256;
      sha256_aarch64 = cfg.nvidia.sha256;
      useSettings = false;
      usePersistenced = false;
    }).override {
      libsOnly = true;
      kernel = null;
    };

    drivers = cfg.packages.callPackage ./gpu-libs-env.nix {
      addNvidia = cfg.nvidia.enable;
      nvidia_x11 = nvidia;  # Only used if addNvidia is enabled
    };

    setupPackage = cfg.packages.callPackage ./setup { non-nixos-gpu-env = drivers; };

  in lib.mkIf cfg.enable {
    assertions = lib.optionals cfg.nvidia.enable [
      {
        assertion = ! isNull cfg.nvidia.version;
        message = ''
          Nvidia proprietary driver is enabled, version must be given.
          Please set nonNixosGpu.nvidia.version.
        '';
      }
      {
        assertion = ! isNull cfg.nvidia.sha256;
        message = ''
          Nvidia proprietary driver is enabled, driver hash must be given.
          Please set nonNixosGpu.nvidia.sha256.
        '';
      }
    ];

    home.packages = [ setupPackage ];

    home.activation.checkExistingGpuDrivers = let
      # Absolute path is needed for use with sudo which doesn't have the user's
      # home environment.
      setupPath = "${lib.getExe setupPackage}";
    in lib.hm.dag.entryAnywhere ''
      existing=$(readlink /run/opengl-driver || true)
      new=${drivers}
      verboseEcho Existing drivers: ''${existing}
      verboseEcho New drivers: ''${new}
      if [[ "''${existing}" != "''${new}" ]] ; then
        warnEcho "GPU drivers updated, run 'sudo ${setupPath}'"
      fi
    '';
  };
}
