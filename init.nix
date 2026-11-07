# For Nix builds: joins conf.d/<folder>/*.zsh (folders by name, then files by
# name, the same order zshrc loads them) into one string
# (programs.zsh.initContent / programs.zsh.interactiveShellInit).
#   import "${inputs.zsh}/init.nix" { inherit lib; }
{ lib }:
let
  dir = ./conf.d;
  names = d: t: lib.attrNames (lib.filterAttrs (_: v: v == t) (builtins.readDir d));
  zshIn = d: map (n: d + "/${n}") (lib.filter (lib.hasSuffix ".zsh") (names d "regular"));
in
lib.concatMapStrings builtins.readFile
  (lib.concatMap (f: zshIn (dir + "/${f}")) (names dir "directory"))
