# SPDX-FileCopyrightText: 2025 Jure Varlec <jure@varlec.si>
#
# SPDX-License-Identifier: MIT

{
  description = "GPU driver setup for Nix on non-NixOS Linux systems";

  inputs = {
    # Nixpkgs / NixOS version to use.
    nixpkgs.url = "nixpkgs/nixos-25.05";

    # Config file - JSON with enabling nvidia, custom nvidia driver version and sha256
    config-params = {
      url = ./config.json;
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      config-params,
    }:
    let
      # to work with older version of flakes
      lastModifiedDate = self.lastModifiedDate or self.lastModified or "19700101";

      # Generate a user-friendly version number.
      version = builtins.substring 0 8 lastModifiedDate;

      config = builtins.fromJSON (builtins.readFile config-params);

      # System types to support.
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          config = {
            allowUnfree = config.addNvidia;
            nvidia.acceptLicense = config.addNvidia;
          };
        }
      );
    in
    {
      # Provide some binary packages for selected system types.
      packages = forAllSystems (system: rec {
        nvidia =
          (nixpkgsFor.${system}.linuxPackages.nvidiaPackages.mkDriver ({
            version = config.nvidia.version;
            sha256_64bit = config.nvidia.sha256_64bit;
            sha256_aarch64 = config.nvidia.sha256_aarch64;
            useSettings = false;
            usePersistenced = false;
          })).override
            {
              libsOnly = true;
              kernel = null;
            };
        env = nixpkgsFor.${system}.callPackage ./gpu-libs-env.nix {
          nvidia_x11 = nvidia;
          addNvidia = config.addNvidia;
        };
        setup = nixpkgsFor.${system}.callPackage ./setup { non-nixos-gpu-env = env; };
      });

      # The default package for 'nix build'. This makes sense if the
      # flake provides only one package or there is a clear "main"
      # package.
      defaultPackage = forAllSystems (system: self.packages.${system}.setup);
    };
}
