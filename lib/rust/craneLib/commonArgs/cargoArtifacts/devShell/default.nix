{
  pkgs,
  craneLib,
  cargoAll,
}:
checks: {
  make = craneLib.devShell {
    inherit checks;

    packages = with pkgs; [
      cargoAll
      cargo-hack
    ];
  };
}
