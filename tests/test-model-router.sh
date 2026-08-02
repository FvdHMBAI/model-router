#!/bin/bash
# test-model-router.sh — Test suite for model-router
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTER="$SCRIPT_DIR/../model-router.sh"
FIXTURE_DIR="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0

# ── Test helpers ───────────────────────────────────────────────────

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $label"
    ((PASS++))
  else
    echo "  FAIL: $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    ((FAIL++))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $label"
    ((PASS++))
  else
    echo "  FAIL: $label"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
    ((FAIL++))
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if ! echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $label"
    ((PASS++))
  else
    echo "  FAIL: $label"
    echo "    expected NOT to contain: $needle"
    ((FAIL++))
  fi
}

assert_exit_code() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" -eq "$actual" ]; then
    echo "  PASS: $label"
    ((PASS++))
  else
    echo "  FAIL: $label (exit code: expected $expected, got $actual)"
    ((FAIL++))
  fi
}

# ── Setup ──────────────────────────────────────────────────────────

mkdir -p "$FIXTURE_DIR"

cat > "$FIXTURE_DIR/valid-config.json" << 'EOF'
{
  "tiers": {
    "heavy": {
      "description": "Complex tasks",
      "provider": "anthropic",
      "model": "claude-opus-5",
      "cli_name": "opus",
      "cost_per_1k_input": 0.015,
      "cost_per_1k_output": 0.075,
      "max_output_tokens": 16384,
      "fallback": "standard",
      "effort": "high"
    },
    "standard": {
      "description": "Routine tasks",
      "provider": "anthropic",
      "model": "claude-sonnet-5",
      "cli_name": "sonnet",
      "cost_per_1k_input": 0.003,
      "cost_per_1k_output": 0.015,
      "max_output_tokens": 8192,
      "fallback": "light",
      "effort": "medium"
    },
    "light": {
      "description": "Simple tasks",
      "provider": "anthropic",
      "model": "claude-haiku-4-5",
      "cli_name": "haiku",
      "cost_per_1k_input": 0.0008,
      "cost_per_1k_output": 0.004,
      "max_output_tokens": 4096,
      "fallback": "local"
    },
    "local": {
      "description": "Local inference",
      "provider": "ollama",
      "model": "qwen3:8b",
      "cli_name": null,
      "cost_per_1k_input": 0,
      "cost_per_1k_output": 0,
      "max_output_tokens": 4096,
      "fallback": "light"
    }
  },
  "agents": {
    "code-reviewer": "standard",
    "architect": "heavy",
    "formatter": "light"
  },
  "autonomous_jobs": {
    "nightly-scan": "local",
    "weekly-review": "standard"
  },
  "providers": {
    "anthropic": {
      "status": "active",
      "api_key_env": "ANTHROPIC_API_KEY",
      "models": ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5"],
      "base_url": "https://api.anthropic.com"
    },
    "ollama": {
      "status": "active",
      "api_key_env": null,
      "models": ["qwen3:8b"],
      "base_url": "http://localhost:11434"
    }
  },
  "cost_limits": {
    "daily_eur": 50,
    "monthly_eur": 800,
    "alert_threshold": 0.8
  }
}
EOF

cat > "$FIXTURE_DIR/disabled-provider.json" << 'EOF'
{
  "tiers": {
    "heavy": {
      "description": "Complex",
      "provider": "anthropic",
      "model": "claude-opus-5",
      "cli_name": "opus",
      "cost_per_1k_input": 0.015,
      "cost_per_1k_output": 0.075,
      "max_output_tokens": 16384,
      "fallback": "standard",
      "effort": "high"
    },
    "standard": {
      "description": "Routine",
      "provider": "openai",
      "model": "gpt-4o",
      "cli_name": null,
      "cost_per_1k_input": 0.005,
      "cost_per_1k_output": 0.015,
      "max_output_tokens": 8192,
      "fallback": "light",
      "effort": "medium"
    },
    "light": {
      "description": "Simple",
      "provider": "anthropic",
      "model": "claude-haiku-4-5",
      "cli_name": "haiku",
      "cost_per_1k_input": 0.0008,
      "cost_per_1k_output": 0.004,
      "max_output_tokens": 4096
    }
  },
  "agents": {},
  "autonomous_jobs": {},
  "providers": {
    "anthropic": {
      "status": "active",
      "api_key_env": "ANTHROPIC_API_KEY",
      "models": ["claude-opus-5", "claude-haiku-4-5"],
      "base_url": "https://api.anthropic.com"
    },
    "openai": {
      "status": "disabled",
      "api_key_env": "OPENAI_API_KEY",
      "models": ["gpt-4o"],
      "base_url": "https://api.openai.com"
    }
  }
}
EOF

