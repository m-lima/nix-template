#   treefmt           cargoAll          craneLib
#     │ │                │                 │
#     │ │                │             commonArgs
#     │ │                │        ╭───────╯ ╰──────╮
#     │ │                │  cargoArtifacts     mainArgs
#     │ ╰───────────────╮│╭──────╯ ╰──────╮ ╭──────╯
# formatting           checks           package
#                        │
#                     devShell
{
  self,
  nixpkgs,
  crane,
  fenix,
  treefmt-nix,
  ...
}:
system: root:
{
  toolchains ? fenixPkgs: [ ],
  features ? [ ],
  cargoExtraArgs ? "",
  buildInputs ? pkgs: [ ],
  nativeBuildInputs ? pkgs: [ ],
  allowFilesets ? [ ],
  mega ? true,
  binary ? true,
  skip ? [ "default" ],
  formatters ? { },
  lockRandomSeed ? false, # Useful when using `cc`
  hack ? false, # If cargo-all with cargo-hack should be used
  readme ? false, # If cargo-readme should be used to check the README.md file
  bindgen ? null, # Path to the generated bindgen file, if it should be checked
  overrides ? { },
}:
let
  pkgs = nixpkgs.legacyPackages.${system};
  inherit (pkgs) lib;

  listFeatures =
    arg: list:
    lib.optionalString (builtins.length list > 0) "${arg} ${builtins.concatStringsSep "," list}";

  override =
    overrider: default:
    if builtins.isFunction overrider then
      overrider default
    else if builtins.isList default then
      default ++ overrider
    else
      default // overrider;

  tryOverride =
    name: default:
    if builtins.hasAttr name overrides then override overrides.${name} default else default;
in
rec {
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

  craneLib = tryOverride "craneLib" (
    let
      fenixPkgs = fenix.packages.${system};
      resolvedToolchains = toolchains fenixPkgs;
    in
    (crane.mkLib pkgs).overrideToolchain (
      if builtins.length resolvedToolchains == 0 then
        fenixPkgs.stable.toolchain
      else if builtins.length resolvedToolchains < 2 then
        builtins.head resolvedToolchains
      else
        fenixPkgs.combine resolvedToolchains
    )
  );

  commonArgs = tryOverride "commonArgs" (
    let
      prepareFeatures = listFeatures "--features";
    in
    {
      nativeBuildInputs = nativeBuildInputs pkgs;
      buildInputs = buildInputs pkgs;
      strictDeps = true;
      cargoExtraArgs = "--locked ${prepareFeatures features} ${cargoExtraArgs}";
      src = lib.fileset.toSource {
        inherit root;
        fileset = lib.fileset.unions (
          [
            (craneLib.fileset.commonCargoSources root)
          ]
          ++ allowFilesets
          ++ (lib.flatten (
            lib.optional readme [
              (root + "/README.md")
              (root + "/README.tpl")
            ]
          ))
        );
      };
    }
    // (lib.optionalAttrs mega {
      CARGO_PROFILE = "mega";
      CARGO_BUILD_RUSTFLAGS = "-C target-cpu=native -C prefer-dynamic=no";
    })
  );

  mainArgs = tryOverride "mainArgs" (
    commonArgs
    // (lib.optionalAttrs lockRandomSeed {
      NIX_OUTPATH_USED_AS_RANDOM_SEED = "0123456789";
    })
  );

  cargoArtifacts = tryOverride "cargoArtifacts" (craneLib.buildDepsOnly commonArgs);

  mainArtifact = tryOverride "mainArtifact" (
    craneLib.buildPackage (mainArgs // { inherit cargoArtifacts; })
  );

  treefmt = tryOverride "treefmt" {
    projectRootFile = "Cargo.toml";
    programs = override formatters (
      {
        nixfmt.enable = true;
        rustfmt = {
          enable = true;
          edition = "2024";
        };
        taplo.enable = true;
      }
      // (lib.optionalAttrs readme {
        mdformat.enable = true;
      })
    );
    settings =
      {
        on-unmatched = "warn";
        excludes = [
          "*.lock"
          ".direnv/*"
          ".envrc"
          ".gitignore"
          "result*/*"
          "target/*"
          "LICENSE"
        ];
      }
      // (lib.optionalAttrs readme {
        formatter = {
          mdformat.includes = [
            "README.tpl"
          ];
        };
      });
  };

  cargoAll = tryOverride "cargoAll" (
    let
      skipFeatures = listFeatures "--skip";
    in
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
    ''
  );

  checks = tryOverride "checks" (
    {
      formatting = (treefmt-nix.lib.evalModule pkgs treefmt).config.build.check self;
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
    // (lib.optionalAttrs readme {
      readme = craneLib.mkCargoDerivation (
        commonArgs
        // {
          inherit cargoArtifacts;
          nativeBuildInputs = [ pkgs.cargo-readme ];
          buildPhaseCargoCommand = "diff README.md <(cargo readme)";
        }
      );
    })
    // (lib.optionalAttrs (builtins.isPath bindgen) {
      bindgen = craneLib.mkCargoDerivation (
        commonArgs
        // {
          inherit cargoArtifacts;
          nativeBuildInputs = [ pkgs.rust-cbindgen ];
          buildPhaseCargoCommand = "diff ${checks.bindgen} <(cbindgen .)";
        }
      );
    })
  );

  devShell = tryOverride "devShell" {
    checks = checks;

    packages = with pkgs; [
      cargo-hack
      cargoAll
    ];
  };

  formatter = (treefmt-nix.lib.evalModule pkgs treefmt).config.build.wrapper;

  outputs =
    {
      packages =
        {
          default = mainArtifact;
        }
        // (lib.optionalAttrs (!binary) {
          deps = cargoArtifacts;
        });

      checks = checks;
      formatter = formatter;
      devShells.default = craneLib.devShell devShell;
    }
    // (lib.optionalAttrs binary {
      apps.default = mkApp { drv = mainArtifact; };
    });
}
