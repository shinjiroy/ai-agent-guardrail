load '../../test_helper.bash'

setup() {
  local dir="${BATS_TEST_DIRNAME}"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "${dir}/core/guardrail.sh" ]]; then
      export GUARDRAIL_HOME="$dir"
      break
    fi
    dir="$(dirname "$dir")"
  done
  export ADAPTER="${GUARDRAIL_HOME}/adapters/cursor/before-shell.sh"
  export FIXTURES="${GUARDRAIL_HOME}/tests/fixtures/cursor"
  export TEST_HOME="/home/testuser"
  export HOME="${TEST_HOME}"
}

assert_permission() {
  local expected="$1"
  local actual
  actual="$(jq -r '.permission // empty' <<<"$output")"
  [ "$actual" = "$expected" ]
}

@test "cursor shell: curl|bash is denied" {
  run bash "$ADAPTER" < "${FIXTURES}/bash-curl-pipe.json"
  assert_success
  assert_permission deny
}

@test "cursor shell: ls is allowed" {
  run bash "$ADAPTER" <<< '{"command":"ls -la","cwd":"/home/user"}'
  assert_success
  assert_permission allow
}

@test "cursor shell: engine failure is fail-open" {
  run env GUARDRAIL_RULES_DIR="/nonexistent/rules" bash "$ADAPTER" < "${FIXTURES}/bash-curl-pipe.json"
  assert_success
  assert_permission allow
}

@test "cursor shell: engine failure is fail-closed when configured" {
  run env GUARDRAIL_RULES_DIR="/nonexistent/rules" GUARDRAIL_FAIL_CLOSED=true bash "$ADAPTER" < "${FIXTURES}/bash-curl-pipe.json"
  assert_success
  assert_permission deny
}
