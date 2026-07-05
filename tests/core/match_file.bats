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

  # shellcheck source=../../core/lib/match_file.sh
  source "${GUARDRAIL_HOME}/core/lib/match_file.sh"
}

@test "glob: **/.env matches nested path" {
  run match_file_path "/home/user/project/.env" "**/.env"
  [ "$status" -eq 0 ]
}

@test "glob: **/.env matches root-level .env" {
  run match_file_path "/home/user/.env" "**/.env"
  [ "$status" -eq 0 ]
}

@test "glob: **/*.env matches config/app.env" {
  run match_file_path "/home/user/config/app.env" "**/*.env"
  [ "$status" -eq 0 ]
}

@test "glob: does not match README.md" {
  run match_file_path "/home/user/project/README.md" "**/.env"
  [ "$status" -eq 1 ]
}

@test "glob: **/.ssh/** matches id_rsa" {
  run match_file_path "/home/user/.ssh/id_rsa" "**/.ssh/**"
  [ "$status" -eq 0 ]
}

@test "placeholder: \${GUARDRAIL_INSTALL_DIR} expands to install dir" {
  export GUARDRAIL_INSTALL_DIR="/opt/guardrail"
  run expand_pattern_placeholders '${GUARDRAIL_INSTALL_DIR}/**'
  [ "$status" -eq 0 ]
  [ "$output" = "/opt/guardrail/**" ]
}

@test "placeholder: trailing slash in install dir is normalized" {
  export GUARDRAIL_INSTALL_DIR="/opt/guardrail/"
  run expand_pattern_placeholders '${GUARDRAIL_INSTALL_DIR}/rules/*.json'
  [ "$status" -eq 0 ]
  [ "$output" = "/opt/guardrail/rules/*.json" ]
}

@test "placeholder: unresolved placeholder returns failure (pattern is skipped)" {
  unset GUARDRAIL_INSTALL_DIR
  run expand_pattern_placeholders '${GUARDRAIL_INSTALL_DIR}/**'
  [ "$status" -eq 1 ]
}

@test "placeholder: pattern without placeholder passes through unchanged" {
  run expand_pattern_placeholders '**/.env'
  [ "$status" -eq 0 ]
  [ "$output" = "**/.env" ]
}

@test "normalize_path: relative path with cwd" {
  run normalize_path "foo/.env" "/home/user/project"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/home/user/project/foo/.env" ]]
}

@test "path_is_under_home: path inside home" {
  run path_is_under_home "/home/testuser/work/file" "/home/testuser"
  [ "$status" -eq 0 ]
}

@test "path_is_under_home: path outside home" {
  run path_is_under_home "/tmp/file" "/home/testuser"
  [ "$status" -eq 1 ]
}
