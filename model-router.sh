#!/bin/bash
# model-router.sh — Universal LLM routing for shell scripts
#
# Routes tasks to the optimal LLM based on tier, provider availability,
# and cost limits. Outputs eval-safe shell variables.
#
# Usage:
#   eval $(model-router.sh <tier>)
#   # Sets: MODEL_ID, MODEL_PROVIDER, MODEL_TIER, MODEL_COST_PER_1K_IN,
#   #        MODEL_COST_PER_1K_OUT, MODEL_MAX_TOKENS, MODEL_CLI_NAME, MODEL_EFFORT
#
#   model-router.sh info              # Show current configuration
#   model-router.sh recommend <agent> # Recommendation for an agent

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Config location: same directory as this script, or override via env
CONFIG="${MODEL_ROUTER_CONFIG:-$SCRIPT_DIR/model-routing.json}"

CONFIG_VALID=true
if [ ! -f "$CONFIG" ]; then
  CONFIG_VALID=false
elif ! jq empty "$CONFIG" 2>/dev/null; then
  CONFIG_VALID=false
fi

ACTION="${1:-standard}"

case "$ACTION" in
  info)
    if ! $CONFIG_VALID; then
      echo "ERROR: $CONFIG not found or invalid" >&2
      exit 1
    fi
    echo "=== Model Router Configuration ==="
    echo ""
    echo "Tiers:"
    jq -r '.tiers | to_entries[] | "  \(.key): \(.value.provider)/\(.value.model) (\(.value.description))"' "$CONFIG"
    echo ""
    echo "Agent mappings:"
    jq -r '.agents // {} | to_entries[] | select(.key != "_comment") | "  \(.key): \(.value)"' "$CONFIG"
    echo ""
    echo "Autonomous jobs:"
    jq -r '.autonomous_jobs // {} | to_entries[] | select(.key != "_comment") | "  \(.key): \(.value)"' "$CONFIG"
    echo ""
    echo "Providers:"
    jq -r '.providers | to_entries[] | "  \(.key): \(.value.status) | \(.value.models | join(", "))"' "$CONFIG"
    exit 0
    ;;

  recommend)
    AGENT="${2:-}"
    if [ -z "$AGENT" ]; then
      echo "Usage: model-router.sh recommend <agent-name>" >&2
      exit 1
    fi
    if ! $CONFIG_VALID; then
      echo "Agent '$AGENT' -> Tier 'standard' -> anthropic/claude-sonnet-5 (config invalid, fallback)" >&2
      exit 0
    fi
    TIER=$(jq -r --arg a "$AGENT" '.agents[$a] // empty' "$CONFIG" 2>/dev/null)
    if [ -z "$TIER" ]; then
      TIER=$(jq -r --arg j "$AGENT" '.autonomous_jobs[$j] // empty' "$CONFIG" 2>/dev/null)
    fi
    TIER="${TIER:-standard}"
    MODEL=$(jq -r --arg t "$TIER" '.tiers[$t].model' "$CONFIG" 2>/dev/null)
    PROVIDER=$(jq -r --arg t "$TIER" '.tiers[$t].provider' "$CONFIG" 2>/dev/null)
    echo "Agent '$AGENT' -> Tier '$TIER' -> $PROVIDER/$MODEL"
    exit 0
    ;;

  heavy|standard|light|local|local-fast|gemini|mistral)
    TIER="$ACTION"
    ;;

  *)
    if $CONFIG_VALID; then
      TIER=$(jq -r --arg a "$ACTION" '.agents[$a] // empty' "$CONFIG" 2>/dev/null)
      if [ -z "$TIER" ]; then
        TIER=$(jq -r --arg j "$ACTION" '.autonomous_jobs[$j] // empty' "$CONFIG" 2>/dev/null)
      fi
    fi
    if [ -z "${TIER:-}" ]; then
      TIER="standard"
    fi
    ;;
esac

# Safe defaults when config is missing or invalid
if ! $CONFIG_VALID; then
  echo "CONFIG_DEGRADED='true'" >&2
  case "$TIER" in
    heavy)   MODEL_ID="claude-opus-5"; MODEL_CLI_NAME="opus"; MODEL_PROVIDER="anthropic" ;;
    light)   MODEL_ID="claude-haiku-4-5"; MODEL_CLI_NAME="haiku"; MODEL_PROVIDER="anthropic" ;;
    local*)  MODEL_ID="qwen3:8b"; MODEL_CLI_NAME=""; MODEL_PROVIDER="ollama" ;;
    gemini)  MODEL_ID="gemini-2.5-flash"; MODEL_CLI_NAME=""; MODEL_PROVIDER="google" ;;
    mistral) MODEL_ID="mistral-small-latest"; MODEL_CLI_NAME=""; MODEL_PROVIDER="mistral" ;;
    *)       MODEL_ID="claude-sonnet-5"; MODEL_CLI_NAME="sonnet"; MODEL_PROVIDER="anthropic" ;;
  esac
  echo "MODEL_ID='$MODEL_ID'"
  echo "MODEL_PROVIDER='$MODEL_PROVIDER'"
  echo "MODEL_TIER='$TIER'"
  echo "MODEL_COST_PER_1K_IN='0.003'"
  echo "MODEL_COST_PER_1K_OUT='0.015'"
  echo "MODEL_MAX_TOKENS='8192'"
  echo "MODEL_CLI_NAME='$MODEL_CLI_NAME'"
  echo "MODEL_EFFORT=''"
  exit 0
