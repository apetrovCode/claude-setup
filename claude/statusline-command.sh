#!/usr/bin/env bash
input=$(cat)

# Colors (ANSI bold)
BOLD_GREEN='\033[1;32m'
BOLD_YELLOW='\033[1;33m'
BOLD_CYAN='\033[1;36m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
DIM='\033[2m'
RESET='\033[0m'

SEP="${DIM} | ${RESET}"

# --- Repo name (from cwd) ---
cwd=$(echo "$input" | jq -r '.cwd // empty')
if [ -n "$cwd" ]; then
  repo_name=$(basename "$cwd")
  repo_part="${BOLD_GREEN}${repo_name}${RESET}"
else
  repo_part=""
fi

# --- Branch ---
branch=""
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
fi
if [ -n "$branch" ]; then
  branch_part="${BOLD_YELLOW}${branch}${RESET}"
else
  branch_part=""
fi

# --- Model + Effort ---
model=$(echo "$input" | jq -r '.model.display_name // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')
if [ -n "$model" ] && [ -n "$effort" ]; then
  model_part="${BOLD_CYAN}${model}:${effort}${RESET}"
elif [ -n "$model" ]; then
  model_part="${BOLD_CYAN}${model}${RESET}"
else
  model_part=""
fi

# --- Context % with color + emoji tiers ---
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used" ]; then
  used_int=$(printf '%.0f' "$used")
  if [ "$used_int" -ge 15 ]; then
    ctx_color="${RED}"
    ctx_emoji=" ⛔⛔⛔"
  elif [ "$used_int" -ge 9 ]; then
    ctx_color="${YELLOW}"
    ctx_emoji=" ⚠️⚠️"
  else
    ctx_color="${GREEN}"
    ctx_emoji=" 🟢"
  fi
  ctx_part="${ctx_color}Context: ${used_int}%${ctx_emoji}${RESET}"
else
  ctx_part=""
fi

# --- Assemble ---
parts=()
[ -n "$repo_part" ]   && parts+=("$repo_part")
[ -n "$branch_part" ] && parts+=("$branch_part")
[ -n "$model_part" ]  && parts+=("$model_part")
[ -n "$ctx_part" ]    && parts+=("$ctx_part")

output=""
for i in "${!parts[@]}"; do
  if [ $i -gt 0 ]; then
    output+="$SEP"
  fi
  output+="${parts[$i]}"
done

printf "%b" "$output"
