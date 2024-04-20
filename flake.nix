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
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        luaInterpreters = with pkgs; [
          lua5_1
          lua5_2
          lua5_3
          lua5_4
        ];

        mkPackage = luaInterpreter:
          luaInterpreter.pkgs.luarocks-nix.overrideAttrs (old: {
            version = "dev";
            src = self;
          });

        mkDevShell = luaInterpreter:
          luaInterpreter.pkgs.luarocks.overrideAttrs (oa: {
            name = "luarocks-dev";
            buildInputs = oa.buildInputs ++ [
              # TODO restore
              pkgs.sumneko-lua-language-server
              pkgs.luajitPackages.luacheck
              pkgs.nurl
            ];
          });

      in
      {

        packages = {
          default = self.packages.${system}."luarocks-51";
        } // (nixpkgs.lib.listToAttrs (builtins.map
          (luaInterpreter:
            let
              versions = nixpkgs.lib.splitVersion luaInterpreter.luaversion;
              pkgName = "luarocks-${builtins.elemAt versions 0}${builtins.elemAt versions 1}";
            in
            nixpkgs.lib.nameValuePair pkgName (mkPackage luaInterpreter)
          )
          luaInterpreters));

        # devShells = {
        #   default = self.devShells.${system}.luarocks-51;
        #   } // (nixpkgs.lib.listToAttrs (builtins.map (luaInterpreter:
        #     nixpkgs.lib.nameValuePair "luarocks-${luaInterpreter.version}" (mkDevShell luaInterpreter)
        #   luaInterpreters)));
      });
}
