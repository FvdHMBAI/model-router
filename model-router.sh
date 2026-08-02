#!/bin/bash
# model-router.sh — Universal LLM routing for shell scripts
#
# Routes tasks to the optimal LLM based on tier, provider availability,
# and cost limits. Outputs eval-safe shell variables.
#
# Usage:
#   eval $(model-router.sh <tier>)
#   model-router.sh info              # Show current configuration
#   model-router.sh health            # Check all provider endpoints
#   model-router.sh recommend <agent> # Recommendation for an agent
#   model-router.sh cost-report       # Summarize usage costs
#   model-router.sh benchmark <tier>  # Latency test per provider

set -uo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG="${MODEL_ROUTER_CONFIG:-$SCRIPT_DIR/model-routing.json}"
USAGE_DIR="${MODEL_ROUTER_DATA:-$HOME/.model-router}"
USAGE_LOG="$USAGE_DIR/usage.log"

CONFIG_VALID=true
if [ ! -f "$CONFIG" ]; then
  CONFIG_VALID=false
elif ! jq empty "$CONFIG" 2>/dev/null; then
  CONFIG_VALID=false
fi

ACTION="${1:-standard}"

# ── Utility functions ──────────────────────────────────────────────

log_usage() {
  local tier="$1" model="$2" provider="$3"
  mkdir -p "$USAGE_DIR" 2>/dev/null || return 0
  local cost_in cost_out
  cost_in=$(jq -r --arg t "$tier" '.tiers[$t].cost_per_1k_input // 0' "$CONFIG" 2>/dev/null || echo "0")
  cost_out=$(jq -r --arg t "$tier" '.tiers[$t].cost_per_1k_output // 0' "$CONFIG" 2>/dev/null || echo "0")
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') tier=$tier model=$model provider=$provider cost_in=$cost_in cost_out=$cost_out" >> "$USAGE_LOG" 2>/dev/null || true
}

sanitize() {
  local val="$1" allow="${2:-a-zA-Z0-9_.-}"
  echo "${val//[^$allow]/}"
}

require_config() {
  if ! $CONFIG_VALID; then
    echo "ERROR: Config not found or invalid: $CONFIG" >&2
    echo "  Create one with: model-router init" >&2
    exit 1
  fi
}

check_provider_health() {
  local provider="$1"
  local base_url api_key_env api_key status_code
  base_url=$(jq -r --arg p "$provider" '.providers[$p].base_url // ""' "$CONFIG" 2>/dev/null)
  api_key_env=$(jq -r --arg p "$provider" '.providers[$p].api_key_env // ""' "$CONFIG" 2>/dev/null)

  [ -z "$base_url" ] && echo "unknown" && return

  if [ "$provider" = "ollama" ]; then
    status_code=$(curl -sf -o /dev/null -w '%{http_code}' --max-time 3 "$base_url/api/tags" 2>/dev/null || echo "000")
  else
    api_key="${!api_key_env:-}"
    if [ -z "$api_key" ] && [ -n "$api_key_env" ]; then
      echo "no-key"
      return
    fi
    status_code=$(curl -sf -o /dev/null -w '%{http_code}' --max-time 5 "$base_url" 2>/dev/null || echo "000")
  fi

  case "$status_code" in
    2*|3*|4*) echo "reachable" ;;  # 4xx = endpoint exists, auth needed = reachable
    *) echo "unreachable" ;;
  esac
}

resolve_tier() {
  local requested="$1"
  local model provider

  model=$(jq -r --arg t "$requested" '.tiers[$t].model // ""' "$CONFIG" 2>/dev/null)
  provider=$(jq -r --arg t "$requested" '.tiers[$t].provider // ""' "$CONFIG" 2>/dev/null)

  if [ -z "$model" ] || [ -z "$provider" ]; then
    echo "ERROR: Unknown tier '$requested'" >&2
    exit 1
  fi

  local provider_status
  provider_status=$(jq -r --arg p "$provider" '.providers[$p].status // "active"' "$CONFIG" 2>/dev/null)

  if [ "$provider_status" != "active" ]; then
    local fallback
    fallback=$(jq -r --arg t "$requested" '.tiers[$t].fallback // ""' "$CONFIG" 2>/dev/null)
    if [ -n "$fallback" ] && [ "$fallback" != "null" ] && [ "$fallback" != "$requested" ]; then
      echo "FALLBACK: $provider unavailable for tier '$requested', trying '$fallback'" >&2
      resolve_tier "$fallback"
      return
    fi
  fi

  echo "$requested"
}

