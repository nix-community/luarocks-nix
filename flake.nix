{
  description = "Luarocks flake";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachSystem ["x86_64-linux"] (system: let
      pkgs = import nixpkgs { inherit system; };
      mkDevShell = luaVersion:
        pkgs.mkShell {
          name = "luarocks-dev";
          buildInputs = [

            # TODO restore
            # self.packages."${system}".luarocks.inputAttrs

            pkgs.sumneko-lua-language-server
          ];
        };

    in {

    packages.luarocks = pkgs.luarocks;

    defaultPackage = self.packages.${system}.luarocks.overrideAttrs(oa: {
      nativeBuildInputs = [
        pkgs.lua51Packages.luacheck
      ];
    });

    devShells = {
      luarocks-51 = mkDevShell "51";
      luarocks-52 = mkDevShell "52";
      luarocks-53 = mkDevShell "53";
      luarocks-54 = mkDevShell "54";
    };
  });
}
