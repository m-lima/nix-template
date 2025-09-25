{
  nixpkgs,
  flake-utils,
  treefmt-nix,
  ...
}:
{
  fmts ? [ ],
  buildInputs ? _: [ ],
}:
flake-utils.lib.eachDefaultSystem (
  system:
  let
    pkgs = nixpkgs.legacyPackages.${system};
    inherit (pkgs) lib;
    treefmt =
      (treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt.enable = true;
          mypy.enable = true;
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
            ".mypy_cache/*"
            "LICENSE"
            "result*/*"
          ];
        };
      }).config.build;
  in
  {
    formatter = treefmt.wrapper;
    devShells.default = pkgs.mkShell {
      buildInputs = [
        pkgs.python312
      ]
      ++ buildInputs pkgs;
    };
  }
)
