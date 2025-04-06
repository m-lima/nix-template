{
  nixpkgs,
  crane,
  flake-utils,
  treefmt-nix,
  ...
}:
{
  commonEnv ? { },
  commonNativeBuildInputs ? _: [ ],
  commonBuildInputs ? _: [ ],
  mainEnv ? { },
  mainNativeBuildInputs ? _: [ ],
  mainBuildInputs ? _: [ ],
  allowFilesets ? [ ],
  hackSkip ? [ ],
}:
root: name:
flake-utils.lib.eachDefaultSystem (
  system:
  let
    pkgs = nixpkgs.legacyPackages.${system};
    inherit (pkgs) lib stdenv;
    craneLib = crane.mkLib pkgs;

    prepareSkip =
      list: lib.optionalString (lib.length list > 0) "--skip  ${lib.concatStringsSep "," list}";

    commonArgs = {
      env = commonEnv;
      nativeBuildInputs = commonNativeBuildInputs pkgs;
      buildInputs = lib.optionals stdenv.isDarwin [ pkgs.libiconv ] ++ commonBuildInputs pkgs;
      src = lib.fileset.toSource {
        inherit root;
        fileset = lib.fileset.unions (
          [
            (craneLib.fileset.commonCargoSources root)
          ]
          ++ allowFilesets
        );
      };
    };

    mainArgs = {
      env =
        commonArgs.env
        // {
          # Assumes that the template was used and that .cargo/config.toml is present
          CARGO_PROFILE = "mega";
          CARGO_BUILD_RUSTFLAGS = "-C target-cpu=native -C prefer-dynamic=no";
        }
        // mainEnv;
      nativeBuildInputs = commonArgs.nativeBuildInputs ++ mainNativeBuildInputs pkgs;
      buildInputs = commonArgs.buildInputs ++ mainBuildInputs pkgs;
    };

    commonArtifacts = craneLib.buildDepsOnly commonArgs;

    mainArtifact = craneLib.buildPackage (
      commonArgs
      // mainArgs
      // {
        cargoArtifacts = commonArtifacts;
      }
    );

    checks =
      let
        hack =
          {
            cmd,
            name ? cmd,
            args ? "",
            tools ? [ ],
          }:
          craneLib.mkCargoDerivation (
            commonArgs
            // {
              cargoArtifacts = commonArtifacts;
              pnameSuffix = "-hack-${cmd}";
              buildPhaseCargoCommand = "cargo hack --feature-powerset --workspace ${prepareSkip hackSkip} ${cmd} ${args}";
              nativeBuildInputs = (commonArgs.nativeBuildInputs or [ ]) ++ [ pkgs.cargo-hack ] ++ tools;
            }
          );
      in
      {
        hackCheck = hack {
          cmd = "check";
        };
        hackCheckTests = hack {
          cmd = "check";
          name = "check-tests";
          args = "--tests";
        };
        hackCheckExamples = hack {
          cmd = "check";
          name = "check-examples";
          args = "--examples";
        };
        hackClippy = hack {
          cmd = "clippy";
          args = "-- -D warnings -W clippy::pedantic";
          tools = [ pkgs.clippy ];
        };
        hackClippyTests = hack {
          cmd = "clippy";
          name = "clippy-tests";
          args = "--tests -- -D warnings -W clippy::pedantic";
          tools = [ pkgs.clippy ];
        };
        hackClippyExamples = hack {
          cmd = "clippy";
          name = "clippy-examples";
          args = "--examples -- -D warnings -W clippy::pedantic";
          tools = [ pkgs.clippy ];
        };
        hackTest = hack {
          cmd = "test";
        };
      };
  in
  {
    checks = checks;

    packages.default = mainArtifact;

    apps.default = flake-utils.lib.mkApp { drv = mainArtifact; };

    devShells.default = craneLib.devShell {
      inherit checks;
      packages = with pkgs; [
        cargo-hack
        (pkgs.writeShellScriptBin "cargo-all" ''
          #!/usr/bin/env bash
          shift

          skip="${prepareSkip hackSkip}"

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
                skip="--skip $1"
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
          cargo $nightly hack --feature-powerset $skip check --workspace $@ && \
          echo "[34mChecking examples[m" && \
          cargo $nightly hack --feature-powerset $skip check --workspace --examples $@ && \
          echo "[34mChecking tests[m" && \
          cargo $nightly hack --feature-powerset $skip check --workspace --tests $@ && \
          echo "[34mLinting main[m" && \
          cargo $nightly hack --feature-powerset $skip clippy --workspace $@ && \
          echo "[34mLinting tests[m" && \
          cargo $nightly hack --feature-powerset $skip clippy --workspace --tests $@ && \
          echo "[34mLinting examples[m" && \
          cargo $nightly hack --feature-powerset $skip clippy --workspace --examples $@ && \
          echo "[34mTesting main[m" && \
          cargo $nightly hack --feature-powerset $skip test --workspace $@ && \
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
)
