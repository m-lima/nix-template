{
  self,
  nixpkgs,
  flake-utils,
  treefmt-nix,
  gomod2nix,
  ...
}:
root:
{
  pname,
  version,
  src ? root,
  pwd ? root,

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

    go2nix = gomod2nix.legacyPackages.${system};

    fmtConfig = tryOverride "treefmt" {
      projectRootFile = "flake.nix";
      programs = override formatters {
        nixfmt.enable = true;
        gofumpt.enable = true;
        goimports.enable = true;
        yamlfmt.enable = true;
      };
      settings = override fmtSettings (util.fmtSettings [ "gomod2nix.toml" ] fmtExcludes);
    };

    treefmt = (treefmt-nix.lib.evalModule pkgs fmtConfig).config.build;
  in
  {
    packages.default = tryOverride "package" (
      go2nix.buildGoApplication (
        tryOverride "packageArgs" {
          inherit
            pname
            version
            src
            pwd
            ;

          buildInputs = buildInputs pkgs;
          nativeBuildInputs = nativeBuildInputs pkgs;
        }
      )
    );
    checks = {
      formatting = treefmt.check self;
      lint = go2nix.buildGoApplication {
        inherit src pwd;
        name = "lint";
        dontBuild = true;
        doCheck = true;
        nativeBuildInputs = [
          pkgs.golangci-lint
          pkgs.writableTmpDirAsHomeHook
        ];
        checkPhase = "golangci-lint run";
        installPhase = "mkdir $out";
      };
    };
    formatter = treefmt.wrapper;
    devShells.default = pkgs.mkShell {
      packages = devPackages pkgs;
      buildInputs = [
        go2nix.gomod2nix
        pkgs.go
        pkgs.gopls
        pkgs.gofumpt
        pkgs.golangci-lint
        pkgs.golangci-lint-langserver
      ];
    };
  }
)
