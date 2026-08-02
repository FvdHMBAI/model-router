#!/bin/bash
# Example: Nightly cron job with model-router
#
# Uses the cheapest local model by default, falls back to cloud if unavailable.
# Ideal for overnight batch processing where cost matters more than speed.
set -euo pipefail

LOG="/var/log/nightly-analysis.log"

# Try local first (free), fall back to light (cheap cloud)
eval "$(model-router local)" || eval "$(model-router light)"

echo "$(date): Using $MODEL_PROVIDER/$MODEL_ID" >> "$LOG"

# Example: Analyze server logs overnight
# ANALYSIS=$(curl -s http://localhost:11434/api/generate \
#   -d "$(jq -n --arg model "$MODEL_ID" \
#     --arg prompt "Analyze these logs for anomalies: $(tail -100 /var/log/syslog)" \
#     '{model: $model, prompt: $prompt, stream: false}')" \
#   | jq -r '.response')

echo "Nightly analysis complete with $MODEL_ID (cost: $MODEL_COST_PER_1K_IN/1K)" >> "$LOG"
