{
  nixpkgs,
  crane,
  flake-utils,
  treefmt-nix,
  ...
}:
{
  allowFilesets ? [ ],
  features ? [ ],
  commonEnv ? { },
  commonNativeBuildInputs ? _: [ ],
  commonBuildInputs ? _: [ ],
  mainEnv ? { },
  mainNativeBuildInputs ? _: [ ],
  mainBuildInputs ? _: [ ],
}:
root: name:
flake-utils.lib.eachDefaultSystem (
  system:
  let
    pkgs = nixpkgs.legacyPackages.${system};
    inherit (pkgs) lib stdenv;
    craneLib = crane.mkLib pkgs;

    prepareFeatures =
      list: lib.optionalString (lib.length list > 0) "--features ${lib.concatStringsSep "," list}";

    commonArgs = {
      env = commonEnv;
      cargoExtraArgs = "--locked ${prepareFeatures features}";
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

    checks = {
      fmt = craneLib.cargoFmt {
        inherit (commonArtifacts) src;
      };

      clippy = craneLib.cargoClippy (
        commonArgs
        // {
          cargoArtifacts = commonArtifacts;
          cargoClippyExtraArgs = "-- -D warnings -W clippy::pedantic";
        }
      );

      clippy-tests = craneLib.cargoClippy (
        commonArgs
        // {
          cargoArtifacts = commonArtifacts;
          pnameSuffix = "-clippy-tests";
          cargoClippyExtraArgs = "--tests -- -D warnings -W clippy::pedantic";
        }
      );

      clippy-examples = craneLib.cargoClippy (
        commonArgs
        // {
          cargoArtifacts = commonArtifacts;
          pnameSuffix = "-clippy-examples";
          cargoClippyExtraArgs = "--examples -- -D warnings -W clippy::pedantic";
        }
      );

      docs = craneLib.cargoDoc (
        commonArgs
        // {
          cargoArtifacts = commonArtifacts;
        }
      );

      tests = craneLib.cargoTest (
        commonArgs
        // {
          cargoArtifacts = commonArtifacts;
        }
      );
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
