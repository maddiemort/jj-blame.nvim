{
  description = "jj-blame.nvim";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
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
      packages = rec {
        default = jj-blame-nvim;
        jj-blame-nvim = let
          rev = self.shortRev or self.dirtyShortRev or "0000000";
        in
          pkgs.vimUtils.buildVimPlugin {
            pname = "jj-blame.nvim";
            version = "0.1.1-dev.${rev}";
            src = pkgs.lib.cleanSource ./.;
          };
      };

      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          alejandra
          convco
        ];
      };

      formatter = pkgs.alejandra;
    });
}
