{
  outputs = {...}: {
    templates = {
      rust = {
        description = "Rust scaffold";
        path = ./rust;
      };
    };

    lib = {
      rust.helper = import ./helper/rust;
    };
  };
}
