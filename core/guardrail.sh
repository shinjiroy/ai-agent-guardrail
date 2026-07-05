#!/usr/bin/env bash
set -euo pipefail

GUARDRAIL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARDRAIL_RULES_DIR="${GUARDRAIL_RULES_DIR:-${GUARDRAIL_SCRIPT_DIR}/../rules}"
# 実行中のガードレール自身の設置先（core/ の親）。deny-files.json の
# ${GUARDRAIL_INSTALL_DIR} プレースホルダの解決に使う（自己保護ルールの適用範囲）。
GUARDRAIL_INSTALL_DIR="${GUARDRAIL_INSTALL_DIR:-$(cd "${GUARDRAIL_SCRIPT_DIR}/.." && pwd)}"
export GUARDRAIL_INSTALL_DIR

# shellcheck source=lib/json.sh
source "${GUARDRAIL_SCRIPT_DIR}/lib/json.sh"
# shellcheck source=lib/match_file.sh
source "${GUARDRAIL_SCRIPT_DIR}/lib/match_file.sh"
# shellcheck source=lib/builtins.sh
source "${GUARDRAIL_SCRIPT_DIR}/lib/builtins.sh"
# shellcheck source=lib/match_command.sh
source "${GUARDRAIL_SCRIPT_DIR}/lib/match_command.sh"

guardrail_evaluate_files_result() {
  local operation="$1"
  local path="$2"
  local cwd="$3"
  local rules_file="$4"

  local normalized_path rule_id
  normalized_path="$(normalize_path "$path" "$cwd")"

  if rule_id="$(denied_file_rule_id "$normalized_path" "$operation" "$rules_file")"; then
    local message
    message="$(jq -r --arg id "$rule_id" '.rules[] | select(.id == $id) | .message' "$rules_file")"
    json_output_result "deny" "$rule_id" "$message"
  else
    json_output_result "allow" "null" ""
  fi
}

guardrail_evaluate_commands() {
  local command="$1"
  local cwd="$2"
  local home="$3"
  local rules_file="$4"

  local rule_count i rule
  rule_count="$(jq '.rules | length' "$rules_file")"

  for (( i = 0; i < rule_count; i++ )); do
    rule="$(jq -c ".rules[$i]" "$rules_file")"
    if match_command_rule "$command" "$cwd" "$home" "$rule"; then
      local rule_id message
      rule_id="$(jq -r '.id' <<<"$rule")"
      message="$(jq -r '.message' <<<"$rule")"
      json_output_result "deny" "$rule_id" "$message"
      return 0
    fi
  done

  json_output_result "allow" "null" ""
}

main() {
  json_require_jq || exit 2

  local input
  input="$(json_read_stdin)" || exit 2
  json_validate_request "$input" || exit 2

  local operation path command cwd home
  operation="$(jq -r '.operation' <<<"$input")"
  path="$(jq -r '.path // empty' <<<"$input")"
  command="$(jq -r '.command // empty' <<<"$input")"
  cwd="$(jq -r '.cwd // empty' <<<"$input")"
  home="$(jq -r '.home // empty' <<<"$input")"
  if [[ -z "$home" ]]; then
    home="${HOME:-}"
  fi

  local deny_files="${GUARDRAIL_RULES_DIR}/deny-files.json"
  local deny_commands="${GUARDRAIL_RULES_DIR}/deny-commands.json"

  if [[ ! -f "$deny_files" ]] || [[ ! -f "$deny_commands" ]]; then
    echo "guardrail: rules files not found in ${GUARDRAIL_RULES_DIR}" >&2
    exit 2
  fi

  case "$operation" in
    read|write)
      guardrail_evaluate_files_result "$operation" "$path" "$cwd" "$deny_files"
      ;;
    exec)
      guardrail_evaluate_commands "$command" "$cwd" "$home" "$deny_commands"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
