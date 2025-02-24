{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane.url = "github:ipetkov/crane";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
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
        inherit (pkgs) lib stdenv;
        craneLib = crane.mkLib pkgs;

        common = {
          env = { };
          nativeBuildInputs = [ ];
          buildInputs = [ ];
          allowFilesets = [ ];
        };

        main = {
          env = { };
          nativeBuildInputs = [ ];
          buildInputs = [ ];
        };

        hackSkip = "--skip default";

        commonArgs = {
          env = common.env;
          nativeBuildInputs = common.nativeBuildInputs;
          buildInputs = lib.optionals stdenv.isDarwin [ pkgs.libiconv ] ++ common.buildInputs;
          src =
            let
              root = ./.;
            in
            lib.fileset.toSource {
              inherit root;
              fileset =
                lib.fileset.unions [
                  (craneLib.fileset.commonCargoSources root)
                ]
                ++ common.allowFilesets;
            };
        };

        mainArgs = {
          env =
            commonArgs.env
            // {

              CARGO_PROFILE = "mega";
              CARGO_BUILD_RUSTFLAGS = "-C target-cpu=native -C prefer-dynamic=no";
            }
            // main.env;
          nativeBuildInputs = commonArgs.nativeBuildInputs ++ main.nativeBuildInputs;
          buildInputs = commonArgs.buildInputs ++ main.buildInputs;
        };

        commonArtifacts = craneLib.buildDepsOnly commonArgs;

        rust_template = craneLib.buildPackage (
          commonArgs
          // mainArgs
          // {
            inherit commonArtifacts;
          }
        );

      in
      # main = {
      #   env = deps.env // {
      #     NIX_OUTPATH_USED_AS_RANDOM_SEED = "ragenixout";
      #   };
      #
      #   args =
      #     deps.args
      #     // main.env
      #     // {
      #       cargoArtifacts = deps.build;
      #       nativeBuildInputs =
      #         with pkgs;
      #         deps.args.nativeBuildInputs
      #         ++ [
      #           pkg-config
      #           rustPlatform.bindgenHook
      #         ];
      #       buildInputs =
      #         with pkgs;
      #         deps.args.buildInputs
      #         ++ [
      #           nix
      #           boost
      #         ];
      #     };
      #
      #   build = craneLib.buildPackage main.args;
      # };
      #
      # commonArgs = {
      #   src = craneLib.cleanCargoSource ./.;
      #   strictDeps = true;
      #
      #   nativeBuildInputs = with pkgs; [ pkg-config ];
      #   buildInputs = with pkgs; [ ] ++ lib.optionals stdenv.isDarwin [ libiconv ];
      # };
      #
      # cargoArtifacts = craneLib.buildDepsOnly commonArgs;
      #
      # rust_template = craneLib.buildPackage (
      #   commonArgs
      #   // {
      #     inherit cargoArtifacts;
      #
      #     env = {
      #       CARGO_PROFILE = "mega";
      #       CARGO_BUILD_RUSTFLAGS = "-C target-cpu=native -C prefer-dynamic=no";
      #     };
      #   }
      # );
      {
        checks =
          let
            hack =
              {
                args,
                tools ? [ ],
              }:
              craneLib.mkCargoDerivation (
                commonArgs
                // {
                  inherit commonArtifacts;
                  pnameSuffix = "-hack";
                  buildPhaseCargoCommand = "cargo hack --feature-powerset --workspace ${args} ${hackSkip}";
                  nativeBuildInputs = (commonArgs.nativeBuildInputs or [ ]) ++ [ pkgs.cargo-hack ] ++ tools;
                }
              );
          in
          {
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
          packages = with pkgs; [
            cargo-hack
            (pkgs.writeShellScriptBin "cargo-all" ''
              #!/usr/bin/env bash
              shift

              skip="${hackSkip}"

              while (( $# > 0 )); do
                case "$1" in
                  nightly)
                    nightly='+nightly' ;;
                  run|r)
                    run=1 ;;
                  clean|c)
                    clean=1 ;;
                  skip|s)
                    shift
                    skip="--skip ${1}"
                    ;;
                esac
                shift
              done

              if [ $clean ]; then
                echo "[34mCleaning[m" && \
                cargo clean
              fi && \
              echo "[34mFormatting[m" && \
              cargo $nightly fmt --all && \
              echo "[34mChecking main[m" && \
              cargo $nightly hack --feature-powerset ${skip} check --workspace $@ && \
              echo "[34mChecking examples[m" && \
              cargo $nightly hack --feature-powerset ${skip} check --workspace --examples $@ && \
              echo "[34mChecking tests[m" && \
              cargo $nightly hack --feature-powerset ${skip} check --workspace --tests $@ && \
              echo "[34mLinting main[m" && \
              cargo $nightly hack --feature-powerset ${skip} clippy --workspace $@ && \
              echo "[34mLinting tests[m" && \
              cargo $nightly hack --feature-powerset ${skip} clippy --workspace --tests $@ && \
              echo "[34mLinting examples[m" && \
              cargo $nightly hack --feature-powerset ${skip} clippy --workspace --examples $@ && \
              echo "[34mTesting main[m" && \
              cargo $nightly hack --feature-powerset ${skip} test --workspace $@ && \
              if [ "$run" ]; then
                echo "[34mRunning[m" && \
                cargo $nightly run $@
              fi
            '')
          ];
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
