# model-router

**One config, every LLM.** Route tasks to the right model based on complexity — not hardcoded model names scattered across your scripts.

```bash
eval $(model-router standard)
curl -s https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -d "{\"model\": \"$MODEL_ID\", \"max_tokens\": $MODEL_MAX_TOKENS, ...}"
```

When Anthropic releases a new model, you update **one JSON file** — not 30 scripts.

## Why?

Every team with AI automation hits the same problem: model names hardcoded everywhere. When `claude-sonnet-4-5-20250514` gets replaced by `claude-sonnet-5`, you grep through dozens of scripts, miss one, and it breaks at 2am.

Model Router solves this with two ideas:

1. **Tiers instead of model names.** Your scripts say `standard`, not `claude-sonnet-5`. The mapping lives in one config file.
2. **Automatic fallback.** If a provider is down, the router falls back to the next tier. If the config is corrupted, hardcoded safe defaults kick in.

## Install

```bash
git clone https://github.com/FvdHMBAI/model-router.git
cd model-router
chmod +x install.sh model-router.sh
./install.sh
```

Or just copy the two files (`model-router.sh` + `model-routing.json`) wherever you want.

## Quick Start

```bash
# Get the right model for a standard task
eval $(model-router standard)
echo $MODEL_ID        # claude-sonnet-5
echo $MODEL_PROVIDER  # anthropic
echo $MODEL_EFFORT    # medium

# Heavy task (complex debugging, architecture)
eval $(model-router heavy)
echo $MODEL_ID        # claude-opus-5

# Cheap local model (classification, triage)
eval $(model-router local)
echo $MODEL_ID        # qwen3:8b
echo $MODEL_PROVIDER  # ollama

# Show full config
model-router info
```

## Tiers

| Tier | Default Model | Provider | Use Case | Cost |
|------|--------------|----------|----------|------|
| `heavy` | claude-opus-5 | Anthropic | Debugging, architecture, security | $$$ |
| `standard` | claude-sonnet-5 | Anthropic | Routine: tickets, reviews, content | $$ |
| `light` | claude-haiku-4-5 | Anthropic | Classification, formatting, health checks | $ |
| `local` | qwen3:8b | Ollama | Simple analysis, triage, docs | Free |
| `local-fast` | qwen2.5:1.5b | Ollama | Keyword extraction, fast classification | Free |
| `gemini` | gemini-2.5-flash | Google | Cross-review, video, large contexts | $ |
| `mistral` | mistral-small-latest | Mistral | EU-hosted, GDPR-compliant | $ |

## Providers

| Provider | Status | Models | Notes |
|----------|--------|--------|-------|
| Anthropic | Active | Opus 5, Sonnet 5, Haiku 4.5 | Primary |
| Google | Active | Gemini 2.5 Flash/Pro | Cross-review |
| Mistral | Active | Small, Medium | EU-hosted |
| OpenAI | Active | GPT-4o, GPT-4o-mini | Alternative |
| Ollama | Active | Qwen 3 8B, Qwen 2.5 1.5B | Local, free |

## Output Variables

Every call sets these eval-safe variables:

| Variable | Example | Description |
|----------|---------|-------------|
| `MODEL_ID` | `claude-sonnet-5` | Full model identifier for API calls |
| `MODEL_PROVIDER` | `anthropic` | Provider name |
| `MODEL_TIER` | `standard` | Resolved tier |
| `MODEL_COST_PER_1K_IN` | `0.003` | Input cost per 1K tokens |
| `MODEL_COST_PER_1K_OUT` | `0.015` | Output cost per 1K tokens |
| `MODEL_MAX_TOKENS` | `8192` | Max output tokens |
| `MODEL_CLI_NAME` | `sonnet` | Short name for CLI tools |
| `MODEL_EFFORT` | `medium` | Reasoning effort (strongest cost lever) |

## Agent & Job Mapping

Map your agents and cron jobs to tiers in the config:

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

Then in your scripts:

```bash
eval $(model-router code-reviewer)
# Resolves: code-reviewer -> standard -> claude-sonnet-5
```

## Resilience

- **Missing config:** Safe defaults (heavy=opus, standard=sonnet, light=haiku)
- **Corrupt JSON:** Falls back to defaults, prints `CONFIG_DEGRADED='true'` to stderr
- **Provider down:** Follows the `fallback` chain (heavy -> standard -> light -> local)
- **Injection-safe:** All output values are sanitized — only alphanumeric, dots, colons, hyphens

## Usage in Scripts

```bash
#!/bin/bash
# Example: nightly scan that uses the cheapest model

eval $(model-router local) || eval $(model-router light)

RESULT=$(curl -s "$OLLAMA_URL/api/generate" \
  -d "$(jq -n --arg model "$MODEL_ID" --arg prompt "Analyze this log" \
    '{model: $model, prompt: $prompt, stream: false}')" \
  | jq -r '.response')
```

## Configuration

Edit `model-routing.json` to match your setup. The config supports:

- **Custom tiers** with any provider/model combination
- **Cost limits** (daily + monthly) with alert thresholds
- **Provider API key paths** via environment variables
- **Fallback chains** for each tier

## Requirements

- `bash` 4+
- `jq` (for JSON parsing)
- API keys for the providers you want to use (set via environment variables)

## License

MIT
