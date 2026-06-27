load '../test_helper.bash'

# rules/*.json の挙動はこのデータ駆動テストで検証する。
# カバレッジを増やすときは cases.jsonl に1行追加するだけでよい（bash を書かない）。
# 各行: {desc, req:{operation,path,command,cwd,home}, decision, rule_id?}
#   - rule_id を省略した場合は decision のみ検証する（allow ケースなど）。

@test "behavior: all data-driven cases match expected decision" {
  local cases_file="${BATS_TEST_DIRNAME}/cases.jsonl"
  [ -f "$cases_file" ]

  local total=0 failures=0 report=""
  local line desc req exp_dec exp_rid out st act_dec act_rid

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    total=$((total + 1))

    desc="$(jq -r '.desc' <<<"$line")"
    req="$(jq -c '.req' <<<"$line")"
    exp_dec="$(jq -r '.decision' <<<"$line")"
    exp_rid="$(jq -r '.rule_id // empty' <<<"$line")"

    st=0
    out="$(printf '%s' "$req" | bash "$GUARDRAIL_SCRIPT")" || st=$?
    if [[ $st -ne 0 ]]; then
      report+="✗ [${desc}] engine exited ${st}"$'\n'
      failures=$((failures + 1))
      continue
    fi

    act_dec="$(jq -r '.decision' <<<"$out")"
    act_rid="$(jq -r '.rule_id // empty' <<<"$out")"

    if [[ "$act_dec" != "$exp_dec" ]]; then
      report+="✗ [${desc}] decision expected=${exp_dec} actual=${act_dec}"$'\n'
      failures=$((failures + 1))
      continue
    fi
    if [[ -n "$exp_rid" && "$act_rid" != "$exp_rid" ]]; then
      report+="✗ [${desc}] rule_id expected=${exp_rid} actual=${act_rid}"$'\n'
      failures=$((failures + 1))
    fi
  done < "$cases_file"

  if [[ $failures -gt 0 ]]; then
    printf 'ran %d cases, %d failed:\n%s' "$total" "$failures" "$report" >&2
  fi
  [ "$failures" -eq 0 ]
}
