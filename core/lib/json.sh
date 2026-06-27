#!/usr/bin/env bash
# jq ラッパーと標準判定リクエストのバリデーション

json_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "guardrail: jq is required but not installed" >&2
    return 1
  fi
}

json_read_stdin() {
  local input
  input="$(cat)"
  if [[ -z "$input" ]]; then
    echo "guardrail: empty input" >&2
    return 1
  fi
  printf '%s' "$input"
}

json_validate_request() {
  local input="$1"
  local operation path command

  operation="$(jq -r '.operation // empty' <<<"$input")"
  case "$operation" in
    read|write)
      path="$(jq -r '.path // empty' <<<"$input")"
      if [[ -z "$path" ]]; then
        echo "guardrail: path is required for operation=$operation" >&2
        return 1
      fi
      ;;
    exec)
      command="$(jq -r '.command // empty' <<<"$input")"
      if [[ -z "$command" ]]; then
        echo "guardrail: command is required for operation=exec" >&2
        return 1
      fi
      ;;
    *)
      echo "guardrail: invalid or missing operation: $operation" >&2
      return 1
      ;;
  esac
}

json_output_result() {
  local decision="$1"
  local rule_id="$2"
  local message="$3"

  jq -n \
    --arg decision "$decision" \
    --arg rule_id "${rule_id:-null}" \
    --arg message "${message:-}" \
    '{
      decision: $decision,
      rule_id: (if $rule_id == "null" or $rule_id == "" then null else $rule_id end),
      message: $message
    }'
}
