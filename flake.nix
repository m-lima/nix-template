{
  outputs =
    { ... }:
    {
      templates = {
        python = {
          description = "Python scaffold";
          path = ./template/python;
        };
        rust = {
          description = "Rust scaffold";
          path = ./template/rust;
        };
      };

      lib = {
        python.helper = import ./lib/python/helper.nix;
        rust.helper = import ./lib/rust/helper.nix;
      };
    };
}
