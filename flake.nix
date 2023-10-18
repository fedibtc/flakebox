{
  description = "Toolkit for building Nix Flake development environments for Rust projects";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    systems.url = "github:nix-systems/default";
    flake-utils.url = "github:numtide/flake-utils";
    flake-utils.inputs.systems.follows = "systems";

    crane = {
      url = "github:dpc/crane?rev=c97a0c0d83bfdf01c29113c5592a3defc27cb315";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    android-nixpkgs = {
      url = "github:dpc/android-nixpkgs?rev=2e42268a196375ce9b010a10ec5250d2f91a09b4"; # stable channel https://github.com/tadfisher/android-nixpkgs/tree/stable
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };
  outputs = { flake-utils, nixpkgs, nixpkgs-unstable, crane, fenix, android-nixpkgs, ... }:
    let
      mkLib = pkgs: import ./lib
        {
          inherit pkgs crane fenix android-nixpkgs nixpkgs;
        };
    in
    { } //
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs-unstable = import nixpkgs-unstable {
          inherit system;
        };
        pkgs = import nixpkgs {
          inherit system;

          overlays = [
            (final: prev: {
              rblake2sum = pkgs-unstable.rblake2sum;

              just = pkgs-unstable.just.overrideAttrs (prev: rec {
                pname = "just";
                version = "1.15.0";

                src = pkgs-unstable.fetchFromGitHub {
                  owner = "casey";
                  repo = "just";
                  rev = "refs/tags/${version}";
                  hash = "sha256-r1YJ7L98aLAwBd3g+WlW/UijceR7t9z7aXSZZjlMNnM=";
                };

                cargoHash = "sha256-Fx2BdSHo+W43ZM/SX1ccddXG9QHlftrupT2cbyT4KM0=";
                cargoDeps = prev.cargoDeps.overrideAttrs (prevDeps: {
                  name = "${pname}-vendor.tar.gz";
                  inherit src;
                  outputHash = "sha256-h8l4af/FMsOSqBf1V1tbniS6r1dQos7JM1215o1pmTA=";
                });
              });

              # TODO: waiting for nixpkgs to have https://github.com/crate-ci/typos/commit/35a8bc67870d6c0b7407683319ae175577e24261
              typos = pkgs-unstable.rustPlatform.buildRustPackage {
                pname = "typos";
                version = "1.16.19";

                src = prev.fetchFromGitHub {
                  owner = "crate-ci";
                  repo = "typos";
                  rev = "35a8bc67870d6c0b7407683319ae175577e24261";
                  hash = "sha256-R/144kHAP3npxrsBAskl1i1viARXZSdLKWFaWp/rkbs=";
                };

                cargoHash = "sha256-tYqEFoemFM8fYq9LuNcr7b0XyQQbn8cDlgk3z4Uk36c=";
              };
            })
          ];
        };

        flakeboxLib = mkLib pkgs {
          config = { };
        };

        src = flakeboxLib.filterSubPaths {
          root = builtins.path {
            name = "flakebox";
            path = ./.;
          };
          paths = [
            "Cargo.toml"
            "Cargo.lock"
            ".cargo"
            "flakebox-bin"
          ];
        };

        outputs =
          (flakeboxLib.craneMultiBuild { }) (craneLib':
            let
              craneLib = (craneLib'.overrideArgs {
                pname = "flexbox";
                nativeBuildInputs = [
                  pkgs.mold
                ];
                inherit src;
              });
            in
            rec {
              workspaceDeps = craneLib.buildWorkspaceDepsOnly { };
              workspaceBuild = craneLib.buildWorkspace {
                cargoArtifacts = workspaceDeps;
              };
              flakebox = craneLib.buildPackage { };
              flakeboxGroup = craneLib.buildPackageGroup { packages = [ "flakebox" ]; mainProgram = "flakebox"; };
            });


        checks =
          pkgs.callPackages ./checks {
            inherit pkgs;
            mkLib = mkLib;
          };
      in
      {

        inherit checks;
        lib = mkLib pkgs;

        packages = {
          bootstrap = pkgs.writeShellScriptBin "flakebox-bootstrap" "exec ${pkgs.bash}/bin/bash ${./bin/bootstrap.sh} ${./bin/bootstrap.flake.nix} \"$@\"";
          root = flakeboxLib.root;
          default = outputs.flakebox;
          docs = flakeboxLib.docs;
          fullChecks =
            (pkgs.callPackages ./checks {
              inherit pkgs;
              mkLib = mkLib;
              full = true;
            }).workspaceCross;
        };

        legacyPackages = outputs;

        devShells = flakeboxLib.mkShells {
          packages = [ pkgs.mdbook ];
        };

      });
}
