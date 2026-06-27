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
