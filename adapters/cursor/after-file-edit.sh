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

GUARDRAIL_SCRIPT_DIR="${GUARDRAIL_HOME}/core"
GUARDRAIL_RULES_DIR="${GUARDRAIL_RULES_DIR:-${GUARDRAIL_HOME}/rules}"

# shellcheck source=../../core/lib/json.sh
source "${GUARDRAIL_SCRIPT_DIR}/lib/json.sh"
# shellcheck source=../../core/lib/match_file.sh
source "${GUARDRAIL_SCRIPT_DIR}/lib/match_file.sh"

input="$(cat)"

file_path="$(jq -r '.file_path // empty' <<<"$input")"
cwd="$(jq -r '.cwd // empty' <<<"$input")"

if [[ -z "$file_path" ]]; then
  exit 0
fi

normalized_path="$(normalize_path "$file_path" "$cwd")"
deny_files="${GUARDRAIL_RULES_DIR}/deny-files.json"

if [[ ! -f "$deny_files" ]]; then
  exit 0
fi

rule_count="$(jq '.rules | length' "$deny_files")"
for (( i = 0; i < rule_count; i++ )); do
  rule="$(jq -c ".rules[$i]" "$deny_files")"

  if ! jq -e '.operations | index("write") != null' <<<"$rule" >/dev/null; then
    continue
  fi

  patterns="$(jq -r '.patterns[]' <<<"$rule")"
  while IFS= read -r pattern; do
    if match_file_path "$normalized_path" "$pattern"; then
      msg="$(jq -r '.message' <<<"$rule")"
      jq -n \
        --arg m "⚠️ 機密ファイルが編集されました: ${normalized_path}. ${msg}" \
        --arg f "$normalized_path" \
        --arg rid "$(jq -r '.id' <<<"$rule")" \
        '{
          user_message: $m,
          agent_message: $m,
          metadata: { file_path: $f, rule_id: $rid, event: "afterFileEdit" }
        }'
      exit 0
    fi
  done <<<"$patterns"
done

exit 0
