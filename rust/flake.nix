{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane.url = "github:ipetkov/crane";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
      flake-utils,
      treefmt-nix,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        craneLib = crane.mkLib pkgs;

        commonArgs = {
          src = craneLib.cleanCargoSource ./.;
          strictDeps = true;

          nativeBuildInputs = with pkgs; [ pkg-config ];
          buildInputs = with pkgs; [ ] ++ lib.optionals stdenv.isDarwin [ libiconv ];

          # CARGO_BUILD_RUSTFLAGS = "-C target-cpu=native -C prefer-dynamic=no";
        };

        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        rust_template = craneLib.buildPackage (commonArgs // { inherit cargoArtifacts; });

        hack =
          {
            args,
            tools ? [ ],
          }:
          craneLib.mkCargoDerivation (
            commonArgs
            // {
              inherit cargoArtifacts;
              pnameSuffix = "-hack";
              buildPhaseCargoCommand = "cargo hack --feature-powerset --workspace ${args}";
              nativeBuildInputs = (commonArgs.nativeBuildInputs or [ ]) ++ [ pkgs.cargo-hack ] ++ tools;
            }
          );
      in
      {
        checks = {
          inherit rust_template;

          hackCheck = hack {
            args = "check";
          };
          hackCheckTests = hack {
            args = "check --tests";
          };
          hackCheckExamples = hack {
            args = "check --examples";
          };
          hackClippy = hack {
            args = "clippy";
            tools = [ pkgs.clippy ];
          };
          hackClippyTests = hack {
            args = "clippy --tests";
            tools = [ pkgs.clippy ];
          };
          hackClippyExamples = hack {
            args = "clippy --examples";
            tools = [ pkgs.clippy ];
          };
          hackTest = hack {
            args = "test";
          };
        };

        packages.default = rust_template;

        apps.default = flake-utils.lib.mkApp {
          drv = rust_template;
        };

        devShells.default = craneLib.devShell {
          checks = self.checks.${system};
          packages = with pkgs; [ cargo-hack ];
        };

        formatter =
          (treefmt-nix.lib.evalModule pkgs {
            projectRootFile = "Cargo.toml";
            programs = {
              nixfmt.enable = true;
              rustfmt.enable = true;
              taplo.enable = true;
            };
            settings = {
              excludes = [
                "*.lock"
                ".direnv/*"
                ".envrc"
                ".gitignore"
                "result*/"
                "target/*"
              ];
            };
          }).config.build.wrapper;
      }
    );
}
