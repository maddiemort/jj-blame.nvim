{
  description = "jj-blame.nvim";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }: let
    pkgsFor = system:
      import nixpkgs {
        inherit system;
        overlays = [];
      };

    supportedSystems = with flake-utils.lib.system; [
      aarch64-darwin
      aarch64-linux
      x86_64-darwin
      x86_64-linux
    ];

    inherit (flake-utils.lib) eachSystem;
  in
    eachSystem supportedSystems (system: let
      pkgs = pkgsFor system;
    in {
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          alejandra
          convco
        ];
      };

      formatter = pkgs.alejandra;
    });
}
