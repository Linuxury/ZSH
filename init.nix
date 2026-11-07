# For Nix builds: joins conf.d/*.zsh in name order into one string
# (programs.zsh.initContent / programs.zsh.interactiveShellInit).
#   import "${inputs.zsh}/init.nix" { inherit lib; }
{ lib }:
let dir = ./conf.d; in
lib.concatMapStrings (n: builtins.readFile (dir + "/${n}"))
  (lib.attrNames (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".zsh" n) (builtins.readDir dir)))
