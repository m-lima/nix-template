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
        pypolars = {
          description = "A quick setup for running polars in python";
          path = ./template/pypolars;
        };
      };

      lib = {
        python.helper = import ./lib/python/helper.nix;
        rust.helper = import ./lib/rust/helper.nix;
      };
    };
}
