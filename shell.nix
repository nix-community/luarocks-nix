# suse the correct nixpkgs !!
# { pkgs ? import <nixpkgs> }:

with import <nixpkgs> {};

let
  luaEnv = lua5_2.withPackages( ps: [ ps.luarocks-nix ] );
  luarocksLocalCopy = "$PWD";
in
luarocks-nix.overrideAttrs (oa: {

  # name="toto";
  # buildInputs =  [ git luaEnv nix-prefetch-scripts ];
  src = ./.;

  # Not needed anymore ?
  # shellHook=''
  #   export LUA_PATH="${luarocksLocalCopy}/src/?.lua;''${LUA_PATH:-}"
  #   '';

})