echo "invalid json {{{" > "$FIXTURE_DIR/invalid-config.json"

# Temp usage log for cost-report tests
TEMP_USAGE_DIR=$(mktemp -d)
TEMP_USAGE_LOG="$TEMP_USAGE_DIR/usage.log"
TODAY=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
cat > "$TEMP_USAGE_LOG" << EOF
${TODAY} tier=standard model=claude-sonnet-5 provider=anthropic cost_in=0.003 cost_out=0.015
${TODAY} tier=heavy model=claude-opus-5 provider=anthropic cost_in=0.015 cost_out=0.075
${TODAY} tier=local model=qwen3:8b provider=ollama cost_in=0 cost_out=0
${TODAY} tier=standard model=claude-sonnet-5 provider=anthropic cost_in=0.003 cost_out=0.015
${TODAY} tier=light model=claude-haiku-4-5 provider=anthropic cost_in=0.0008 cost_out=0.004
EOF

# ── Tests ──────────────────────────────────────────────────────────

echo "=== Tier Selection ==="

output=$(MODEL_ROUTER_CONFIG="$FIXTURE_DIR/valid-config.json" MODEL_ROUTER_DATA="$TEMP_USAGE_DIR" bash "$ROUTER" heavy 2>/dev/null)
assert_contains "heavy tier returns opus" "claude-opus-5" "$output"
assert_contains "heavy tier sets provider" "anthropic" "$output"

output=$(MODEL_ROUTER_CONFIG="$FIXTURE_DIR/valid-config.json" MODEL_ROUTER_DATA="$TEMP_USAGE_DIR" bash "$ROUTER" standard 2>/dev/null)
assert_contains "standard tier returns sonnet" "claude-sonnet-5" "$output"
assert_contains "standard tier sets effort" "medium" "$output"

output=$(MODEL_ROUTER_CONFIG="$FIXTURE_DIR/valid-config.json" MODEL_ROUTER_DATA="$TEMP_USAGE_DIR" bash "$ROUTER" local 2>/dev/null)
assert_contains "local tier returns qwen" "qwen3:8b" "$output"
assert_contains "local tier uses ollama" "ollama" "$output"

echo ""
echo "=== Agent Lookup ==="

output=$(MODEL_ROUTER_CONFIG="$FIXTURE_DIR/valid-config.json" MODEL_ROUTER_DATA="$TEMP_USAGE_DIR" bash "$ROUTER" code-reviewer 2>/dev/null)
assert_contains "agent code-reviewer resolves to sonnet" "claude-sonnet-5" "$output"

output=$(MODEL_ROUTER_CONFIG="$FIXTURE_DIR/valid-config.json" MODEL_ROUTER_DATA="$TEMP_USAGE_DIR" bash "$ROUTER" architect 2>/dev/null)
assert_contains "agent architect resolves to opus" "claude-opus-5" "$output"

output=$(MODEL_ROUTER_CONFIG="$FIXTURE_DIR/valid-config.json" MODEL_ROUTER_DATA="$TEMP_USAGE_DIR" bash "$ROUTER" nightly-scan 2>/dev/null)
assert_contains "job nightly-scan resolves to qwen" "qwen3:8b" "$output"

output=$(MODEL_ROUTER_CONFIG="$FIXTURE_DIR/valid-config.json" MODEL_ROUTER_DATA="$TEMP_USAGE_DIR" bash "$ROUTER" unknown-agent 2>/dev/null)
assert_contains "unknown agent falls back to standard" "claude-sonnet-5" "$output"

echo ""
echo "=== Provider Fallback ==="

output=$(MODEL_ROUTER_CONFIG="$FIXTURE_DIR/disabled-provider.json" MODEL_ROUTER_DATA="$TEMP_USAGE_DIR" bash "$ROUTER" standard 2>&1)
assert_contains "disabled provider triggers fallback" "FALLBACK" "$output"
assert_contains "fallback reaches haiku" "claude-haiku-4-5" "$output"

echo ""
echo "=== Invalid Config ==="

output=$(MODEL_ROUTER_CONFIG="$FIXTURE_DIR/invalid-config.json" MODEL_ROUTER_DATA="$TEMP_USAGE_DIR" bash "$ROUTER" standard 2>&1)
assert_contains "invalid config sets degraded flag" "CONFIG_DEGRADED" "$output"
assert_contains "invalid config still outputs MODEL_ID" "MODEL_ID" "$output"
assert_contains "invalid config defaults to sonnet" "claude-sonnet-5" "$output"

