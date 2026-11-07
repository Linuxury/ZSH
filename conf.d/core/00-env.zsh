# Ensure NixOS setuid wrappers always take priority — nix shells can displace them
typeset -gU path
path=(/run/wrappers/bin $path)

# Default editor — Neovim for both terminal and "visual" contexts.
# Most tools check VISUAL first, then fall back to EDITOR.
export EDITOR=nvim
export VISUAL=nvim

# Canonical path to the nixos-config repo — used by nru and other tools
export NIXOS_CONFIG=$HOME/nixos-config

# IteraCompute (free Qwen, OpenAI-compatible) for any AI tool — only on hosts
# that import the Zed or ai-tools module (they deploy the agenix secret).
if [[ -r /run/agenix/iteracompute-api-key ]]; then
  export ITERACOMPUTE_API_KEY=$(</run/agenix/iteracompute-api-key)
  export ITERACOMPUTE_BASE_URL=https://api.iteracompute.com/v1
  export ITERACOMPUTE_MODEL=qwen/qwen3.8-27b
fi

