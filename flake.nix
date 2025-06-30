{
  description = "Extract from db2 and upload to BigQuery";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Rust compile stuff
    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Rust 3rd party tooling
    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };
  };

  outputs =
    { self, ... }@inputs:
    inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [ (import inputs.rust-overlay) ];
        };
        inherit (pkgs) lib;

        craneLib = (inputs.crane.mkLib pkgs).overrideToolchain (p: p.rust-bin.stable.latest.default);

        # Common vars
        cargoDetails = pkgs.lib.importTOML ./Cargo.toml;
        pname = cargoDetails.package.name;
        src = craneLib.cleanCargoSource (craneLib.path ./.);
        commonArgs = {
          inherit pname src;
          nativeBuildInputs =
            with pkgs;
            [
              pkg-config
              openssl
            ]
            ++ lib.optionals stdenv.isDarwin [
              darwin.apple_sdk.frameworks.Security
              darwin.apple_sdk.frameworks.SystemConfiguration
            ];
        };

        imageTag = "v${cargoDetails.package.version}-${dockerTag}";
        imageName = "${pname}:${imageTag}";
        teamName = "utsikt";
        my-spec = import ./spec.nix {
          inherit
            lib
            teamName
            pname
            imageName
            ;
        };

        # Compile (and cache) cargo dependencies _only_
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        cargo-sbom = craneLib.mkCargoDerivation (
          commonArgs
          // {
            # Require the caller to specify cargoArtifacts we can use
            inherit cargoArtifacts;

            # A suffix name used by the derivation, useful for logging
            pnameSuffix = "-sbom";

            # Set the cargo command we will use and pass through the flags
            installPhase = "mv bom.json $out";
            buildPhaseCargoCommand = "cargo cyclonedx -f json --all --override-filename bom";
            nativeBuildInputs = (commonArgs.nativeBuildInputs or [ ]) ++ [ pkgs.cargo-cyclonedx ];
          }
        );

        dockerTag =
          if lib.hasAttr "rev" self then
            "${builtins.toString self.revCount}-${self.shortRev}"
          else
            "gitDirty";

        # Compile workspace code (including 3rd party dependencies)
        db2 = pkgs.callPackage ./db2.nix { };
        cargo-package = craneLib.buildPackage (
          commonArgs
          // {
            inherit cargoArtifacts;
            meta.mainProgram = pname;

            # DB2
            nativeBuildInputs = (commonArgs.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
            postInstall =
              # bash
              ''
                wrapProgram $out/bin/${pname} \
                  --suffix PATH : "${lib.makeBinPath [ db2 ]}" \
                  --suffix LD_LIBRARY_PATH : "${lib.makeBinPath [ db2 ]}" \
                  --suffix IBM_DB_HOME : "${db2}"
              '';
          }
        );
        cargo-audit = craneLib.cargoAudit {
          inherit (inputs) advisory-db;
          inherit src;
        };
      in
      {
        checks = {
          inherit cargo-package cargo-sbom cargo-audit;
          # Run clippy (and deny all warnings) on the crate source,
          # again, resuing the dependency artifacts from above.
          #
          # Note that this is done as a separate derivation so that
          # we can block the CI if there are issues here, but not
          # prevent downstream consumers from building our crate by itself.
          cargo-clippy = craneLib.cargoClippy (
            commonArgs
            // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = lib.concatStringsSep " " [ ];
            }
          );
          cargo-doc = craneLib.cargoDoc (commonArgs // { inherit cargoArtifacts; });
          cargo-fmt = craneLib.cargoFmt { inherit src; };
        };
        devShells.default = craneLib.devShell {
          inputsFrom = [
            cargo-package
            cargo-sbom
            cargo-audit
          ];
          packages =
            with pkgs;
            [
              cargo-watch

              # Editor stuffs
              lldb
              rust-analyzer

              dive # For docker image inspection
            ]
            ++ lib.optionals stdenv.isDarwin [
              darwin.apple_sdk.frameworks.Security
              darwin.apple_sdk.frameworks.SystemConfiguration
            ];
        };

        packages = rec {
          default = rust;
          rust = cargo-package;
          sbom = cargo-sbom;
          image = docker;
          spec =
            let
              toJson = attrSet: builtins.toJSON attrSet;
              yamlContent = builtins.concatStringsSep ''

                ---
              '' (map toJson my-spec);
            in
            pkgs.writeText "spec.yaml" yamlContent;

          docker = pkgs.dockerTools.buildLayeredImage {
            name = pname;
            tag = imageTag;
            config.Entrypoint = [ (lib.getExe cargo-package) ];
          };
          inherit db2;
        };

        formatter =
          let
            linters = [
              # General
              "shellcheck"
              "dos2unix"

              # rust
              "rustfmt"

              # nix
              "alejandra"
              "statix"
              "nixfmt"
              "deadnix"
            ];
          in
          inputs.treefmt-nix.lib.mkWrapper pkgs (
            {
              projectRootFile = "flake.nix";
              settings.global.excludes = [
                "*.md"
                ".gitattributes"
              ];
            }
            // {
              programs = lib.genAttrs linters (_: {
                enable = true;
              });
            }
          );
      }
    );
}
