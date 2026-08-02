#!/bin/bash
# Example: Using model-router in a CI/CD pipeline
#
# Routes LLM calls to the cheapest suitable model based on task complexity.
# In CI, you typically want "light" for fast checks and "standard" for reviews.
set -euo pipefail

# Route to the right model for this task
eval "$(model-router light)"

echo "Using $MODEL_PROVIDER/$MODEL_ID (tier: $MODEL_TIER)"

# Example: Summarize a PR diff using the routed model
PR_DIFF=$(git diff HEAD~1 --stat 2>/dev/null || echo "no diff")

case "$MODEL_PROVIDER" in
  anthropic)
    # curl -s https://api.anthropic.com/v1/messages \
    #   -H "x-api-key: $ANTHROPIC_API_KEY" \
    #   -H "anthropic-version: 2023-06-01" \
    #   -H "content-type: application/json" \
    #   -d "$(jq -n --arg model "$MODEL_ID" --arg diff "$PR_DIFF" \
    #     '{model: $model, max_tokens: 500, messages: [{role: "user", content: ("Summarize: " + $diff)}]}')"
    echo "Would call Anthropic API with model=$MODEL_ID"
    ;;
  ollama)
    # curl -s http://localhost:11434/api/generate \
    #   -d "$(jq -n --arg model "$MODEL_ID" --arg prompt "Summarize: $PR_DIFF" \
    #     '{model: $model, prompt: $prompt, stream: false}')"
    echo "Would call Ollama with model=$MODEL_ID"
    ;;
esac

echo "Cost: \$${MODEL_COST_PER_1K_IN}/1K input, \$${MODEL_COST_PER_1K_OUT}/1K output"
