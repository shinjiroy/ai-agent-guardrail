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

input="$(cat)"

file_path="$(jq -r '.file_path // empty' <<<"$input")"
cwd="$(jq -r '.cwd // empty' <<<"$input")"

req="$(jq -n \
  --arg agent cursor \
  --arg op read \
  --arg path "$file_path" \
  --arg cwd "$cwd" \
  '{agent: $agent, operation: $op, path: $path, cwd: $cwd}')"

if ! result="$(printf '%s' "$req" | "${GUARDRAIL_HOME}/core/guardrail.sh" 2>/dev/null)"; then
  if [[ "$FAIL_CLOSED" == "true" ]]; then
    jq -n --arg m "ガードレールの判定に失敗しました。操作はブロックされました。" \
      '{permission: "deny", user_message: $m, agent_message: $m}'
  else
    echo '{"permission":"allow"}'
  fi
  exit 0
fi

decision="$(jq -r '.decision' <<<"$result")"
if [[ "$decision" == "deny" ]]; then
  msg="$(jq -r '.message' <<<"$result")"
  jq -n --arg m "$msg" '{permission: "deny", user_message: $m, agent_message: $m}'
else
  echo '{"permission":"allow"}'
fi

exit 0
