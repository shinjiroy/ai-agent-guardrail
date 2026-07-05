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
  # 既定のインストール先を偽 HOME 配下に固定する
  unset XDG_DATA_HOME GUARDRAIL_INSTALL_DIR
  export DEFAULT_INSTALL_DIR="${HOME}/.local/share/ai-agent-guardrail"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "install.sh: claude user scope creates settings.json pointing at install dir" {
  run bash "$INSTALL_SCRIPT" claude --scope user
  assert_success
  [ -f "${HOME}/.claude/settings.json" ]
  jq -e --arg cmd "${DEFAULT_INSTALL_DIR}/adapters/claude/pretooluse.sh" \
    '.hooks.PreToolUse[0].hooks[0].command == $cmd' \
    "${HOME}/.claude/settings.json" >/dev/null
}

@test "install.sh: cursor user scope creates hooks.json pointing at install dir" {
  run bash "$INSTALL_SCRIPT" cursor --scope user
  assert_success
  [ -f "${HOME}/.cursor/hooks.json" ]
  jq -e --arg cmd "${DEFAULT_INSTALL_DIR}/adapters/cursor/before-shell.sh" \
    '.hooks.beforeShellExecution[0].command == $cmd' \
    "${HOME}/.cursor/hooks.json" >/dev/null
  jq -e --arg cmd "${DEFAULT_INSTALL_DIR}/adapters/cursor/before-read-file.sh" \
    '.hooks.beforeReadFile[0].command == $cmd' \
    "${HOME}/.cursor/hooks.json" >/dev/null
  jq -e --arg cmd "${DEFAULT_INSTALL_DIR}/adapters/cursor/after-file-edit.sh" \
    '.hooks.afterFileEdit[0].command == $cmd' \
    "${HOME}/.cursor/hooks.json" >/dev/null
}

@test "install.sh: copies core/adapters/rules into the default install dir" {
  run bash "$INSTALL_SCRIPT" claude --scope user
  assert_success
  [ -f "${DEFAULT_INSTALL_DIR}/core/guardrail.sh" ]
  [ -f "${DEFAULT_INSTALL_DIR}/core/lib/match_file.sh" ]
  [ -x "${DEFAULT_INSTALL_DIR}/adapters/claude/pretooluse.sh" ]
  [ -f "${DEFAULT_INSTALL_DIR}/rules/deny-files.json" ]
  [ -f "${DEFAULT_INSTALL_DIR}/rules/deny-commands.json" ]
}

@test "install.sh: --install-dir overrides the destination" {
  local custom="${TEST_DIR}/opt/guardrail"
  run bash "$INSTALL_SCRIPT" claude --scope user --install-dir "$custom"
  assert_success
  [ -f "${custom}/core/guardrail.sh" ]
  jq -e --arg cmd "${custom}/adapters/claude/pretooluse.sh" \
    '.hooks.PreToolUse[0].hooks[0].command == $cmd' \
    "${HOME}/.claude/settings.json" >/dev/null
}

@test "install.sh: re-install refreshes the installed copy (stale files removed)" {
  run bash "$INSTALL_SCRIPT" claude --scope user
  assert_success
  touch "${DEFAULT_INSTALL_DIR}/rules/stale.json"
  run bash "$INSTALL_SCRIPT" claude --scope user
  assert_success
  [ ! -f "${DEFAULT_INSTALL_DIR}/rules/stale.json" ]
}

