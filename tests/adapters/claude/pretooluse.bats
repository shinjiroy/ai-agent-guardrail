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
  export ADAPTER="${GUARDRAIL_HOME}/adapters/claude/pretooluse.sh"
  export FIXTURES="${GUARDRAIL_HOME}/tests/fixtures/claude"
  export TEST_HOME="/home/testuser"
  export HOME="${TEST_HOME}"
}

assert_claude_deny() {
  [[ "$output" == *'"permissionDecision": "deny"'* ]]
}

@test "claude: curl|bash is denied" {
  run bash "$ADAPTER" < "${FIXTURES}/bash-curl-pipe.json"
  assert_success
  assert_claude_deny
}

@test "claude: read .env is denied" {
  run bash "$ADAPTER" < "${FIXTURES}/read-dotenv.json"
  assert_success
  assert_claude_deny
}

@test "claude: ls is allowed (no output)" {
  run bash "$ADAPTER" < "${FIXTURES}/bash-ls.json"
  assert_success
  [ -z "$output" ]
}

@test "claude: unknown tool passes through" {
  run bash "$ADAPTER" <<< '{"tool_name":"Grep","tool_input":{}}'
  assert_success
  [ -z "$output" ]
}

@test "claude: engine failure is fail-open" {
  run env GUARDRAIL_RULES_DIR="/nonexistent/rules" bash "$ADAPTER" < "${FIXTURES}/bash-curl-pipe.json"
  assert_success
  [ -z "$output" ]
}
