setup() {
  local dir="${BATS_TEST_DIRNAME}"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "${dir}/core/guardrail.sh" ]]; then
      export GUARDRAIL_HOME="$dir"
      break
    fi
    dir="$(dirname "$dir")"
  done
  export TEST_HOME="/home/testuser"
  export HOME="${TEST_HOME}"
  # 自己保護ルールの ${GUARDRAIL_INSTALL_DIR} プレースホルダをテスト用パスへ固定する
  export GUARDRAIL_INSTALL_DIR="/home/testuser/ai-agent-guardrail"

  # shellcheck source=../../core/lib/match_file.sh
  source "${GUARDRAIL_HOME}/core/lib/match_file.sh"
  # shellcheck source=../../core/lib/builtins.sh
  source "${GUARDRAIL_HOME}/core/lib/builtins.sh"
}

@test "rm_wildcard_outside_home: rm * in /tmp is denied" {
  run builtin_rm_wildcard_outside_home "rm *" "/tmp" "/home/testuser"
  [ "$status" -eq 0 ]
}

@test "rm_wildcard_outside_home: rm -rf ./* in /tmp is denied" {
  run builtin_rm_wildcard_outside_home "rm -rf ./*" "/tmp" "/home/testuser"
  [ "$status" -eq 0 ]
}

@test "rm_wildcard_outside_home: rm * in HOME is allowed" {
  run builtin_rm_wildcard_outside_home "rm *" "/home/testuser/work" "/home/testuser"
  [ "$status" -eq 1 ]
}

@test "rm_wildcard_outside_home: rm file.txt without wildcard is allowed" {
  run builtin_rm_wildcard_outside_home "rm file.txt" "/tmp" "/home/testuser"
  [ "$status" -eq 1 ]
}

@test "rm_wildcard_outside_home: absolute path outside home with wildcard" {
  run builtin_rm_wildcard_outside_home "rm -rf /var/log/*" "/home/testuser" "/home/testuser"
  [ "$status" -eq 0 ]
}

@test "rm_wildcard_outside_home: empty home allows (fail-open at builtin level)" {
  run builtin_rm_wildcard_outside_home "rm *" "/tmp" ""
  [ "$status" -eq 1 ]
}

@test "rm_wildcard_outside_home: rm inside command substitution is detected" {
  run builtin_rm_wildcard_outside_home 'echo $(rm -rf /opt/*)' "/home/testuser" "/home/testuser"
  [ "$status" -eq 0 ]
}

@test "rm_wildcard_outside_home: rm inside backticks is detected" {
  run builtin_rm_wildcard_outside_home 'echo `rm -rf /opt/*`' "/home/testuser" "/home/testuser"
  [ "$status" -eq 0 ]
}

@test "rm_wildcard_outside_home: rm inside subshell parens is detected" {
  run builtin_rm_wildcard_outside_home '(rm -rf /var/log/*)' "/home/testuser" "/home/testuser"
  [ "$status" -eq 0 ]
}

# --- reads_denied_file: グロブ / インタプリタ / ラッパ ---

@test "reads_denied_file: glob cat .env* expands to real .env and is denied" {
  export GUARDRAIL_RULES_DIR="${GUARDRAIL_HOME}/rules"
  local proj="${BATS_TEST_TMPDIR}/proj"
  mkdir -p "$proj"
  : > "$proj/.env"
  run builtin_reads_denied_file "cat .env*" "$proj" "/home/testuser"
  [ "$status" -eq 0 ]
}

@test "reads_denied_file: glob cat .en? expands to real .env and is denied" {
  export GUARDRAIL_RULES_DIR="${GUARDRAIL_HOME}/rules"
  local proj="${BATS_TEST_TMPDIR}/proj2"
  mkdir -p "$proj"
  : > "$proj/.env"
  run builtin_reads_denied_file "cat .en?" "$proj" "/home/testuser"
  [ "$status" -eq 0 ]
}

@test "reads_denied_file: glob matching no sensitive file is allowed" {
  export GUARDRAIL_RULES_DIR="${GUARDRAIL_HOME}/rules"
  local proj="${BATS_TEST_TMPDIR}/proj3"
  mkdir -p "$proj"
  : > "$proj/README.md"
  run builtin_reads_denied_file "cat *.md" "$proj" "/home/testuser"
  [ "$status" -eq 1 ]
}

@test "reads_denied_file: interpreter trailing operand (ruby .env) is denied" {
  export GUARDRAIL_RULES_DIR="${GUARDRAIL_HOME}/rules"
  run builtin_reads_denied_file "ruby .env" "/home/testuser/project" "/home/testuser"
  [ "$status" -eq 0 ]
}

@test "reads_denied_file: jq into secrets.json is denied" {
  export GUARDRAIL_RULES_DIR="${GUARDRAIL_HOME}/rules"
  run builtin_reads_denied_file "jq .k secrets.json" "/home/testuser/app" "/home/testuser"
  [ "$status" -eq 0 ]
}

# --- writes_denied_file ---

@test "writes_denied_file: redirect echo > .env is denied" {
  export GUARDRAIL_RULES_DIR="${GUARDRAIL_HOME}/rules"
  run builtin_writes_denied_file "echo x > .env" "/home/testuser/project" "/home/testuser"
  [ "$status" -eq 0 ]
}

@test "writes_denied_file: tee .env is denied" {
  export GUARDRAIL_RULES_DIR="${GUARDRAIL_HOME}/rules"
  run builtin_writes_denied_file "echo x | tee .env" "/home/testuser/project" "/home/testuser"
  [ "$status" -eq 0 ]
}

@test "writes_denied_file: cp dest .env is denied" {
  export GUARDRAIL_RULES_DIR="${GUARDRAIL_HOME}/rules"
  run builtin_writes_denied_file "cp template .env" "/home/testuser/project" "/home/testuser"
  [ "$status" -eq 0 ]
}

@test "writes_denied_file: bash-write to rules json is denied (self-protection)" {
  export GUARDRAIL_RULES_DIR="${GUARDRAIL_HOME}/rules"
  run builtin_writes_denied_file "echo x > rules/deny-files.json" "/home/testuser/ai-agent-guardrail" "/home/testuser"
  [ "$status" -eq 0 ]
}

@test "writes_denied_file: benign redirect > out.log is allowed" {
  export GUARDRAIL_RULES_DIR="${GUARDRAIL_HOME}/rules"
  run builtin_writes_denied_file "echo x > out.log" "/home/testuser/project" "/home/testuser"
  [ "$status" -eq 1 ]
}

@test "writes_denied_file: stderr redirect 2>&1 is not treated as a write target" {
  export GUARDRAIL_RULES_DIR="${GUARDRAIL_HOME}/rules"
  run builtin_writes_denied_file "make build 2>&1" "/home/testuser/project" "/home/testuser"
  [ "$status" -eq 1 ]
}

# --- git_push_force_protected ---

@test "git_push_force_protected: --force origin main is denied" {
  run builtin_git_push_force_protected "git push --force origin main" "" ""
  [ "$status" -eq 0 ]
}

@test "git_push_force_protected: -f origin master is denied" {
  run builtin_git_push_force_protected "git push -f origin master" "" ""
  [ "$status" -eq 0 ]
}

@test "git_push_force_protected: force push to feature branch is allowed" {
  run builtin_git_push_force_protected "git push --force origin feature/x" "" ""
  [ "$status" -eq 1 ]
}

@test "git_push_force_protected: non-force push to main is allowed" {
  run builtin_git_push_force_protected "git push origin main" "" ""
  [ "$status" -eq 1 ]
}
