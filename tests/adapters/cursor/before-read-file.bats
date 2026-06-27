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
  export ADAPTER="${GUARDRAIL_HOME}/adapters/cursor/before-read-file.sh"
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

@test "cursor read: .env is denied" {
  run bash "$ADAPTER" < "${FIXTURES}/read-dotenv.json"
  assert_success
  assert_permission deny
}

@test "cursor read: README.md is allowed" {
  run bash "$ADAPTER" < "${FIXTURES}/read-readme.json"
  assert_success
  assert_permission allow
}
