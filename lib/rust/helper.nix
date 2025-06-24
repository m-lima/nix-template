{
  root,
  system,
  pkgs,
  crane,
  fenix,
  treefmt-nix,
}:
let
  stdenv = pkgs.stdenv;
  lib = pkgs.stdenv;

  listFeatures =
    arg: list:
    lib.optionalString (builtins.length list > 0) "${arg} ${builtins.concatStringsSep "," list}";

  skipFeatures = listFeatures "--skip";

  prepareFeatures = listFeatures "--features";

  fenixPkgs = fenix.packages.${system};
  overrideCraneLib = (crane.mkLib pkgs).overrideToolchain;

  mkCraneLib =
    {
      toolchains ? fenixPkgs: [ ],
    }:
    overrideCraneLib (fenixPkgs.combine (toolchains fenixPkgs));
  mkCraneLibDefault = overrideCraneLib fenixPkgs.stable.toolchain;

  mkCommonArgs =
    {
      craneLib ? mkCraneLibDefault,
      features ? [ ],
      buildInputs ? pkgs: [ ],
      nativeBuildInputs ? pkgs: [ ],
      allowFilesets ? [ ],
      mega ? true,
    }:
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
    // (lib.optionalAttrs mega {
      CARGO_PROFILE = "mega";
      CARGO_BUILD_RUSTFLAGS = "-C target-cpu=native -C prefer-dynamic=no";
    });

  mkMainArgs =
    {
      craneLib ? mkCraneLibDefault,
      commonArgs ? mkCommonArgs { inherit craneLib; },
      lockRandomSeed ? false,
    }:
    commonArgs
    // (lib.optionalAttrs lockRandomSeed {
      NIX_OUTPATH_USED_AS_RANDOM_SEED = "0123456789";
    });

  mkCargoArtifacts =
    {
      craneLib ? mkCraneLibDefault,
      commonArgs ? mkCommonArgs { inherit craneLib; },
    }:
    craneLib.buildDepsOnly commonArgs;

  mkMainArtifacts =
    {
      craneLib ? mkCraneLibDefault,
      commonArgs ? mkCommonArgs { inherit craneLib; },
      mainArgs ? mkMainArgs { inherit craneLib commonArgs; },
      cargoArtifacts ? mkCargoArtifacts {
        inherit craneLib commonArgs;
      },
    }:
    craneLib.buildPackage (
      mainArgs
      // {
        inherit cargoArtifacts;
      }
    );

  mkCargoAll =
    {
      skip ? [ "default" ],
    }:
    pkgs.writeShellScriptBin "cargo-all" ''
      shift

      skip="${skipFeatures skip}"

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

  mkTreefmtConfig =
    {
      programs ? default: default,
      settings ? default: default,
    }:
    {
      programs = programs {
        nixfmt.enable = true;
        rustfmt = {
          enable = true;
          edition = "2024";
        };
        taplo.enable = true;
      };
      settings = settings {
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
    };

  mkTreefmt =
    {
      config ? mkTreefmtConfig { },
    }:
    (treefmt-nix.lib.evalModule pkgs config).config.build;

  mkFormatter =
    {
      treefmt,
    }:
    treefmt.wrapper;

  mkChecks =
    {
      outputs,
      treefmt ? mkTreefmt { },
      craneLib ? mkCraneLibDefault,
      commonArgs ? mkCommonArgs { inherit craneLib; },
      cargoArtifacts ? mkCargoArtifacts {
        inherit craneLib commonArgs;
      },
      extraChecks ? { },
      hack ? null,
    }:
    {
      formatting = treefmt.check outputs;
    }
    // (
      if builtins.isAttrs hack then
        {
          hack = craneLib.mkCargoDerivation (
            commonArgs
            // {
              inherit cargoArtifacts;
              buildPhaseCargoCommand = "cargo all";
              nativeBuildInputs = (commonArgs.nativeBuildInputs or [ ]) ++ [
                pkgs.cargo-hack
                hack
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
    // (lib.optionalAttrs (builtins.hasAttr "readme" extraChecks && extraChecks.readme) {
      readme = craneLib.mkCargoDerivation (
        commonArgs
        // {
          inherit cargoArtifacts;
          nativeBuildInputs = [ pkgs.cargo-readme ];
          buildPhaseCargoCommand = "diff README.md <(cargo readme)";
        }
      );
    })
    // (lib.optionalAttrs
      (builtins.hasAttr "bindgen" extraChecks && (builtins.isPath extraChecks.bindgen))
      {
        bindgen = craneLib.mkCargoDerivation (
          commonArgs
          // {
            inherit cargoArtifacts;
            nativeBuildInputs = [ pkgs.rust-cbindgen ];
            buildPhaseCargoCommand = "diff ${extraChecks.bindgen} <(cbindgen .)";
          }
        );
      }
    );

  mkDevShells =
    {
      checks ? mkChecks,
      craneLib ? mkCraneLibDefault,
      cargoAll ? mkCargoAll { },
    }:
    {
      default = craneLib.devShell {
        checks = checks;

        packages = with pkgs; [
          cargo-hack
          cargoAll
        ];
      };
    };

  mkApp =
    {
      drv,
      name ? drv.pname or drv.name,
      exePath ? drv.passthru.exePath or "/bin/${name}",
    }:
    {
      type = "app";
      program = "${drv}${exePath}";
    };

  mkApps =
    {
      mainArtifact ? mkMainArtifacts { },
    }:
    {
      default = mkApp { drv = mainArtifact; };
    };

  mkPackages =
    {
      mainArtifact ? mkMainArtifacts { },
    }:
    {
      default = mainArtifact;
    };
in
{
  inherit
    prepareFeatures
    mkCraneLib
    mkCraneLibDefault
    mkCommonArgs
    mkMainArgs
    mkCargoArtifacts
    mkMainArtifacts
    mkCargoAll
    mkTreefmtConfig
    mkTreefmt
    mkFormatter
    mkChecks
    mkDevShells
    mkApp
    mkApps
    mkPackages
    ;
}
