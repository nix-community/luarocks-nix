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
      luaInterpreters = with pkgs; [
        lua5_1
        lua5_2
        lua5_3
        lua5_4
      ];

        mkPackage = luaInterpreter:
            luaInterpreter.pkgs.luarocks;

        mkDevShell = luaInterpreter:
          luaInterpreter.pkgs.luarocks.overrideAttrs(oa: {
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
          default = self.packages.${system}."luarocks-5.1";
        } // (nixpkgs.lib.listToAttrs (builtins.map (luaInterpreter:
            nixpkgs.lib.nameValuePair "luarocks-${luaInterpreter.luaversion}" (mkPackage luaInterpreter))
          luaInterpreters));

        # devShells = {
        #   default = self.devShells.${system}.luarocks-51;
        #   } // (nixpkgs.lib.listToAttrs (builtins.map (luaInterpreter:
        #     nixpkgs.lib.nameValuePair "luarocks-${luaInterpreter.version}" (mkDevShell luaInterpreter)
        #   luaInterpreters)));
      });
}
