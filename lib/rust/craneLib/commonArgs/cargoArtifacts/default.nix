{
  pkgs,
  craneLib,
  commonArgs,
}:
let
  inherit (pkgs) lib;
in
cargoArtifacts: treefmtCheck: cargoAll: {
  checks = {
    make =
      {
        # If cargo-all with cargo-hack should be used
        hack ? false,
        # If cargo-readme should be used to check the README.md file
        readme ? false,
        # Path to the generated bindgen file, if it should be checked
        bindgen ? null,
      }:
      {
        formatting = treefmtCheck;
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
            buildPhaseCargoCommand = "diff ${bindgen} <(cbindgen .)";
          }
        );
      });

    use = (import ./devShell) { inherit pkgs craneLib cargoAll; };
  };
}