fi

# Load tier configuration
MODEL_ID=$(jq -r --arg t "$TIER" '.tiers[$t].model' "$CONFIG" 2>/dev/null)
MODEL_PROVIDER=$(jq -r --arg t "$TIER" '.tiers[$t].provider' "$CONFIG" 2>/dev/null)
MODEL_COST_IN=$(jq -r --arg t "$TIER" '.tiers[$t].cost_per_1k_input' "$CONFIG" 2>/dev/null)
MODEL_COST_OUT=$(jq -r --arg t "$TIER" '.tiers[$t].cost_per_1k_output' "$CONFIG" 2>/dev/null)
MODEL_MAX_TOKENS=$(jq -r --arg t "$TIER" '.tiers[$t].max_output_tokens // 4096' "$CONFIG" 2>/dev/null)
MODEL_CLI_NAME=$(jq -r --arg t "$TIER" '.tiers[$t].cli_name // empty' "$CONFIG" 2>/dev/null)
MODEL_EFFORT=$(jq -r --arg t "$TIER" '.tiers[$t].effort // empty' "$CONFIG" 2>/dev/null)

# Provider fallback when primary is unavailable
PROVIDER_STATUS=$(jq -r --arg p "$MODEL_PROVIDER" '.providers[$p].status' "$CONFIG" 2>/dev/null)
if [ "$PROVIDER_STATUS" != "active" ]; then
  FALLBACK_TIER=$(jq -r --arg t "$TIER" '.tiers[$t].fallback // "standard"' "$CONFIG" 2>/dev/null)
  MODEL_ID=$(jq -r --arg t "$FALLBACK_TIER" '.tiers[$t].model' "$CONFIG" 2>/dev/null)
  MODEL_PROVIDER=$(jq -r --arg t "$FALLBACK_TIER" '.tiers[$t].provider' "$CONFIG" 2>/dev/null)
  MODEL_COST_IN=$(jq -r --arg t "$FALLBACK_TIER" '.tiers[$t].cost_per_1k_input' "$CONFIG" 2>/dev/null)
  MODEL_COST_OUT=$(jq -r --arg t "$FALLBACK_TIER" '.tiers[$t].cost_per_1k_output' "$CONFIG" 2>/dev/null)
  MODEL_CLI_NAME=$(jq -r --arg t "$FALLBACK_TIER" '.tiers[$t].cli_name // empty' "$CONFIG" 2>/dev/null)
  MODEL_EFFORT=$(jq -r --arg t "$FALLBACK_TIER" '.tiers[$t].effort // empty' "$CONFIG" 2>/dev/null)
fi

# Input sanitization: only safe characters in values (prevents eval injection)
TIER="${TIER//[^a-zA-Z0-9_-]/}"
MODEL_ID="${MODEL_ID//[^a-zA-Z0-9_.:-]/}"
MODEL_PROVIDER="${MODEL_PROVIDER//[^a-zA-Z0-9_.-]/}"
MODEL_COST_IN="${MODEL_COST_IN//[^0-9.]/}"
MODEL_COST_OUT="${MODEL_COST_OUT//[^0-9.]/}"
MODEL_MAX_TOKENS="${MODEL_MAX_TOKENS//[^0-9]/}"
MODEL_CLI_NAME="${MODEL_CLI_NAME//[^a-zA-Z0-9_.-]/}"
MODEL_EFFORT="${MODEL_EFFORT//[^a-z]/}"

# Output eval-safe variables
echo "MODEL_ID='$MODEL_ID'"
echo "MODEL_PROVIDER='$MODEL_PROVIDER'"
echo "MODEL_TIER='$TIER'"
echo "MODEL_COST_PER_1K_IN='$MODEL_COST_IN'"
echo "MODEL_COST_PER_1K_OUT='$MODEL_COST_OUT'"
echo "MODEL_MAX_TOKENS='$MODEL_MAX_TOKENS'"
echo "MODEL_CLI_NAME='$MODEL_CLI_NAME'"
echo "MODEL_EFFORT='$MODEL_EFFORT'"
