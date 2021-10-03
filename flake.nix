{
  description = "Luarocks flake";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachSystem ["x86_64-linux"] (system: let
      pkgs = import nixpkgs { inherit system; };
    in {


    packages.luarocks = pkgs.luarocks;

    defaultPackage = self.packages."${system}".luarocks.overrideAttrs(oa: {
      nativeBuildInputs = [
        pkgs.lua51Packages.luacheck

      ];


    });
    # devShell = pkgs.mkShell {
    #   name = "luarocks-dev";
    #   buildInputs = [
    #     self.packages."${system}".luarocks.inputAttrs
    #     pkgs.sumneko-lua-language-server
    #   ];
    # };
  });
}
