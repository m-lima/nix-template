{
  nixpkgs,
  crane,
  fenix,
  treefmt-nix,
  ...
}:
{
  system,
  root,
}:
let
  pkgs = nixpkgs.legacyPackages.${system};
  inherit (pkgs) stdenv lib;

  listFeatures =
    arg: list:
    lib.optionalString (builtins.length list > 0) "${arg} ${builtins.concatStringsSep "," list}";
in
{
  craneLib =
    let
      make =
        {
          toolchains ? fenixPkgs: [ ],
        }:
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
        );

      default = use (make { });

      use = craneLib: {
        commonArgs =
          let
            make =
              {
                features ? [ ],
                cargoExtraArgs ? "",
                buildInputs ? [ ],
                nativeBuildInputs ? [ ],
                allowFilesets ? [ ],
                mega ? true,
              }:
              let
                prepareFeatures = listFeatures "--features";
              in
              {
                inherit nativeBuildInputs buildInputs;
                strictDeps = true;
                cargoExtraArgs = "--locked ${prepareFeatures features} ${cargoExtraArgs}";
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

            default = use (make { });

            use = commonArgs: {
              mainArgs = {
                make =
                  {
                    lockRandomSeed ? false,
                  }:
                  commonArgs
                  // (lib.optionalAttrs lockRandomSeed {
                    NIX_OUTPATH_USED_AS_RANDOM_SEED = "0123456789";
                  });
              };

              cargoArtifacts =
                let
                  make = craneLib.buildDepsOnly commonArgs;
                  default = use make;
                in
                {
                  inherit make use default;
                };
            };
          in
          {
            inherit make use default;
          };
      };
    in
    {
      inherit make default use;
    };

  treefmt =
    let
      make =
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
      default = use (make { });
      use = treefmt: {
        formatter = {
          make = treefmt.wrapper;
        };
        check = { };
      };
    in
    {
      inherit make default use;
    };
}

