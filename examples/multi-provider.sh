#!/bin/bash
# Example: Multi-provider failover with model-router
#
# Demonstrates how model-router handles provider outages gracefully.
# The fallback chain is configured in model-routing.json per tier.
set -euo pipefail

echo "=== Multi-Provider Failover Demo ==="
echo ""

# Show what each tier resolves to
for tier in heavy standard light local; do
  output=$(model-router "$tier" 2>/dev/null)
  model=$(echo "$output" | grep MODEL_ID | cut -d"'" -f2)
  provider=$(echo "$output" | grep MODEL_PROVIDER | cut -d"'" -f2)
  cost_in=$(echo "$output" | grep COST_PER_1K_IN | cut -d"'" -f2)
  printf "  %-12s -> %-12s %-20s (\$%s/1K input)\n" "$tier" "$provider" "$model" "$cost_in"
done

echo ""

# Check provider health
echo "Provider health:"
model-router health 2>/dev/null | grep -E '^\s'

echo ""

# Show agent routing
echo "Agent routing:"
for agent in code-reviewer architect formatter; do
  model-router recommend "$agent" 2>/dev/null | head -1
done
