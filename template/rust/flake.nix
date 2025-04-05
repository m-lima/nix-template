{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane.url = "github:ipetkov/crane";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
    rust-helper.url = "github:m-lima/nix-template";
  };

  outputs =
    {
      rust-helper,
      ...
    }@inputs:
    rust-helper.lib.rust.helper inputs { } ./. "rust_template";
}