#   withCraneLib =
#     craneLib:
#     let
#       mkCommonArgs =
#         {
#           features ? [ ],
#           cargoExtraArgs ? "",
#           buildInputs ? [ ],
#           nativeBuildInputs ? [ ],
#           allowFilesets ? [ ],
#           mega ? true,
#         }:
#         let
#           prepareFeatures = listFeatures "--features";
#         in
#         {
#           inherit nativeBuildInputs buildInputs;
#           strictDeps = true;
#           cargoExtraArgs = "--locked ${prepareFeatures features} ${cargoExtraArgs}";
#           src = lib.fileset.toSource {
#             inherit root;
#             fileset = lib.fileset.unions (
#               [
#                 (craneLib.fileset.commonCargoSources root)
#               ]
#               ++ allowFilesets
#             );
#           };
#         }
#         // (lib.optionalAttrs mega {
#           CARGO_PROFILE = "mega";
#           CARGO_BUILD_RUSTFLAGS = "-C target-cpu=native -C prefer-dynamic=no";
#         });
#
#       withCommonArgs =
#         commonArgs:
#         let
#           mkMainArgs =
#             {
#               lockRandomSeed ? false,
#             }:
#             commonArgs
#             // (lib.optionalAttrs lockRandomSeed {
#               NIX_OUTPATH_USED_AS_RANDOM_SEED = "0123456789";
#             });
#
#           mkCargoArtifacts = craneLib.buildDepsOnly commonArgs;
#
#           withCargoArtifacts = cargoArtifacts: {
#             mkArtifacts =
#               {
#                 args,
#               }:
#               craneLib.buildPackage (
#                 args
#                 // {
#                   inherit cargoArtifacts;
#                 }
#               );
#           };
#         in
#         {
#           inherit mkMainArgs mkCargoArtifacts withCargoArtifacts;
#         };
#     in
#     {
#       inherit mkCommonArgs withCommonArgs;
#       withDefaultCommonArgs = withCommonArgs (mkCommonArgs { });
#     };
# in
# {
#   inherit mkCraneLib withCraneLib;
#   withDefaultCraneLib = withCraneLib (mkCraneLib { });
#
#   mkTreefmt =
#     {
#       programs ? default: default,
#       settings ? default: default,
#     }:
#     {
#       programs = programs {
#         nixfmt.enable = true;
#         rustfmt = {
#           enable = true;
#           edition = "2024";
#         };
#         taplo.enable = true;
#       };
#       settings = settings {
#         excludes = [
#           "*.lock"
#           ".direnv/*"
#           ".envrc"
#           ".gitignore"
#           "result*/*"
#           "target/*"
#           "LICENSE"
#         ];
#       };
#     };
#
#   withTreefmt = treefmt: {
#     mkFormatter = treefmt.wrapper;
#   };
#
#   mkCargoAll =
#     {
#       skip ? [ "default" ],
#     }:
#     let
#       skipFeatures = listFeatures "--skip";
#     in
#     pkgs.writeShellScriptBin "cargo-all" ''
#       shift
#
#       skip="${skipFeatures skip}"
#
#       while (( $# > 0 )); do
#         case "$1" in
#           nightly)
#             nightly='+nightly' ;;
#           run|r)
#             run=1 ;;
#           clean|c)
#             clean=1 ;;
#           skip|s)
#             shift
#             skip="--skip $1"
#             ;;
#         esac
#         shift
#       done
#
#       if [ $clean ]; then
#         echo "[34mCleaning[m" && \
#         cargo clean
#       fi && \
#       echo "[34mFormatting[m" && \
#       cargo $nightly fmt --all && \
#       echo "[34mChecking main[m" && \
#       cargo $nightly hack --feature-powerset $skip check --workspace $@ && \
#       echo "[34mChecking examples[m" && \
#       cargo $nightly hack --feature-powerset $skip check --workspace --examples $@ && \
#       echo "[34mChecking tests[m" && \
#       cargo $nightly hack --feature-powerset $skip check --workspace --tests $@ && \
#       echo "[34mLinting main[m" && \
#       cargo $nightly hack --feature-powerset $skip clippy --workspace $@ && \
#       echo "[34mLinting tests[m" && \
#       cargo $nightly hack --feature-powerset $skip clippy --workspace --tests $@ && \
#       echo "[34mLinting examples[m" && \
#       cargo $nightly hack --feature-powerset $skip clippy --workspace --examples $@ && \
#       echo "[34mTesting main[m" && \
#       cargo $nightly hack --feature-powerset $skip test --workspace $@ && \
#       if [ "$run" ]; then
#         echo "[34mRunning[m" && \
#         cargo $nightly run $@
#       fi
#     '';
#
#   mkApp =
#     {
#       drv,
#       name ? drv.pname or drv.name,
#       exePath ? drv.passthru.exePath or "/bin/${name}",
#     }:
#     {
#       type = "app";
#       program = "${drv}${exePath}";
#     };
# }
#
# #   mkTreefmt =
# #     {
# #       config ? mkTreefmtConfig { },
# #     }:
# #     (treefmt-nix.lib.evalModule pkgs config).config.build;
# #
# #   mkChecks =
# #     {
# #       outputs,
# #       treefmt ? mkTreefmt { },
# #       commonArgs ? mkCommonArgs { inherit craneLib; },
# #       cargoArtifacts ? mkCargoArtifacts {
# #         inherit craneLib commonArgs;
# #       },
# #       hack ? null,
# #       extraChecks ? { },
# #     }:
# #     {
# #       formatting = treefmt.check outputs;
# #     }
# #     // (
# #       if builtins.isAttrs hack then
# #         {
# #           hack = craneLib.mkCargoDerivation (
# #             commonArgs
# #             // {
# #               inherit cargoArtifacts;
# #               buildPhaseCargoCommand = "cargo all";
# #               nativeBuildInputs = (commonArgs.nativeBuildInputs or [ ]) ++ [
# #                 pkgs.cargo-hack
# #                 hack
# #               ];
# #             }
# #           );
# #         }
# #       else
# #         {
# #           clippy = craneLib.cargoClippy (
# #             commonArgs
# #             // {
# #               inherit cargoArtifacts;
# #               cargoClippyExtraArgs = "-- -D warnings -W clippy::pedantic";
# #             }
# #           );
# #
# #           clippy-tests = craneLib.cargoClippy (
# #             commonArgs
# #             // {
# #               inherit cargoArtifacts;
# #               pnameSuffix = "-clippy-tests";
# #               cargoClippyExtraArgs = "--tests -- -D warnings -W clippy::pedantic";
# #             }
# #           );
# #
# #           clippy-examples = craneLib.cargoClippy (
# #             commonArgs
# #             // {
# #               inherit cargoArtifacts;
# #               pnameSuffix = "-clippy-examples";
# #               cargoClippyExtraArgs = "--examples -- -D warnings -W clippy::pedantic";
# #             }
# #           );
# #
# #           docs = craneLib.cargoDoc (
# #             commonArgs
# #             // {
# #               inherit cargoArtifacts;
# #             }
# #           );
# #
# #           tests = craneLib.cargoTest (
# #             commonArgs
# #             // {
# #               inherit cargoArtifacts;
# #             }
# #           );
# #         }
# #     )
# #     // (lib.optionalAttrs (builtins.hasAttr "readme" extraChecks && extraChecks.readme) {
# #       readme = craneLib.mkCargoDerivation (
# #         commonArgs
# #         // {
# #           inherit cargoArtifacts;
# #           nativeBuildInputs = [ pkgs.cargo-readme ];
# #           buildPhaseCargoCommand = "diff README.md <(cargo readme)";
# #         }
# #       );
# #     })
# #     // (lib.optionalAttrs
# #       (builtins.hasAttr "bindgen" extraChecks && (builtins.isPath extraChecks.bindgen))
# #       {
# #         bindgen = craneLib.mkCargoDerivation (
# #           commonArgs
# #           // {
# #             inherit cargoArtifacts;
# #             nativeBuildInputs = [ pkgs.rust-cbindgen ];
# #             buildPhaseCargoCommand = "diff ${extraChecks.bindgen} <(cbindgen .)";
# #           }
# #         );
# #       }
# #     );
# #
# #   mkDevShells =
# #     {
# #       checks ? mkChecks,
# #       cargoAll ? mkCargoAll { },
# #     }:
# #     {
# #       default = craneLib.devShell {
# #         checks = checks;
# #
# #         packages = with pkgs; [
# #           cargo-hack
# #           cargoAll
# #         ];
# #       };
# #     };
# #
# #   mkApps =
# #     {
# #       mainArtifact ? mkMainArtifacts { },
# #     }:
# #     {
# #       default = mkApp { drv = mainArtifact; };
# #     };
# #
# #   mkPackages =
# #     {
# #       mainArtifact ? mkMainArtifacts { },
# #     }:
# #     {
# #       default = mainArtifact;
# #     };
# # in
# # {
# #   inherit
# #     prepareFeatures
# #     mkCommonArgs
# #     mkMainArgs
# #     mkCargoArtifacts
# #     mkMainArtifacts
# #     mkCargoAll
# #     mkTreefmtConfig
# #     mkTreefmt
# #     mkFormatter
# #     mkChecks
# #     mkDevShells
# #     mkApp
# #     mkApps
# #     mkPackages
# #     ;
# # }
