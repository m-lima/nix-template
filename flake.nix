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
          description = "Python with polars and vim notebook";
          path = ./template/pypolars;
        };
        shell-pypolars = {
          description = "A quick setup for running polars in python";
          path = ./template/nupolars;
        };
        shell-nupolars = {
          description = "A quick setup for running polars in nushell";
          path = ./template/nupolars;
        };
      };

      lib = {
        python.helper = import ./lib/python/helper.nix;
        rust.helper = import ./lib/rust/helper.nix;
      };
    };
}
