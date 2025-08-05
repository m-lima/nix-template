{
  pkgs,
  root,
  listFeatures,
}:
let
  inherit (pkgs) lib;
in
craneLib: {
  commonArgs = {
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

    use = (import ./commonArgs) { inherit pkgs craneLib; };
  };
}
