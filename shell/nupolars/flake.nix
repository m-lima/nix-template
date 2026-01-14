{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          shellHook = ''
            nu -c "plugin add ${pkgs.nushellPlugins.polars}/bin/nu_plugin_polars"
            nu -c "plugin use ${pkgs.nushellPlugins.polars}/bin/nu_plugin_polars"
          '';
          buildInputs = [
            pkgs.nushell
            pkgs.nushellPlugins.polars
          ];
        };
      }
    );
}