echo ""
echo "=== Missing Config ==="

output=$(MODEL_ROUTER_CONFIG="/nonexistent/config.json" MODEL_ROUTER_DATA="$TEMP_USAGE_DIR" bash "$ROUTER" heavy 2>&1)
assert_contains "missing config defaults heavy to opus" "claude-opus-5" "$output"

output=$(MODEL_ROUTER_CONFIG="/nonexistent/config.json" MODEL_ROUTER_DATA="$TEMP_USAGE_DIR" bash "$ROUTER" light 2>&1)
assert_contains "missing config defaults light to haiku" "claude-haiku-4-5" "$output"

echo ""
echo "=== Output Safety ==="

output=$(MODEL_ROUTER_CONFIG="$FIXTURE_DIR/valid-config.json" MODEL_ROUTER_DATA="$TEMP_USAGE_DIR" bash "$ROUTER" standard 2>/dev/null)
assert_not_contains "no backticks in output" '`' "$output"
assert_not_contains "no dollar signs in values" "\$(" "$output"
assert_not_contains "no semicolons in output" ";" "$output"

echo ""
echo "=== Version ==="

output=$(bash "$ROUTER" --version 2>/dev/null)
assert_contains "version command works" "model-router" "$output"

echo ""
echo "=== Help ==="

output=$(bash "$ROUTER" --help 2>/dev/null)
assert_contains "help shows routing section" "ROUTING" "$output"
assert_contains "help shows tiers" "TIERS" "$output"

echo ""
echo "=== Info Command ==="

output=$(MODEL_ROUTER_CONFIG="$FIXTURE_DIR/valid-config.json" bash "$ROUTER" info 2>/dev/null)
assert_contains "info shows tiers" "heavy:" "$output"
assert_contains "info shows agents" "code-reviewer" "$output"
assert_contains "info shows cost limits" "Daily" "$output"

echo ""
echo "=== Recommend Command ==="

output=$(MODEL_ROUTER_CONFIG="$FIXTURE_DIR/valid-config.json" bash "$ROUTER" recommend code-reviewer 2>/dev/null)
assert_contains "recommend shows agent routing" "code-reviewer" "$output"
assert_contains "recommend shows cost" "Cost" "$output"

echo ""
echo "=== Cost Report ==="

COST_REPORT_DIR=$(mktemp -d)
COST_REPORT_LOG="$COST_REPORT_DIR/usage.log"
cat > "$COST_REPORT_LOG" << COSTEOF
${TODAY} tier=standard model=claude-sonnet-5 provider=anthropic cost_in=0.003 cost_out=0.015
${TODAY} tier=heavy model=claude-opus-5 provider=anthropic cost_in=0.015 cost_out=0.075
${TODAY} tier=local model=qwen3:8b provider=ollama cost_in=0 cost_out=0
COSTEOF
output=$(MODEL_ROUTER_DATA="$COST_REPORT_DIR" bash "$ROUTER" cost-report 2>/dev/null)
assert_contains "cost-report shows entries count" "3" "$output"
assert_contains "cost-report shows provider breakdown" "anthropic" "$output"
rm -rf "$COST_REPORT_DIR"

echo ""
echo "=== Usage Logging ==="

TEMP_LOG_DIR=$(mktemp -d)
MODEL_ROUTER_CONFIG="$FIXTURE_DIR/valid-config.json" MODEL_ROUTER_DATA="$TEMP_LOG_DIR" bash "$ROUTER" standard >/dev/null 2>&1
if [ -f "$TEMP_LOG_DIR/usage.log" ]; then
  log_content=$(cat "$TEMP_LOG_DIR/usage.log")
  assert_contains "usage log records tier" "tier=standard" "$log_content"
  assert_contains "usage log records provider" "provider=anthropic" "$log_content"
else
  echo "  FAIL: usage log not created"
  ((FAIL++))
fi

echo ""
echo "=== Health Command ==="

output=$(MODEL_ROUTER_CONFIG="$FIXTURE_DIR/disabled-provider.json" bash "$ROUTER" health 2>/dev/null)
assert_contains "health shows disabled providers" "DISABLED" "$output"

# ── Cleanup ────────────────────────────────────────────────────────

rm -rf "$TEMP_USAGE_DIR" "$TEMP_LOG_DIR"

echo ""
echo "════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
echo "════════════════════════════════════════"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
