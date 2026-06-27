load '../test_helper.bash'

# rules/*.json の「データとしての正しさ」を検証する。
# 全ルールを走査するため、ルールを追加すれば自動的に検査対象になる。
# （個々のルールの「挙動」は tests/behavior/cases.jsonl 側で検証する）

deny_files() { echo "${GUARDRAIL_HOME}/rules/deny-files.json"; }
deny_commands() { echo "${GUARDRAIL_HOME}/rules/deny-commands.json"; }
all_rule_files() { deny_files; deny_commands; }

@test "rules: each file is valid JSON with version and rules array" {
  local f
  for f in $(all_rule_files); do
    run jq -e 'has("version") and (.rules | type == "array") and (.rules | length > 0)' "$f"
    assert_success
  done
}

@test "rules: ids are unique across all rule files" {
  local dup
  dup="$(jq -r '.rules[].id' $(all_rule_files) | sort | uniq -d)"
  [ -z "$dup" ] || { echo "duplicate rule ids: $dup" >&2; false; }
}

@test "rules: every rule has required common fields (id, description, action=deny, message)" {
  local f bad
  for f in $(all_rule_files); do
    bad="$(jq -r '
      .rules[]
      | select(
          (.id | type != "string") or (.id == "")
          or (.description | type != "string") or (.description == "")
          or (.action != "deny")
          or (.message | type != "string") or (.message == "")
        )
      | (.id // "<no-id>")' "$f")"
    [ -z "$bad" ] || { echo "$f: rules with invalid common fields: $bad" >&2; false; }
  done
}

@test "deny-files: patterns non-empty and operations are a subset of read/write" {
  local bad
  bad="$(jq -r '
    .rules[]
    | select(
        (.patterns | type != "array") or (.patterns | length == 0)
        or (.operations | type != "array") or (.operations | length == 0)
        or (any(.operations[]; . != "read" and . != "write"))
      )
    | .id' "$(deny_files)")"
  [ -z "$bad" ] || { echo "invalid file rules: $bad" >&2; false; }
}

@test "deny-commands: match.type is regex/builtin with required subfields" {
  local bad
  bad="$(jq -r '
    .rules[]
    | select(
        (.match.type != "regex" and .match.type != "builtin")
        or (.match.type == "regex" and ((.match.pattern | type != "string") or (.match.pattern == "")))
        or (.match.type == "builtin" and ((.match.evaluator | type != "string") or (.match.evaluator == "")))
      )
    | .id' "$(deny_commands)")"
  [ -z "$bad" ] || { echo "invalid command rules: $bad" >&2; false; }
}

@test "deny-commands: every regex pattern compiles under grep -E" {
  local pat st
  while IFS= read -r pat; do
    [[ -z "$pat" ]] && continue
    # grep は不一致で 1、正規表現エラーで 2 を返す。1 は正常なので || で握る。
    st=0
    grep -E "$pat" >/dev/null 2>&1 <<< "" || st=$?
    [ "$st" -ne 2 ] || { echo "pattern does not compile: $pat" >&2; false; return; }
  done < <(jq -r '.rules[] | select(.match.type == "regex") | .match.pattern' "$(deny_commands)")
}

@test "deny-commands: every builtin evaluator is registered in builtin_dispatch" {
  source "${GUARDRAIL_HOME}/core/lib/json.sh"
  source "${GUARDRAIL_HOME}/core/lib/match_file.sh"
  source "${GUARDRAIL_HOME}/core/lib/builtins.sh"
  export GUARDRAIL_RULES_DIR="${GUARDRAIL_HOME}/rules"

  local ev
  while IFS= read -r ev; do
    [[ -z "$ev" ]] && continue
    run builtin_dispatch "$ev" "noop" "/tmp" "/home/testuser"
    refute_output --partial "unknown builtin evaluator"
  done < <(jq -r '.rules[] | select(.match.type == "builtin") | .match.evaluator' "$(deny_commands)")
}
