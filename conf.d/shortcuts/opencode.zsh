# ---------------------------------------------------------------------------
# OpenCode — runs with OpenRouter API (key from agenix)
# ---------------------------------------------------------------------------
opencode() {
  ANTHROPIC_API_KEY="$(cat /run/agenix/openrouter-api-key 2>/dev/null)" \
  ANTHROPIC_BASE_URL="https://openrouter.ai/api" \
  command opencode "$@"
}