@test "install.sh: installed engine denies writes to install dir but allows dev clone" {
  run bash "$INSTALL_SCRIPT" claude --scope user
  assert_success

  local out
  out="$(jq -n --arg p "${DEFAULT_INSTALL_DIR}/rules/deny-files.json" \
    '{operation: "write", path: $p}' | bash "${DEFAULT_INSTALL_DIR}/core/guardrail.sh")"
  [ "$(jq -r '.decision' <<<"$out")" = "deny" ]
  [ "$(jq -r '.rule_id' <<<"$out")" = "guardrail-self-protection" ]

  out="$(jq -n --arg p "${GUARDRAIL_HOME}/rules/deny-files.json" \
    '{operation: "write", path: $p}' | bash "${DEFAULT_INSTALL_DIR}/core/guardrail.sh")"
  [ "$(jq -r '.decision' <<<"$out")" = "allow" ]
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

@test "install.sh: claude removes stale guardrail entries pointing at old paths" {
  mkdir -p "${HOME}/.claude"
  jq -n '{hooks: {PreToolUse: [
    {matcher: "Bash", hooks: [{type: "command", command: "/old/clone/adapters/claude/pretooluse.sh", timeout: 10}]},
    {matcher: "Bash", hooks: [{type: "command", command: "/somewhere/unrelated-hook.sh"}]}
  ]}}' > "${HOME}/.claude/settings.json"

  run bash "$INSTALL_SCRIPT" claude --scope user
  assert_success
  # 旧ガードレールエントリは消え、無関係フック + 新エントリの2件になる
  jq -e '.hooks.PreToolUse | length == 2' "${HOME}/.claude/settings.json" >/dev/null
  jq -e '[.hooks.PreToolUse[].hooks[0].command] | index("/old/clone/adapters/claude/pretooluse.sh") == null' \
    "${HOME}/.claude/settings.json" >/dev/null
  jq -e '[.hooks.PreToolUse[].hooks[0].command] | index("/somewhere/unrelated-hook.sh") != null' \
    "${HOME}/.claude/settings.json" >/dev/null
  jq -e --arg cmd "${DEFAULT_INSTALL_DIR}/adapters/claude/pretooluse.sh" \
    '[.hooks.PreToolUse[].hooks[0].command] | index($cmd) != null' \
    "${HOME}/.claude/settings.json" >/dev/null
}

@test "install.sh: claude keeps entries that bundle guardrail with other hooks" {
  mkdir -p "${HOME}/.claude"
  # 1エントリに複数フックが同居する場合は他人のフックを巻き込まないよう除去しない
  jq -n '{hooks: {PreToolUse: [
    {matcher: "Bash", hooks: [
      {type: "command", command: "/somewhere/other.sh"},
      {type: "command", command: "/old/clone/adapters/claude/pretooluse.sh"}
    ]}
  ]}}' > "${HOME}/.claude/settings.json"

  run bash "$INSTALL_SCRIPT" claude --scope user
  assert_success
  jq -e '.hooks.PreToolUse | length == 2' "${HOME}/.claude/settings.json" >/dev/null
  jq -e '[.hooks.PreToolUse[].hooks[].command] | index("/somewhere/other.sh") != null' \
    "${HOME}/.claude/settings.json" >/dev/null
}

@test "install.sh: cursor removes stale guardrail entries but keeps unrelated hooks" {
  mkdir -p "${HOME}/.cursor"
  jq -n '{hooks: {
    beforeShellExecution: [
      {command: "/old/clone/adapters/cursor/before-shell.sh", type: "command", failClosed: true},
      {command: "/somewhere/unrelated-hook.sh", type: "command"}
    ],
    beforeReadFile: [
      {command: "/old/clone/adapters/cursor/before-read-file.sh", type: "command", failClosed: true}
    ],
    afterFileEdit: [
      {command: "/old/clone/adapters/cursor/after-file-edit.sh", type: "command"}
    ]
  }}' > "${HOME}/.cursor/hooks.json"

  run bash "$INSTALL_SCRIPT" cursor --scope user
  assert_success
  jq -e '.hooks.beforeShellExecution | length == 2' "${HOME}/.cursor/hooks.json" >/dev/null
  jq -e '[.hooks.beforeShellExecution[].command] | index("/old/clone/adapters/cursor/before-shell.sh") == null' \
    "${HOME}/.cursor/hooks.json" >/dev/null
  jq -e '[.hooks.beforeShellExecution[].command] | index("/somewhere/unrelated-hook.sh") != null' \
    "${HOME}/.cursor/hooks.json" >/dev/null
  jq -e '.hooks.beforeReadFile | length == 1' "${HOME}/.cursor/hooks.json" >/dev/null
  jq -e '.hooks.afterFileEdit | length == 1' "${HOME}/.cursor/hooks.json" >/dev/null
  jq -e --arg cmd "${DEFAULT_INSTALL_DIR}/adapters/cursor/before-read-file.sh" \
    '.hooks.beforeReadFile[0].command == $cmd' "${HOME}/.cursor/hooks.json" >/dev/null
}

@test "install.sh: rejects unknown agent" {
  run bash "$INSTALL_SCRIPT" unknown
  assert_failure
}
