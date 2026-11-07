# ZSH

My zsh setup, split into small files. It is written for NixOS (flakes, Home Manager),
and the `nru` update tool only makes sense there. The rest is plain zsh.

## What is in here

| Path | What it holds |
| --- | --- |
| `zshrc` | Entry point. Sources `conf.d/*.zsh` in name order. |
| `init.nix` | The same files joined into one string, for Nix builds. |
| `conf.d/00-env.zsh` | PATH wrappers, `EDITOR`, `NIXOS_CONFIG`, API key variables |
| `conf.d/10-banner.zsh` | fastfetch on startup (random image from `~/Pictures/Fastfetch`) |
| `conf.d/20-completion.zsh` | Completion styling |
| `conf.d/30-` to `42-nru-*.zsh` | `nru`, the NixOS update tool, in 13 parts |
| `conf.d/80-shortcuts.zsh` | Short commands, listed below |
| `conf.d/91-` to `93-*.zsh` | `hytale`, `opencode`, `ctrl-check` |
| `conf.d/99-local.zsh` | Loads `~/.env.local` if it exists (keys and secrets, not tracked) |
| `starship/` | Starship prompt config and colour template |
| `fastfetch/` | fastfetch config (the images live in the Assets repo) |

Load order is the file name, so a new file only needs the right number.

## Install

On a plain zsh system:

```sh
git clone https://github.com/Linuxury/ZSH.git ~/.zsh
echo 'source ~/.zsh/zshrc' >> ~/.zshrc
```

On NixOS, add it as a flake input and read it at build time:

```nix
inputs.zsh = { url = "github:Linuxury/ZSH"; flake = false; };

# in a Home Manager or NixOS module:
programs.zsh.initContent = import "${inputs.zsh}/init.nix" { inherit lib; };
```

`nru` re-sources `$ZSH_HOME/zshrc` (default `~/.zsh/zshrc`) after pulling, so keep a
checkout there on hosts where you run it.

## Shortcuts

Defined in this repo:

| Shortcut | Command | Description |
| --- | --- | --- |
| `nru` | function | Pull, update flake inputs and tracked packages, rebuild, summarise |
| `nr` | `nixos-rebuild switch --flake …#<host>` | Rebuild and switch |
| `nrt` | `nixos-rebuild test --flake …#<host>` | Activate without touching the boot entry |
| `nrr` | `sudo nixos-rebuild switch --rollback` | Roll back to the previous generation |
| `ngc` | `sudo nix-collect-garbage --delete-older-than 30d` | Remove generations older than 30 days |
| `ngens` | `sudo nix-env --list-generations --profile /nix/var/nix/profiles/system` | List system generations |
| `add` | `git add .` | Stage everything |
| `clone` | `git clone` | Clone a repository |
| `cloned` | `git clone --depth=1` | Shallow clone |
| `commit` | `git commit -m` | Commit with a message |
| `pull` | `git pull` | Pull |
| `push` | `git push` | Push |
| `pushm` | `git push -u origin main` | Push and set upstream to main |
| `pusho` | `git push origin` | Push to a named branch: `pusho <branch>` |
| `gpush` | function | `git add .`, `git commit -m "<message>"`, `git push`: `gpush <message>` |
| `hytale` | function | Launch Hytale with the gamepad profile, restore it on exit |
| `opencode` | function | Run OpenCode with the OpenRouter key from agenix |
| `ctrl-check` | function | List connected controllers and whether you can access them |

Defined in my NixOS config, not here (they depend on Home Manager):

| Shortcut | Command | Description |
| --- | --- | --- |
| `ll` | `eza -la --color=always --icons --group-directories-first --git` | Long listing with git status |
| `vi`, `vim` | `nvim` | Open Neovim |
| `age-edit` | `nix run github:ryantm/agenix -- -e` | Edit an agenix secret |
| `age-rekey` | `nix run github:ryantm/agenix -- -r` | Re-key agenix secrets |
| `notes` | `cd ~/Jarvis && nvim .` | Open my notes vault |
| `snaps`, `snapsh` | `sudo snapper -c root list`, `… -c home list` | List root and home snapshots |
| `snapc` | `sudo snapper -c root create --description` | Create a root snapshot |

`add` stages everything in the current directory, so check `git status` first.

## nru

`nru` is tied to my NixOS config: it edits `flake.lock`, `pkgs/` hashes and a few
package files in the repo that `NIXOS_CONFIG` points to (default `~/nixos-config`). It
is not generic yet. Read it before you run it.

## Customize

Edit or add files under `conf.d/`. New shell sessions pick them up; in a running
session, `source ~/.zsh/zshrc`.
