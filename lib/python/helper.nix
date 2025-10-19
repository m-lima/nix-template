{
  nixpkgs,
  flake-utils,
  treefmt-nix,
  ...
}:
{
  fmts ? [ ],
  buildInputs ? _: [ ],
  pythonPkgs ? _: [ ],
}:
flake-utils.lib.eachDefaultSystem (
  system:
  let
    pkgs = nixpkgs.legacyPackages.${system};
    inherit (pkgs) lib;
    python = pkgs.python3.withPackages (
      ps:
      (pythonPkgs ps)
      ++ [
        ps.venvShellHook
      ]
    );
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
      packages = [ python ];
      buildInputs = buildInputs pkgs;

      shellHook = ''
        SOURCE_DATE_EPOCH=$(date +%s)
        VENV=.venv

        if test ! -d $VENV; then
          python3 -m venv $VENV
        fi
        source ./$VENV/bin/activate
        export PYTHONPATH=$(pwd)/$VENV/${python.sitePackages}/:$PYTHONPATH
        pip install -r requirements.txt
      '';

      postShellHook = ''
        ln -sf ${python.sitePackages}/* ./.venv/${python.sitePackages}
      '';
    };
  }
)
