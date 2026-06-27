load 'test_helper.bash'

setup() {
  local dir="${BATS_TEST_DIRNAME}"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "${dir}/core/guardrail.sh" ]]; then
      export GUARDRAIL_HOME="$dir"
      break
    fi
    dir="$(dirname "$dir")"
  done
  export INSTALL_SCRIPT="${GUARDRAIL_HOME}/install.sh"
  export TEST_DIR="${BATS_TMPDIR}/guardrail-install-$$"
  mkdir -p "$TEST_DIR"
  export HOME="${TEST_DIR}/home"
  mkdir -p "$HOME"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "install.sh: claude user scope creates settings.json" {
  run bash "$INSTALL_SCRIPT" claude --scope user
  assert_success
  [ -f "${HOME}/.claude/settings.json" ]
  jq -e '.hooks.PreToolUse[0].hooks[0].command | endswith("/adapters/claude/pretooluse.sh")' \
    "${HOME}/.claude/settings.json" >/dev/null
}

@test "install.sh: cursor user scope creates hooks.json" {
  run bash "$INSTALL_SCRIPT" cursor --scope user
  assert_success
  [ -f "${HOME}/.cursor/hooks.json" ]
  jq -e '.hooks.beforeShellExecution[0].command | endswith("/adapters/cursor/before-shell.sh")' \
    "${HOME}/.cursor/hooks.json" >/dev/null
  jq -e '.hooks.beforeReadFile[0].command | endswith("/adapters/cursor/before-read-file.sh")' \
    "${HOME}/.cursor/hooks.json" >/dev/null
  jq -e '.hooks.afterFileEdit[0].command | endswith("/adapters/cursor/after-file-edit.sh")' \
    "${HOME}/.cursor/hooks.json" >/dev/null
}

@test "install.sh: cursor --fail-closed sets failClosed true" {
  run bash "$INSTALL_SCRIPT" cursor --scope user --fail-closed
  assert_success
  jq -e '.hooks.beforeShellExecution[0].failClosed == true' \
    "${HOME}/.cursor/hooks.json" >/dev/null
}

@test "install.sh: cursor re-install updates failClosed to true" {
  run bash "$INSTALL_SCRIPT" cursor --scope user
  assert_success
  jq -e '.hooks.beforeShellExecution[0].failClosed == false' \
    "${HOME}/.cursor/hooks.json" >/dev/null

  run bash "$INSTALL_SCRIPT" cursor --scope user --fail-closed
  assert_success
  jq -e '.hooks.beforeShellExecution[0].failClosed == true' \
    "${HOME}/.cursor/hooks.json" >/dev/null
  jq -e '.hooks.beforeReadFile[0].failClosed == true' \
    "${HOME}/.cursor/hooks.json" >/dev/null
}

@test "install.sh: cursor re-install does not duplicate entries" {
  run bash "$INSTALL_SCRIPT" cursor --scope user
  assert_success
  run bash "$INSTALL_SCRIPT" cursor --scope user --fail-closed
  assert_success
  jq -e '.hooks.beforeShellExecution | length == 1' "${HOME}/.cursor/hooks.json" >/dev/null
  jq -e '.hooks.beforeReadFile | length == 1' "${HOME}/.cursor/hooks.json" >/dev/null
  jq -e '.hooks.afterFileEdit | length == 1' "${HOME}/.cursor/hooks.json" >/dev/null
}

@test "install.sh: claude re-install does not duplicate entries" {
  run bash "$INSTALL_SCRIPT" claude --scope user
  assert_success
  run bash "$INSTALL_SCRIPT" claude --scope user
  assert_success
  jq -e '.hooks.PreToolUse | length == 1' "${HOME}/.claude/settings.json" >/dev/null
}

@test "install.sh: merges with existing claude settings" {
  mkdir -p "${HOME}/.claude"
  echo '{"existing": true}' > "${HOME}/.claude/settings.json"
  run bash "$INSTALL_SCRIPT" claude --scope user
  assert_success
  jq -e '.existing == true' "${HOME}/.claude/settings.json" >/dev/null
  jq -e '.hooks.PreToolUse | length >= 1' "${HOME}/.claude/settings.json" >/dev/null
}

@test "install.sh: rejects unknown agent" {
  run bash "$INSTALL_SCRIPT" unknown
  assert_failure
}