# ── Commands ───────────────────────────────────────────────────────

case "$ACTION" in
  --version|-v|version)
    echo "model-router $VERSION"
    exit 0
    ;;

  --help|-h|help)
    cat <<'HELP'
model-router — Universal LLM routing for shell scripts

ROUTING:
  model-router <tier>           Output eval-safe vars for a tier
  model-router <agent-name>     Resolve agent -> tier -> model

COMMANDS:
  model-router info             Show full configuration
  model-router health           Check all provider endpoints
  model-router recommend <name> Show routing for an agent/job
  model-router cost-report      Summarize usage costs from log
  model-router benchmark <tier> Latency test across providers
  model-router init             Create default config file
  model-router version          Show version

TIERS:
  heavy        Complex: debugging, architecture, security
  standard     Routine: reviews, tickets, content
  light        Simple: classification, formatting
  local        Free: triage, docs (Ollama)
  local-fast   Free: keyword extraction (Ollama)
  gemini       Google: cross-review, large context
  mistral      EU-hosted, GDPR-compliant

ENVIRONMENT:
  MODEL_ROUTER_CONFIG    Path to config JSON (default: ./model-routing.json)
  MODEL_ROUTER_DATA      Path to data dir (default: ~/.model-router)
HELP
    exit 0
    ;;

  init)
    CONFIG_DIR="${MODEL_ROUTER_CONFIG_DIR:-$HOME/.config/model-router}"
    if [ -f "$CONFIG_DIR/model-routing.json" ]; then
      echo "Config already exists: $CONFIG_DIR/model-routing.json" >&2
      exit 1
    fi
    mkdir -p "$CONFIG_DIR"
    cp "$SCRIPT_DIR/model-routing.json" "$CONFIG_DIR/model-routing.json"
    echo "Created: $CONFIG_DIR/model-routing.json"
    echo "Set: export MODEL_ROUTER_CONFIG=\"$CONFIG_DIR/model-routing.json\""
    exit 0
    ;;

  info)
    require_config
    echo "=== Model Router v$VERSION ==="
    echo ""
    echo "Config: $CONFIG"
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
    echo ""
    echo "Cost limits:"
    jq -r '"  Daily:   \(.cost_limits.daily_eur // "unlimited") EUR\n  Monthly: \(.cost_limits.monthly_eur // "unlimited") EUR\n  Alert:   \((.cost_limits.alert_threshold // 0.8) * 100)%"' "$CONFIG"
    exit 0
    ;;

  health)
    require_config
    echo "=== Provider Health Check ==="
    echo ""
    local_providers=$(jq -r '.providers | keys[]' "$CONFIG" 2>/dev/null)
    all_ok=true
    for p in $local_providers; do
      status_conf=$(jq -r --arg p "$p" '.providers[$p].status' "$CONFIG")
      if [ "$status_conf" != "active" ]; then
        printf "  %-12s %-12s (disabled in config)\n" "$p" "DISABLED"
        continue
      fi
      health=$(check_provider_health "$p")
      case "$health" in
        reachable)   printf "  %-12s %-12s\n" "$p" "OK" ;;
        no-key)      printf "  %-12s %-12s (set %s)\n" "$p" "NO KEY" "$(jq -r --arg p "$p" '.providers[$p].api_key_env' "$CONFIG")" ; all_ok=false ;;
        unreachable) printf "  %-12s %-12s\n" "$p" "DOWN" ; all_ok=false ;;
        *)           printf "  %-12s %-12s\n" "$p" "UNKNOWN" ; all_ok=false ;;
      esac
    done
    echo ""
    $all_ok && echo "All active providers reachable." || echo "Some providers have issues."
    exit 0
    ;;

  recommend)
    AGENT="${2:-}"
    if [ -z "$AGENT" ]; then
      echo "Usage: model-router recommend <agent-name>" >&2
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
    COST_IN=$(jq -r --arg t "$TIER" '.tiers[$t].cost_per_1k_input' "$CONFIG" 2>/dev/null)
    COST_OUT=$(jq -r --arg t "$TIER" '.tiers[$t].cost_per_1k_output' "$CONFIG" 2>/dev/null)
    EFFORT=$(jq -r --arg t "$TIER" '.tiers[$t].effort // "default"' "$CONFIG" 2>/dev/null)
    echo "Agent '$AGENT' -> Tier '$TIER' -> $PROVIDER/$MODEL"
    echo "  Cost:   \$${COST_IN}/1K in, \$${COST_OUT}/1K out"
    echo "  Effort: $EFFORT"
    exit 0
    ;;

  cost-report)
    if [ ! -f "$USAGE_LOG" ]; then
      echo "No usage data yet. Route some requests first." >&2
      echo "  Usage log: $USAGE_LOG" >&2
      exit 0
    fi
    echo "=== Cost Report ==="
    echo ""
    echo "Usage log: $USAGE_LOG"
    echo "Entries:   $(wc -l < "$USAGE_LOG")"
    echo ""

    echo "By provider (last 30 days):"
    cutoff=$(date -u -d '30 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-30d '+%Y-%m-%d' 2>/dev/null || echo "2000-01-01")
    awk -v cutoff="$cutoff" '
      $1 >= cutoff {
        provider=""
        for (i=1; i<=NF; i++) {
          if ($i ~ /^provider=/) { split($i, a, "="); provider=a[2] }
        }
        if (provider != "") { count[provider]++; total++ }
      }
      END {
        for (p in count) printf "  %-12s %d requests\n", p, count[p]
        print ""
        print "Total: " total " requests"
      }
    ' "$USAGE_LOG"

    echo ""
    echo "By tier (last 30 days):"
    awk -v cutoff="$cutoff" '
      $1 >= cutoff {
        tier=""
        for (i=1; i<=NF; i++) {
          if ($i ~ /^tier=/) { split($i, a, "="); tier=a[2] }
        }
        if (tier != "") count[tier]++
      }
      END {
        for (t in count) printf "  %-12s %d requests\n", t, count[t]
      }
    ' "$USAGE_LOG"

    echo ""
    echo "By day (last 7 days):"
    cutoff7=$(date -u -d '7 days ago' '+%Y-%m-%d' 2>/dev/null || date -u -v-7d '+%Y-%m-%d' 2>/dev/null || echo "2000-01-01")
    awk -v cutoff="$cutoff7" '
      {
        day=substr($1, 1, 10)
        if (day >= cutoff) count[day]++
      }
      END {
        n = asorti(count, sorted)
        for (i = 1; i <= n; i++) printf "  %s  %d requests\n", sorted[i], count[sorted[i]]
      }
    ' "$USAGE_LOG" 2>/dev/null || awk -v cutoff="$cutoff7" '
      {
        day=substr($1, 1, 10)
        if (day >= cutoff) count[day]++
      }
      END {
        for (d in count) printf "  %s  %d requests\n", d, count[d]
      }
    ' "$USAGE_LOG" | sort

    exit 0
    ;;

  benchmark)
    require_config
    BENCH_TIER="${2:-standard}"
    echo "=== Benchmark: Tier '$BENCH_TIER' ==="
    echo ""

    providers=$(jq -r '.providers | to_entries[] | select(.value.status == "active") | .key' "$CONFIG")
    for p in $providers; do
      base_url=$(jq -r --arg p "$p" '.providers[$p].base_url' "$CONFIG")
      start_ms=$(date +%s%N 2>/dev/null || echo "0")
      if [ "$p" = "ollama" ]; then
        curl -sf -o /dev/null --max-time 5 "$base_url/api/tags" 2>/dev/null
      else
        curl -sf -o /dev/null --max-time 5 "$base_url" 2>/dev/null
      fi
      rc=$?
      end_ms=$(date +%s%N 2>/dev/null || echo "0")
      if [ "$rc" -eq 0 ] && [ "$start_ms" != "0" ]; then
        latency_ms=$(( (end_ms - start_ms) / 1000000 ))
        printf "  %-12s %4d ms\n" "$p" "$latency_ms"
      elif [ "$rc" -eq 0 ]; then
        printf "  %-12s reachable (timing unavailable)\n" "$p"
      else
        printf "  %-12s unreachable\n" "$p"
      fi
    done
    exit 0
    ;;

  # Standard tier routing
  heavy|standard|light|local|local-fast|gemini|mistral)
    TIER="$ACTION"
    ;;

  *)
    # Try agent/job lookup
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

