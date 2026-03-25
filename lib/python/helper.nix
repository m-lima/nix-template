{
  nixpkgs,
  flake-utils,
  treefmt-nix,
  ...
}:
{
  python ? null,
  pythonPackages ? null,

  # Dependencies
  buildInputs ? pkgs: [ ],
  nativeBuildInputs ? pkgs: [ ],
  devPackages ? pkgs: [ ],

  # treeFmt
  formatters ? { },
  fmtSettings ? { },
  fmtExcludes ? [ ],

  # General
  overrides ? { },
}:
flake-utils.lib.eachDefaultSystem (
  system:
  let
    pkgs = nixpkgs.legacyPackages.${system};
    util = import ../util.nix;
    inherit (util) override;
    tryOverride = util.tryOverride overrides;

    fmtConfig = tryOverride "treefmt" {
      projectRootFile = "flake.nix";
      programs = override formatters {
        nixfmt.enable = true;
        mypy.enable = true;
      };
      settings = override fmtSettings (util.fmtSettings [ ".mypy_cache/*" ] fmtExcludes);
    };

    treefmt = (treefmt-nix.lib.evalModule pkgs fmtConfig).config.build;

    pythonPkg = override python pkgs.python3;
    pyPkgs =
      if builtins.isNull pythonPackages then pythonPkg else pythonPkg.withPackages pythonPackages;
  in
  {
    formatter = treefmt.wrapper;
    devShells.default = pkgs.mkShell {
      packages = [ pyPkgs ];
      buildInputs = buildInputs pkgs;
      nativeBuildInputs = nativeBuildInputs pkgs;

      shellHook = ''
        SOURCE_DATE_EPOCH=$(date +%s)
        VENV=.venv

        if test ! -d $VENV; then
          python3 -m venv $VENV
        fi
        source ./$VENV/bin/activate
        export PYTHONPATH=$(pwd)/$VENV/${pythonPkg.sitePackages}/:$PYTHONPATH
        pip install -r requirements.txt
      '';

      postShellHook = ''
        ln -sf ${pythonPkg.sitePackages}/* ./.venv/${pythonPkg.sitePackages}
      '';
    };
  }
)
