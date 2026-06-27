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
  export ADAPTER="${GUARDRAIL_HOME}/adapters/cursor/after-file-edit.sh"
  export TEST_HOME="/home/testuser"
  export HOME="${TEST_HOME}"
}

@test "cursor afterFileEdit: .env edit emits warning" {
  run bash "$ADAPTER" <<< '{"file_path":"/home/user/project/.env","cwd":"/home/user/project"}'
  assert_success
  [[ "$output" == *'"user_message"'* ]]
  [[ "$output" == *'機密ファイルが編集されました'* ]]
}

@test "cursor afterFileEdit: README.md edit is silent" {
  run bash "$ADAPTER" <<< '{"file_path":"/home/user/project/README.md","cwd":"/home/user/project"}'
  assert_success
  [ -z "$output" ]
}
