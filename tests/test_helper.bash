# bats-support / bats-assert（Docker イメージ内）。ローカルでは簡易スタブにフォールバック。
if [[ -f /opt/bats-support/load.bash ]]; then
  # shellcheck disable=SC1091
  load /opt/bats-support/load.bash
  # shellcheck disable=SC1091
  load /opt/bats-assert/load.bash
else
  assert_success() { [ "$status" -eq 0 ]; }
  assert_failure() { [ "$status" -ne 0 ]; }
fi

setup() {
  local dir="${BATS_TEST_DIRNAME}"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "${dir}/core/guardrail.sh" ]]; then
      export GUARDRAIL_HOME="$dir"
      break
    fi
    dir="$(dirname "$dir")"
  done
  export GUARDRAIL_RULES_DIR="${GUARDRAIL_HOME}/rules"
  export GUARDRAIL_SCRIPT="${GUARDRAIL_HOME}/core/guardrail.sh"
  export TEST_HOME="/home/testuser"
  export HOME="${TEST_HOME}"
}

run_guardrail() {
  local request="$1"
  run bash "$GUARDRAIL_SCRIPT" <<< "$request"
}

assert_decision() {
  local expected="$1"
  local actual
  actual="$(jq -r '.decision' <<<"$output")"
  [ "$actual" = "$expected" ]
}

assert_rule_id() {
  local expected="$1"
  local actual
  actual="$(jq -r '.rule_id' <<<"$output")"
  [ "$actual" = "$expected" ]
}

make_request() {
  jq -n \
    --arg operation "$1" \
    --arg path "${2:-}" \
    --arg command "${3:-}" \
    --arg cwd "${4:-}" \
    --arg home "${5:-${TEST_HOME}}" \
    '{operation: $operation, path: $path, command: $command, cwd: $cwd, home: $home} | with_entries(select(.value != ""))'
}
