{
  outputs = {...}: {
    templates = {
      rust = {
        description = "Rust scaffold";
        path = ./template/rust;
      };
    };

    lib = {
      rust.helper = import ./lib/rust/helper.nix;
    };
  };
}
