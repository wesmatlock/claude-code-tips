#!/bin/bash

# Claude Code status line script
# Shows: Opus 4.5 | Daft | main | ████░░░░░░ 42%

input=$(cat)

# Extract model, directory, and cwd
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "?"')
cwd=$(echo "$input" | jq -r '.cwd // empty')
dir=$(basename "$cwd" 2>/dev/null || echo "?")

# Get git branch
branch=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
fi

# Get transcript path for context calculation
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

# Calculate context bar
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    context_length=$(jq -s '
        map(select(.message.usage and .isSidechain != true and .isApiErrorMessage != true)) |
        last |
        if . then
            (.message.usage.input_tokens // 0) +
            (.message.usage.cache_read_input_tokens // 0) +
            (.message.usage.cache_creation_input_tokens // 0)
        else 0 end
    ' < "$transcript_path")

    max_context=200000
    bar_width=10

    if [[ "$context_length" -gt 0 ]]; then
        pct=$((context_length * 100 / max_context))
    else
        pct=0
    fi

    [[ $pct -gt 100 ]] && pct=100

    filled=$((pct * bar_width / 100))
    empty=$((bar_width - filled))

    bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    ctx="${bar} ${pct}%"
else
    ctx="░░░░░░░░░░ ?%"
fi

# Build output: Model | Dir | Branch | Context
output="${model} | ${dir}"
[[ -n "$branch" ]] && output+=" | ${branch}"
output+=" | ${ctx}"

echo "$output"
