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
  # cranelib
  toolchains ? fenixPkgs: [ ],

  # commonArgs
  features ? [ ],
  noDefaultFeatures ? false,
  cargoExtraArgs ? "",
  buildInputs ? pkgs: [ ],
  nativeBuildInputs ? pkgs: [ ],
  allowFilesets ? [ ],
  mega ? true,

  # mainArgs
  lockRandomSeed ? false, # Useful when using `cc`

  # devShell
  devPackages ? pkgs: [ ],

  # cargoArtifact
  monolithic ? false, # Useful when cross compiling

  # apps
  binary ? true, # Generate a app entry

  # cargoAll
  skip ? [ "default" ],

  # treeFmt
  formatters ? { },
  fmtSettings ? { },
  fmtExcludes ? [ ],

  hack ? false, # If cargo-all with cargo-hack should be used

  # general
  systemLinker ? false, # Useful when dynamic linking is needed
  readme ? false, # If cargo-readme should be used to check the README.md file
  bindgen ? false, # If cbindgen should be run
  wasm ? false, # If this should generate wasm-bindgen output
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
        fenixPkgs.stable.defaultToolchain
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
      nativeBuildInputs =
        (nativeBuildInputs pkgs)
        ++ (lib.optional readme pkgs.cargo-readme)
        ++ (lib.optional (builtins.isPath bindgen || bindgen) pkgs.rust-cbindgen)
        ++ (lib.optional systemLinker pkgs.llvmPackages.bintools);
      buildInputs = buildInputs pkgs;
      strictDeps = true;
      cargoExtraArgs =
        "--locked ${prepareFeatures features} ${cargoExtraArgs}"
        + (lib.optionalString noDefaultFeatures "--no-default-features");
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
      env = lib.optionalAttrs systemLinker {
        RUSTFLAGS = "-C link-self-contained=-linker";
        RUSTDOCFLAGS = "-C link-self-contained=-linker";
      };
    }
    // (
      lib.optionalAttrs mega
      && !wasm {
        CARGO_PROFILE = "mega";
        CARGO_BUILD_RUSTFLAGS = "-C target-cpu=native -C prefer-dynamic=no";
      }
    )
  );

  mainArgs = tryOverride "mainArgs" (
    commonArgs
    // (lib.optionalAttrs lockRandomSeed {
      NIX_OUTPATH_USED_AS_RANDOM_SEED = "0123456789";
    })
  );

  cargoArtifacts =
    if monolithic then
      if builtins.hasAttr "cargoArtifacts" overrides then
        builtins.abort "Cannot override `cargoArtifacts` when building a monolithic project"
      else
        ""
    else
      tryOverride "cargoArtifacts" (craneLib.buildDepsOnly commonArgs);

  mainArtifact = tryOverride "mainArtifact" (
    craneLib.buildPackage (
      mainArgs
      // {
        inherit cargoArtifacts;
      }
      // (lib.optionalAttrs (builtins.isPath bindgen || bindgen) {
        postInstall = ''
          mkdir -p $out/include
          cbindgen . --output $out/include/${
            (craneLib.crateNameFromCargoToml { cargoToml = "${root}/Cargo.toml"; }).pname
          }.h
        '';
      })
    )
  );

  wasmArgs = tryOverride "wasmArgs" (
    builtins.removeAttrs mainArgs [
      "env"
      "CARGO_PROFILE"
      "CARGO_BUILD_RUSTFLAGS"
    ]
  );

  wasmArtifact = tryOverride "wasmArtifact" (
    craneLib.mkCargoDerivation (
      wasmArgs
      // {
        inherit cargoArtifacts;
        buildPhaseCargoCommand = "wasm-bindgen target/wasm32-unknown-unknown/release/passer.wasm --out-dir pkg";
        installPhaseCommand = "cp -r pkg $out";
      }
    )
  );

  treefmt = tryOverride "treefmt" {
    projectRootFile = "flake.nix";
    programs = override formatters (
      {
        nixfmt.enable = true;
        rustfmt = {
          enable = true;
          edition = "2024";
        };
        taplo.enable = true;
        yamlfmt.enable = true;
      }
      // (lib.optionalAttrs readme {
        mdformat.enable = true;
      })
    );
    settings = override fmtSettings (
      {
        on-unmatched = "warn";
        excludes = [
          "**/.direnv/*"
          "**/.envrc"
          "**/.gitignore"
          "*.lock"
          ".direnv/*"
          ".envrc"
          ".gitignore"
          "LICENSE"
          "result*/*"
          "target/*"
        ]
        ++ fmtExcludes
        ++ (lib.optional readme "README.md");
      }
      // (lib.optionalAttrs readme {
        formatter = {
          mdformat.includes = [
            "README.tpl"
          ];
        };
      })
    );
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
      echo "[34mGenerating docs[m" && \
      cargo $nightly doc --workspace --no-deps --all-features $@ && \
      if [ "$run" ]; then
        echo "[34mRunning[m" && \
        cargo $nightly run $@
      fi
    ''
  );

  checks = tryOverride "checks" (
    let
      checkCommonArgs =
        if mega then
          commonArgs
          // {
            CARGO_PROFILE = builtins.replaceStrings [ "mega" ] [ "" ] commonArgs.CARGO_PROFILE;
            CARGO_BUILD_RUSTFLAGS =
              builtins.replaceStrings [ "-C target-cpu=native -C prefer-dynamic=no" ] [ "" ]
                commonArgs.CARGO_BUILD_RUSTFLAGS;
          }
        else
          commonArgs;
      checkCargoArtifacts = if monolithic then mainArtifact else craneLib.buildDepsOnly checkCommonArgs;
    in
    {
      formatting = (treefmt-nix.lib.evalModule pkgs treefmt).config.build.check self;
    }
    // (
      if hack then
        {
          hack = craneLib.mkCargoDerivation (
            checkCommonArgs
            // {
              cargoArtifacts = checkCargoArtifacts;
              buildPhaseCargoCommand = "cargo all";
              nativeBuildInputs = (checkCommonArgs.nativeBuildInputs or [ ]) ++ [
                pkgs.cargo-hack
                cargoAll
              ];
            }
          );
        }
      else
        {
          clippy = craneLib.cargoClippy (
            checkCommonArgs
            // {
              cargoArtifacts = checkCargoArtifacts;
              cargoClippyExtraArgs = "-- -D warnings -W clippy::pedantic";
            }
          );

          clippy-tests = craneLib.cargoClippy (
            checkCommonArgs
            // {
              cargoArtifacts = checkCargoArtifacts;
              pnameSuffix = "-clippy-tests";
              cargoClippyExtraArgs = "--tests -- -D warnings -W clippy::pedantic";
            }
          );

          clippy-examples = craneLib.cargoClippy (
            checkCommonArgs
            // {
              cargoArtifacts = checkCargoArtifacts;
              pnameSuffix = "-clippy-examples";
              cargoClippyExtraArgs = "--examples -- -D warnings -W clippy::pedantic";
            }
          );

          docs = craneLib.cargoDoc (
            checkCommonArgs
            // {
              cargoArtifacts = checkCargoArtifacts;
              cargoDocExtraArgs = "--no-deps --all-features";
            }
          );

          tests = craneLib.cargoTest (
            checkCommonArgs
            // {
              cargoArtifacts = checkCargoArtifacts;
            }
          );
        }
    )
    // (lib.optionalAttrs readme {
      readme = craneLib.mkCargoDerivation (
        checkCommonArgs
        // {
          cargoArtifacts = checkCargoArtifacts;
          buildPhaseCargoCommand = "diff README.md <(cargo readme)";
        }
      );
    })
    // (lib.optionalAttrs (builtins.isPath bindgen) {
      bindgen = craneLib.mkCargoDerivation (
        checkCommonArgs
        // {
          cargoArtifacts = checkCargoArtifacts;
          buildPhaseCargoCommand = "diff ${bindgen} <(cbindgen .)";
        }
      );
    })
  );

  devShell = tryOverride "devShell" (
    mainArgs
    // {
      inherit checks;

      packages =
        with pkgs;
        [
          (pkgs.writeShellScriptBin "cargo-docsrs" ''
            PATH="${
              fenix.packages.${system}.minimal.toolchain
            }/bin:$PATH" RUSTDOCFLAGS='--cfg docsrs' cargo doc --all-features --no-deps
          '')
          cargo-hack
          cargo-outdated
          cargoAll
        ]
        ++ (devPackages pkgs);
    }
  );

  formatter = (treefmt-nix.lib.evalModule pkgs treefmt).config.build.wrapper;

  outputs = {
    packages.default = mainArtifact;
    checks = checks;
    formatter = formatter;
    devShells.default = craneLib.devShell devShell;
  }
  // (lib.optionalAttrs binary {
    apps.default = mkApp { drv = mainArtifact; };
  })
  // (lib.optionalAttrs wasm {
    packages.wasm = craneLib.buildPackage (mainArgs // { inherit cargoArtifacts; });
  });
}
