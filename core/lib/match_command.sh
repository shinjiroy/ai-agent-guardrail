#!/usr/bin/env bash
# コマンド文字列に対する regex / builtin 評価

match_command_regex() {
  local command="$1"
  local pattern="$2"

  if printf '%s\n' "$command" | grep -Eq "$pattern"; then
    return 0
  fi
  return 1
}

match_command_rule() {
  local command="$1"
  local cwd="$2"
  local home="$3"
  local rule_json="$4"

  local match_type pattern evaluator

  match_type="$(jq -r '.match.type' <<<"$rule_json")"
  case "$match_type" in
    regex)
      pattern="$(jq -r '.match.pattern' <<<"$rule_json")"
      match_command_regex "$command" "$pattern"
      ;;
    builtin)
      evaluator="$(jq -r '.match.evaluator' <<<"$rule_json")"
      builtin_dispatch "$evaluator" "$command" "$cwd" "$home"
      ;;
    *)
      echo "guardrail: unknown match type: $match_type" >&2
      return 1
      ;;
  esac
}
