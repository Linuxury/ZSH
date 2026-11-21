# ===========================================================================
# conf.d/user/local.zsh — machine-local environment, loaded last
#
# Sources ~/.env.local if it exists. That file is not tracked in git, so put
# API keys and other secrets there. "user" is the last folder, so values set in
# ~/.env.local override everything loaded before, including conf.d/core/00-env.zsh.
# Example line in ~/.env.local (placeholder value):
#   export ANTHROPIC_API_KEY=sk-ant-...
# "export" makes the variable visible to programs the shell starts. A plain
# NAME=value only sets a shell variable.
# To turn it off: delete ~/.env.local, or rename this file so it no longer
# ends in .zsh.
# ===========================================================================
[[ -f "$HOME/.env.local" ]] && source "$HOME/.env.local"