# ── Resolve tier with fallback chain ───────────────────────────────

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
  log_usage "$TIER" "$MODEL_ID" "$MODEL_PROVIDER"
  exit 0
fi

RESOLVED_TIER=$(resolve_tier "$TIER")

# Load tier configuration
MODEL_ID=$(jq -r --arg t "$RESOLVED_TIER" '.tiers[$t].model' "$CONFIG" 2>/dev/null)
MODEL_PROVIDER=$(jq -r --arg t "$RESOLVED_TIER" '.tiers[$t].provider' "$CONFIG" 2>/dev/null)
MODEL_COST_IN=$(jq -r --arg t "$RESOLVED_TIER" '.tiers[$t].cost_per_1k_input' "$CONFIG" 2>/dev/null)
MODEL_COST_OUT=$(jq -r --arg t "$RESOLVED_TIER" '.tiers[$t].cost_per_1k_output' "$CONFIG" 2>/dev/null)
MODEL_MAX_TOKENS=$(jq -r --arg t "$RESOLVED_TIER" '.tiers[$t].max_output_tokens // 4096' "$CONFIG" 2>/dev/null)
MODEL_CLI_NAME=$(jq -r --arg t "$RESOLVED_TIER" '.tiers[$t].cli_name // empty' "$CONFIG" 2>/dev/null)
MODEL_EFFORT=$(jq -r --arg t "$RESOLVED_TIER" '.tiers[$t].effort // empty' "$CONFIG" 2>/dev/null)

