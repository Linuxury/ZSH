# ---------------------------------------------------------------------------
# Local environment variables — loaded from ~/.env.local if it exists
# Use this for API keys and secrets not tracked in git
# Example: ANTHROPIC_API_KEY=sk-ant-...
# ---------------------------------------------------------------------------
[[ -f "$HOME/.env.local" ]] && source "$HOME/.env.local"
