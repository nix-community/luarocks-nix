{
  description = "Luarocks flake";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        mkPackage = luaVersion:
            pkgs."lua${luaVersion}Packages".luarocks;

        mkDevShell = luaVersion:
          pkgs."lua${luaVersion}Packages".luarocks.overrideAttrs(oa: {
            name = "luarocks-dev";
            buildInputs = oa.buildInputs ++ [

              # TODO restore

              pkgs.sumneko-lua-language-server
              pkgs.lua51Packages.luacheck
            ];
          });

      in
      {

        packages = {
          default = self.packages.${system}.luarocks-51;
          luarocks-51 = mkPackage "51";
          luarocks-52 = mkPackage "52";
        };

        devShells = {
          default = self.devShells.${system}.luarocks-51;
          luarocks-51 = mkDevShell "51";
          luarocks-52 = mkDevShell "52";
          luarocks-53 = mkDevShell "53";
          luarocks-54 = mkDevShell "54";
        };
      });
}
