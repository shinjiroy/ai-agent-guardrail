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

FAIL_CLOSED="${GUARDRAIL_FAIL_CLOSED:-false}"

emit_deny() {
  jq -n --arg r "$1" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
}

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
  Grep)
    op="read"
    path="$(jq -r '.tool_input.path // empty' <<<"$input")"
    # path 省略時（カレント配下検索）は個別ファイル判定できないため素通し
    [[ -z "$path" ]] && exit 0
    ;;
  Write|Edit|MultiEdit|NotebookEdit)
    op="write"
    path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")"
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
  if [[ "$FAIL_CLOSED" == "true" ]]; then
    emit_deny "ガードレールの判定に失敗しました。操作はブロックされました。"
  fi
  exit 0
fi

decision="$(jq -r '.decision' <<<"$result")"
if [[ "$decision" == "deny" ]]; then
  reason="$(jq -r '.message' <<<"$result")"
  emit_deny "$reason"
fi

exit 0
