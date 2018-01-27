# suse the correct nixpkgs !!
# { pkgs ? import <nixpkgs> }:

with import <nixpkgs> {};

let
  luaEnv = lua5_2.withPackages( ps: [ ps.luarocks-nix ] );
  luarocksLocalCopy = "/home/teto/luarocks/";
in
stdenv.mkDerivation {

  name="toto";
  buildInputs =  [ git luaEnv nix-prefetch-scripts ];

  shellHook=''
    export LUA_PATH="${luarocksLocalCopy}/src/?.lua;''${LUA_PATH:-}"
    '';

}