# Sanitize all output values (prevents eval injection)
RESOLVED_TIER="$(sanitize "$RESOLVED_TIER" 'a-zA-Z0-9_-')"
MODEL_ID="$(sanitize "$MODEL_ID" 'a-zA-Z0-9_.:-')"
MODEL_PROVIDER="$(sanitize "$MODEL_PROVIDER" 'a-zA-Z0-9_.-')"
MODEL_COST_IN="$(sanitize "$MODEL_COST_IN" '0-9.')"
MODEL_COST_OUT="$(sanitize "$MODEL_COST_OUT" '0-9.')"
MODEL_MAX_TOKENS="$(sanitize "$MODEL_MAX_TOKENS" '0-9')"
MODEL_CLI_NAME="$(sanitize "$MODEL_CLI_NAME" 'a-zA-Z0-9_.-')"
MODEL_EFFORT="$(sanitize "$MODEL_EFFORT" 'a-z')"

# Output eval-safe variables
echo "MODEL_ID='$MODEL_ID'"
echo "MODEL_PROVIDER='$MODEL_PROVIDER'"
echo "MODEL_TIER='$RESOLVED_TIER'"
echo "MODEL_COST_PER_1K_IN='$MODEL_COST_IN'"
echo "MODEL_COST_PER_1K_OUT='$MODEL_COST_OUT'"
echo "MODEL_MAX_TOKENS='$MODEL_MAX_TOKENS'"
echo "MODEL_CLI_NAME='$MODEL_CLI_NAME'"
echo "MODEL_EFFORT='$MODEL_EFFORT'"

# Log usage
log_usage "$RESOLVED_TIER" "$MODEL_ID" "$MODEL_PROVIDER"
