{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
    helper.url = "github:m-lima/nix-template";
  };

  outputs =
    {
      helper,
      ...
    }@inputs:
    helper.lib.python.helper inputs { };
}
