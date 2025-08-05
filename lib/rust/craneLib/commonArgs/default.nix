{
  pkgs,
  craneLib,
}:
let
  inherit (pkgs) lib;
in
commonArgs: {
  mainArgs = {
    make =
      {
        # Useful when using `cc`
        lockRandomSeed ? false,
      }:
      commonArgs
      // (lib.optionalAttrs lockRandomSeed {
        NIX_OUTPATH_USED_AS_RANDOM_SEED = "0123456789";
      });
  };

  cargoArtifacts = {
    make = craneLib.buildDepsOnly commonArgs;
    use = (import ./cargoArtifacts) { inherit pkgs craneLib; };
  };
}
