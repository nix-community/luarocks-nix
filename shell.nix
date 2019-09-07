with import <nixpkgs> {};

let
  # luaEnv = lua5_2.withPackages( ps: [ ps.luarocks-nix ] );
  # luarocksLocalCopy = "$PWD";
in
luarocks-nix.overrideAttrs (oa: {

  name="luarocks-nix-dev";
  src = ./.;

  # Not needed anymore ?
  # shellHook=''
  #   export LUA_PATH="${luarocksLocalCopy}/src/?.lua;''${LUA_PATH:-}"
  #   '';

})
