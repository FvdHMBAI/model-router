# model-router

[![CI](https://github.com/FvdHMBAI/model-router/actions/workflows/ci.yml/badge.svg)](https://github.com/FvdHMBAI/model-router/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**The LLM router that lives in your shell.** One config file, every model, zero dependencies beyond `bash` and `jq`.

```bash
eval $(model-router standard)
echo $MODEL_ID  # claude-sonnet-5
```

When Anthropic ships a new model, you update **one JSON file** — not 30 scripts.

## Why model-router?

Every team running AI automation hits the same problem: model names hardcoded across dozens of scripts. When `claude-sonnet-4` becomes `claude-sonnet-5`, you grep through everything, miss one, and it breaks at 2 AM.

Model Router fixes this with two ideas:

1. **Tiers, not model names.** Scripts say `standard`, not `claude-sonnet-5`. The mapping lives in one config.
2. **Automatic fallback.** Provider down? Config corrupt? Safe defaults kick in. Your 2 AM cron job doesn't die.

## How it compares

| Feature | model-router | LiteLLM | OpenRouter | Portkey |
|---------|:---:|:---:|:---:|:---:|
| Shell-native (`eval` output) | **Yes** | No | No | No |
| Zero dependencies | **bash + jq** | Python + pip | SaaS | Node.js |
| Self-hosted | **Yes** | Yes | No | Yes |
| No server/proxy needed | **Yes** | No (proxy) | No (API) | No (gateway) |
| Provider health checks | **Yes** | Yes | N/A | Yes |
| Cost tracking | **Yes** | Yes | Yes | Yes |
| Latency benchmarks | **Yes** | No | No | Yes |
| Eval-injection safe | **Yes** | N/A | N/A | N/A |
| Lines of code | **~300** | 50,000+ | Closed | 20,000+ |
| Setup time | **30 seconds** | Minutes | Account | Minutes |

**When to use model-router:** You write bash. Your AI automation runs in cron jobs, CI pipelines, or shell scripts. You want routing without adding Python, Node.js, or a proxy server to your stack.

**When to use something else:** You need a unified OpenAI-compatible API proxy, SDK support in Python/JS, or request-level load balancing across model replicas.

## Install

```bash
git clone https://github.com/FvdHMBAI/model-router.git
cd model-router
./install.sh
```

Or just copy two files:

```bash
cp model-router.sh /usr/local/bin/model-router
cp model-routing.json ~/.config/model-router/model-routing.json
export MODEL_ROUTER_CONFIG="$HOME/.config/model-router/model-routing.json"
```

## Quick start

```bash
# Route a standard task
eval $(model-router standard)
echo "$MODEL_ID"        # claude-sonnet-5
echo "$MODEL_PROVIDER"  # anthropic
echo "$MODEL_EFFORT"    # medium

# Heavy task — complex debugging, architecture
eval $(model-router heavy)
# -> claude-opus-5, effort=high

# Free local model — triage, classification
eval $(model-router local)
# -> qwen3:8b via Ollama

# Use in an API call
eval $(model-router standard)
curl -s https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$(jq -n \
    --arg model "$MODEL_ID" \
    --argjson max_tokens "$MODEL_MAX_TOKENS" \
    '{model: $model, max_tokens: $max_tokens,
      messages: [{role: "user", content: "Hello"}]}')"
```

## Commands

| Command | Description |
|---------|-------------|
| `model-router <tier>` | Output eval-safe variables for a tier |
| `model-router <agent>` | Resolve agent name to tier to model |
| `model-router info` | Show full configuration |
| `model-router health` | Check all provider endpoints |
| `model-router recommend <name>` | Show routing details for an agent or job |
| `model-router cost-report` | Usage summary by provider, tier, and day |
| `model-router benchmark [tier]` | Latency test across providers |
| `model-router init` | Create default config in `~/.config/model-router/` |
| `model-router --version` | Show version |
| `model-router --help` | Show usage |

## Tiers

| Tier | Default Model | Provider | Use Case | Cost |
|------|--------------|----------|----------|------|
| `heavy` | claude-opus-5 | Anthropic | Debugging, architecture, security | $$$ |
| `standard` | claude-sonnet-5 | Anthropic | Reviews, tickets, content, deployments | $$ |
| `light` | claude-haiku-4-5 | Anthropic | Classification, formatting, health checks | $ |
| `local` | qwen3:8b | Ollama | Triage, docs, simple analysis | Free |
| `local-fast` | qwen2.5:1.5b | Ollama | Keyword extraction, fast classification | Free |
| `gemini` | gemini-2.5-flash | Google | Cross-review, video, large contexts | $ |
| `mistral` | mistral-small-latest | Mistral | EU-hosted, GDPR-compliant workloads | $ |

All tiers are customizable. Add your own in `model-routing.json`.

## Output variables

Every routing call sets these eval-safe shell variables:

| Variable | Example | Description |
|----------|---------|-------------|
| `MODEL_ID` | `claude-sonnet-5` | Full model identifier for API calls |
| `MODEL_PROVIDER` | `anthropic` | Provider name |
| `MODEL_TIER` | `standard` | Resolved tier |
| `MODEL_COST_PER_1K_IN` | `0.003` | Input cost per 1K tokens (USD) |
| `MODEL_COST_PER_1K_OUT` | `0.015` | Output cost per 1K tokens (USD) |
| `MODEL_MAX_TOKENS` | `8192` | Maximum output tokens |
| `MODEL_CLI_NAME` | `sonnet` | Short name for CLI tools |
| `MODEL_EFFORT` | `medium` | Reasoning effort hint |

## Providers

5 providers supported out of the box:

| Provider | Models | Notes |
|----------|--------|-------|
| Anthropic | Opus 5, Sonnet 5, Haiku 4.5 | Primary |
| Google | Gemini 2.5 Flash/Pro | Cross-review, large context |
| Mistral | Small, Medium | EU-hosted, GDPR |
| OpenAI | GPT-4o, GPT-4o-mini | Alternative |
| Ollama | Any local model | Free, self-hosted |

Add more by editing the `providers` section in your config.

## Agent & job mapping

Map your agents and cron jobs to tiers:

```json
{
  "agents": {
    "code-reviewer": "standard",
    "architect": "heavy",
    "formatter": "light"
  },
  "autonomous_jobs": {
    "nightly-scan": "local",
    "weekly-review": "standard"
  }
}
```

Then route by name:

```bash
eval $(model-router code-reviewer)
# Resolves: code-reviewer -> standard -> anthropic/claude-sonnet-5
```

## Resilience

Model Router is designed for unattended operation:

- **Missing config?** Safe hardcoded defaults (heavy=opus, standard=sonnet, light=haiku, local=qwen)
- **Corrupt JSON?** Falls back to defaults, prints `CONFIG_DEGRADED='true'` to stderr
- **Provider down?** Follows the `fallback` chain defined per tier, logs the failover to stderr
- **Eval injection?** All output values are sanitized — only alphanumeric, dots, colons, hyphens pass through

## Cost tracking

Every routing call logs to `~/.model-router/usage.log`:

```
2026-08-02T14:30:00Z tier=standard model=claude-sonnet-5 provider=anthropic cost_in=0.003 cost_out=0.015
```

View your usage:

```bash
model-router cost-report
# === Cost Report ===
# By provider (last 30 days):
#   anthropic    142 requests
#   ollama        89 requests
# By tier (last 30 days):
#   standard      98 requests
#   local          89 requests
#   heavy          44 requests
```

## Provider health checks

```bash
model-router health
# === Provider Health Check ===
#   anthropic    OK
#   google       OK
#   mistral      OK
#   openai       NO KEY   (set OPENAI_API_KEY)
#   ollama       OK
```

## Examples

See the [`examples/`](examples/) directory:

- **[ci-pipeline.sh](examples/ci-pipeline.sh)** — Use model-router in CI/CD
- **[cron-job.sh](examples/cron-job.sh)** — Overnight batch processing with local-first routing
- **[multi-provider.sh](examples/multi-provider.sh)** — Provider failover and health demo

## Configuration

Edit `model-routing.json` to match your setup:

```json
{
  "tiers": {
    "heavy": {
      "provider": "anthropic",
      "model": "claude-opus-5",
      "fallback": "standard",
      "effort": "high",
      "cost_per_1k_input": 0.015,
      "cost_per_1k_output": 0.075
    }
  },
  "providers": {
    "anthropic": {
      "status": "active",
      "api_key_env": "ANTHROPIC_API_KEY",
      "base_url": "https://api.anthropic.com"
    }
  },
  "cost_limits": {
    "daily_eur": 50,
    "monthly_eur": 800,
    "alert_threshold": 0.8
  }
}
```

Override config location:

```bash
export MODEL_ROUTER_CONFIG="/path/to/your/model-routing.json"
```

## Requirements

- `bash` 4+
- `jq` (JSON parsing)
- API keys for the providers you use (set via environment variables)

## Contributing

Contributions welcome. Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Run `bash tests/test-model-router.sh` before submitting
5. Open a PR

## License

[MIT](LICENSE)
