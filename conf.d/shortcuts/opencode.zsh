# ===========================================================================
# conf.d/shortcuts/opencode.zsh — run OpenCode through OpenRouter
#
# Usage: opencode [subcommand] [flags] [directory]    (see: opencode --help)
# For this one command, sets two variables and then runs the real binary:
#   ANTHROPIC_API_KEY   OpenRouter key, read from /run/agenix/openrouter-api-key
#   ANTHROPIC_BASE_URL  https://openrouter.ai/api, the endpoint OpenCode calls
# Other variables the opencode binary reads, if you want a different setup:
#   ANTHROPIC_AUTH_TOKEN  also referenced by the binary
#   OPENROUTER_API_KEY    also referenced by the binary (key under its own name)
# If the key file is missing, ANTHROPIC_API_KEY is set to an empty string,
# which replaces any ANTHROPIC_API_KEY already in the environment.
# To turn it off: rename the file so it no longer ends in .zsh.
# ===========================================================================
opencode() {
  # The two assignments apply to this command only. "command" skips this
  # function, so the real opencode binary runs.
  ANTHROPIC_API_KEY="$(cat /run/agenix/openrouter-api-key 2>/dev/null)" \
  ANTHROPIC_BASE_URL="https://openrouter.ai/api" \
  command opencode "$@"
}
