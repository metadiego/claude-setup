#!/bin/bash
# Continuous Learning - Session Evaluator (Stop hook)
#
# Reads the Stop hook payload from stdin, gates on session length, and emits
# a {"decision": "block", "reason": ...} JSON response that prompts the
# running Claude to perform ONE pattern-extraction pass before stopping.
#
# Safeguards:
#   - stop_hook_active guard prevents infinite stop loops
#   - per-session marker file in /tmp ensures at most one extraction per session
#
# Hook config (in ~/.claude/settings.json):
# {
#   "hooks": {
#     "Stop": [{
#       "hooks": [{
#         "type": "command",
#         "command": "~/.claude/skills/continuous-learning/evaluate-session.sh"
#       }]
#     }]
#   }
# }

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

MIN_SESSION_LENGTH=10
PROMPT_EXTRACTION=true
LEARNED_SKILLS_PATH="$HOME/.claude/skills/learned"

HAS_JQ=false
if command -v jq &>/dev/null; then
  HAS_JQ=true
fi

if [ -f "$CONFIG_FILE" ] && [ "$HAS_JQ" = true ]; then
  MIN_SESSION_LENGTH=$(jq -r '.min_session_length // 10' "$CONFIG_FILE")
  PROMPT_EXTRACTION=$(jq -r '.prompt_extraction // true' "$CONFIG_FILE")
  LEARNED_SKILLS_PATH=$(jq -r '.learned_skills_path // "~/.claude/skills/learned/"' "$CONFIG_FILE" | sed "s|^~|$HOME|")
fi

mkdir -p "$LEARNED_SKILLS_PATH"

stdin_data=$(cat)

# Parse hook payload. Stop hooks receive: session_id, transcript_path, stop_hook_active.
if [ "$HAS_JQ" = true ]; then
  transcript_path=$(echo "$stdin_data" | jq -r '.transcript_path // ""')
  session_id=$(echo "$stdin_data" | jq -r '.session_id // ""')
  stop_hook_active=$(echo "$stdin_data" | jq -r '.stop_hook_active // false')
else
  transcript_path=$(echo "$stdin_data" | grep -o '"transcript_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')
  session_id=$(echo "$stdin_data" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')
  stop_hook_active=$(echo "$stdin_data" | grep -o '"stop_hook_active"[[:space:]]*:[[:space:]]*true' | head -1 | grep -o 'true' || echo "false")
fi

# Loop guard: if we already blocked once, let Claude stop.
if [ "$stop_hook_active" = "true" ]; then
  exit 0
fi

if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
  exit 0
fi

# Once per session: skip if already evaluated.
marker="/tmp/continuous-learning-${session_id:-unknown}"
if [ -f "$marker" ]; then
  exit 0
fi

message_count=$(grep -c '"type":"user"' "$transcript_path" 2>/dev/null || echo "0")

if [ "$message_count" -lt "$MIN_SESSION_LENGTH" ]; then
  exit 0
fi

touch "$marker"

if [ "$PROMPT_EXTRACTION" != "true" ]; then
  # Legacy ECC v1 behavior: stderr signal only (rarely acted on).
  echo "[ContinuousLearning] Session has $message_count messages - evaluate for extractable patterns" >&2
  echo "[ContinuousLearning] Save learned skills to: $LEARNED_SKILLS_PATH" >&2
  exit 0
fi

reason="This session has $message_count user messages. Before stopping, run one continuous-learning extraction pass: review the session for reusable patterns (error_resolution, user_corrections, workarounds, debugging_techniques, project_specific). Propose candidate patterns to the user (name, category, one-line gist) and ask which to store; only write approved ones to $LEARNED_SKILLS_PATH<skill-name>/SKILL.md with YAML frontmatter (name, description starting with 'Use when...'). Check for existing learned skills covering the same pattern and offer updates instead of duplicates. Ignore simple typos, one-time fixes, and external API issues. If nothing qualifies, say so. Then stop. See ~/.claude/skills/continuous-learning/SKILL.md for the format."

if [ "$HAS_JQ" = true ]; then
  jq -n --arg reason "$reason" '{"decision": "block", "reason": $reason}'
else
  printf '{"decision": "block", "reason": "%s"}\n' "$(echo "$reason" | sed 's/"/\\"/g')"
fi

exit 0
