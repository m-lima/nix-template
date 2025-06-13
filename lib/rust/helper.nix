{
  self,
  nixpkgs,
  crane,
  fenix,
  flake-utils,
  treefmt-nix,
  ...
}:
{
  allowFilesets ? [ ],
  features ? [ ],
  lockRandomSeed ? false,
  mega ? true,
  binary ? true,
  hack ? false,
  fmts ? [ ],
  buildInputs ? pkgs: [ ],
  nativeBuildInputs ? pkgs: [ ],
  args ? { },
  buildArgs ? { },
  toolchains ? fenix: [ fenix.stable.toolchain ],
  packages ?
    {
      system,
      pkgs,
      lib,
      craneLib,
      prepareFeatures,
      mainArgs,
      cargoArtifacts,
    }:
    { },
  checks ? {
    readme = false;
    bindgen = null;
  },
}:
root: name:
flake-utils.lib.eachDefaultSystem (
  system:
  let
    pkgs = nixpkgs.legacyPackages.${system};
    inherit (pkgs) lib stdenv;
    craneToolchain =
      let
        fenixPkgs = fenix.packages.${system};
      in
      fenixPkgs.combine (toolchains fenixPkgs);
    craneLib = (crane.mkLib pkgs).overrideToolchain craneToolchain;

    prepareFeatures =
      list: lib.optionalString (lib.length list > 0) "--features ${lib.concatStringsSep "," list}";

    commonArgs =
      {
        strictDeps = true;
        cargoExtraArgs = "--locked ${prepareFeatures features}";
        nativeBuildInputs = nativeBuildInputs pkgs;
        buildInputs = lib.optionals stdenv.isDarwin [ pkgs.libiconv ] ++ buildInputs pkgs;
        src = lib.fileset.toSource {
          inherit root;
          fileset = lib.fileset.unions (
            [
              (craneLib.fileset.commonCargoSources root)
            ]
            ++ allowFilesets
          );
        };
      }
      // args
      // (lib.optionalAttrs mega {
        CARGO_PROFILE = "mega";
        CARGO_BUILD_RUSTFLAGS = "-C target-cpu=native -C prefer-dynamic=no";
      });

    mainArgs =
      commonArgs
      // (lib.optionalAttrs lockRandomSeed {
        NIX_OUTPATH_USED_AS_RANDOM_SEED = "0123456789";
      });

    cargoArtifacts = craneLib.buildDepsOnly commonArgs;

    mainArtifact = craneLib.buildPackage (
      mainArgs
      // {
        inherit cargoArtifacts;
      }
      // buildArgs
    );

    treefmt =
      (treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "Cargo.toml";
        programs =
          {
            nixfmt.enable = true;
            rustfmt = {
              enable = true;
              edition = "2024";
            };
            taplo.enable = true;
          }
          // (lib.listToAttrs (
            map (x: {
              name = x;
              value = {
                enable = true;
              };
            }) fmts
          ));
        settings = {
          excludes = [
            "*.lock"
            ".direnv/*"
            ".envrc"
            ".gitignore"
            "result*/*"
            "target/*"
            "LICENSE"
          ];
        };
      }).config.build;

    cargoAll = pkgs.writeShellScriptBin "cargo-all" ''
      shift

      skip="--skip default"

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
    '';

    checkSetup =
      {
        formatting = treefmt.check self;
      }
      // (
        if hack then
          {
            hack = craneLib.mkCargoDerivation (
              commonArgs
              // {
                inherit cargoArtifacts;
                buildPhaseCargoCommand = "cargo all";
                nativeBuildInputs = (commonArgs.nativeBuildInputs or [ ]) ++ [
                  pkgs.cargo-hack
                  cargoAll
                ];
              }
            );
          }
        else
          {
            clippy = craneLib.cargoClippy (
              commonArgs
              // {
                inherit cargoArtifacts;
                cargoClippyExtraArgs = "-- -D warnings -W clippy::pedantic";
              }
            );

            clippy-tests = craneLib.cargoClippy (
              commonArgs
              // {
                inherit cargoArtifacts;
                pnameSuffix = "-clippy-tests";
                cargoClippyExtraArgs = "--tests -- -D warnings -W clippy::pedantic";
              }
            );

            clippy-examples = craneLib.cargoClippy (
              commonArgs
              // {
                inherit cargoArtifacts;
                pnameSuffix = "-clippy-examples";
                cargoClippyExtraArgs = "--examples -- -D warnings -W clippy::pedantic";
              }
            );

            docs = craneLib.cargoDoc (
              commonArgs
              // {
                inherit cargoArtifacts;
              }
            );

            tests = craneLib.cargoTest (
              commonArgs
              // {
                inherit cargoArtifacts;
              }
            );
          }
      )
      // (lib.optionalAttrs (builtins.hasAttr "readme" checks && checks.readme) {
        readme = craneLib.mkCargoDerivation (
          commonArgs
          // {
            inherit cargoArtifacts;
            nativeBuildInputs = [ pkgs.cargo-readme ];
            buildPhaseCargoCommand = "diff README.md <(cargo readme)";
          }
        );
      })
      // (lib.optionalAttrs (builtins.hasAttr "bindgen" checks && (builtins.isPath checks.bindgen)) {
        bindgen = craneLib.mkCargoDerivation (
          commonArgs
          // {
            inherit cargoArtifacts;
            nativeBuildInputs = [ pkgs.rust-cbindgen ];
            buildPhaseCargoCommand = "diff ${checks.bindgen} <(cbindgen .)";
          }
        );
      });
  in
  {
    checks = checkSetup;

    packages =
      {
        default = mainArtifact;
      }
      // (lib.optionalAttrs (!binary) {
        deps = cargoArtifacts;
      })
      // (packages {
        inherit
          system
          pkgs
          lib
          craneLib
          prepareFeatures
          mainArgs
          cargoArtifacts
          ;
      });

    formatter = treefmt.wrapper;

    devShells.default = craneLib.devShell {
      checks = checkSetup;

      packages = with pkgs; [
        cargo-hack
        cargoAll
      ];
    };
  }
  // (lib.optionalAttrs binary {
    apps.default = flake-utils.lib.mkApp { drv = mainArtifact; };
  })
)
