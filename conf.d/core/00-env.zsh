# ===========================================================================
# conf.d/core/00-env.zsh — environment variables for every interactive shell
#
# Loads first ("core" is the first folder, "00-" the first file in it), so
# later files can rely on these values. To change one on a single machine,
# set it in ~/.env.local (untracked; loaded last by conf.d/user/local.zsh).
# ===========================================================================

# PATH order — NixOS setuid wrappers (sudo, ping, passwd…) first.
#   typeset -gU path   keep PATH entries unique (no duplicates after nix shells)
#   /run/wrappers/bin  NixOS' setuid copies of those tools; nix shells can push
#                      them behind non-setuid versions, which then fail
typeset -gU path
path=(/run/wrappers/bin $path)

# Default editor.
#   EDITOR  used by terminal tools (git commit, crontab -e, sudoedit)
#   VISUAL  used by tools that can open a full-screen editor; checked first
# NixOS sets both (nixos-config: core.nix EDITOR=hx, vscode.nix
# VISUAL="code --wait"), so only fill them in when unset: hx, and VISUAL
# falls back to EDITOR (headless hosts have no VS Code).
#   Alternatives: micro, nano, or a GUI editor with a wait flag such as
#   "code --wait".
export EDITOR="${EDITOR:-hx}"
export VISUAL="${VISUAL:-$EDITOR}"

# Path to the NixOS flake repo. Read by nru (update + rebuild) and its
# helpers; change it if the repo lives somewhere else.
export NIXOS_CONFIG=$HOME/nixos-config

# IteraCompute (OpenAI-compatible API) for AI tools in the shell.
# Only set when the agenix secret exists, i.e. on hosts that import the
# Zed or ai-tools NixOS module.
#   ITERACOMPUTE_API_KEY   key, read from /run/agenix/iteracompute-api-key
#   ITERACOMPUTE_BASE_URL  OpenAI-style endpoint
#   ITERACOMPUTE_MODEL     default model; any model id the provider lists works
if [[ -r /run/agenix/iteracompute-api-key ]]; then
  export ITERACOMPUTE_API_KEY=$(</run/agenix/iteracompute-api-key)
  export ITERACOMPUTE_BASE_URL=https://api.iteracompute.com/v1
  export ITERACOMPUTE_MODEL=qwen/qwen3.8-27b
fi
