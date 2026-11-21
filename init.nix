# ===========================================================================
# init.nix — the zsh files from conf.d/ joined into one string, for Nix builds
#
# Used as a value, not run on its own:
#   import "${inputs.zsh}/init.nix" { inherit lib; }
# lib is nixpkgs' lib, passed in by the caller. The result is the text of every
# conf.d/<folder>/*.zsh file, concatenated. It is used by:
#   programs.zsh.initContent            NixOS and Home Manager configurations
#   programs.zsh.interactiveShellInit   NixOS (server-shell module)
# Plain zsh installs read zshrc instead.
# ===========================================================================
{ lib }:
let
  # The conf.d folder next to this file. Nix copies it into the store.
  dir = ./conf.d;
  # Names in folder d whose type is t ("regular", "directory", "symlink").
  # builtins.readDir lists dotfiles too; attrNames returns them sorted.
  names = d: t: lib.attrNames (lib.filterAttrs (_: v: v == t) (builtins.readDir d));
  # Paths of the *.zsh regular files in folder d. Symlinked files are not
  # included here, though zshrc's glob does load them. Hidden *.zsh files are
  # included here, though zshrc's glob skips them.
  zshIn = d: map (n: d + "/${n}") (lib.filter (lib.hasSuffix ".zsh") (names d "regular"));
in
# Read each file and concatenate them: folders by name, then files by name,
# the same order zshrc sources them. No separator is added, so each file must
# end with a newline.
lib.concatMapStrings builtins.readFile
  (lib.concatMap (f: zshIn (dir + "/${f}")) (names dir "directory"))
