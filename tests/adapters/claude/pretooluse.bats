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

@test "claude: cursor-compat Shell tool with curl|bash is denied" {
  run bash "$ADAPTER" < "${FIXTURES}/cursor-compat-shell-curl-pipe.json"
  assert_success
  assert_claude_deny
}

@test "claude: cursor-compat Shell tool with benign command is allowed" {
  run bash "$ADAPTER" <<< '{"tool_name":"Shell","tool_input":{"command":"ls -la","cwd":"/tmp"},"cwd":"","hook_event_name":"preToolUse"}'
  assert_success
  [ -z "$output" ]
}

@test "claude: cursor-compat Shell resolves cwd from tool_input (relative .env write)" {
  run bash "$ADAPTER" <<< '{"tool_name":"Shell","tool_input":{"command":"echo x > .env","cwd":"/home/testuser/project"},"cwd":"","hook_event_name":"preToolUse"}'
  assert_success
  assert_claude_deny
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
