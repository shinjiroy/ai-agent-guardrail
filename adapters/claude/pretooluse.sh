#!/usr/bin/env bash
set -euo pipefail

resolve_guardrail_home() {
  if [[ -n "${GUARDRAIL_HOME:-}" ]]; then
    printf '%s' "$GUARDRAIL_HOME"
    return 0
  fi
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  printf '%s' "$script_dir"
}

GUARDRAIL_HOME="$(resolve_guardrail_home)"
export GUARDRAIL_HOME

input="$(cat)"

tool="$(jq -r '.tool_name // empty' <<<"$input")"
cwd="$(jq -r '.cwd // empty' <<<"$input")"

op=""
path=""
command=""

case "$tool" in
  Bash)
    op="exec"
    command="$(jq -r '.tool_input.command // empty' <<<"$input")"
    ;;
  Read)
    op="read"
    path="$(jq -r '.tool_input.file_path // empty' <<<"$input")"
    ;;
  Write|Edit|MultiEdit)
    op="write"
    path="$(jq -r '.tool_input.file_path // empty' <<<"$input")"
    ;;
  *)
    exit 0
    ;;
esac

req="$(jq -n \
  --arg agent claude \
  --arg op "$op" \
  --arg path "$path" \
  --arg command "$command" \
  --arg cwd "$cwd" \
  '{agent: $agent, operation: $op, path: $path, command: $command, cwd: $cwd}')"

if ! result="$(printf '%s' "$req" | "${GUARDRAIL_HOME}/core/guardrail.sh" 2>/dev/null)"; then
  exit 0
fi

decision="$(jq -r '.decision' <<<"$result")"
if [[ "$decision" == "deny" ]]; then
  reason="$(jq -r '.message' <<<"$result")"
  jq -n \
    --arg r "$reason" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
fi

exit 0
