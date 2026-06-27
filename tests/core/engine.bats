load '../test_helper.bash'

# エンジン本体の「ロジック」を検証する（ルール内容には依存しない）。
# 入力バリデーションと異常系のみを扱う。各ルールの挙動は
# tests/behavior/cases.jsonl、データとしての正しさは tests/rules/validation.bats で検証する。

@test "engine: empty stdin is rejected" {
  run bash "$GUARDRAIL_SCRIPT" <<< ""
  [ "$status" -eq 2 ]
}

@test "engine: missing operation is rejected" {
  run bash "$GUARDRAIL_SCRIPT" <<< '{"path":"/home/testuser/.env"}'
  [ "$status" -eq 2 ]
}

@test "engine: invalid operation is rejected" {
  run bash "$GUARDRAIL_SCRIPT" <<< '{"operation":"chmod","path":"/x"}'
  [ "$status" -eq 2 ]
}

@test "engine: read without path is rejected" {
  run bash "$GUARDRAIL_SCRIPT" <<< '{"operation":"read"}'
  [ "$status" -eq 2 ]
}

@test "engine: exec without command is rejected" {
  run bash "$GUARDRAIL_SCRIPT" <<< '{"operation":"exec"}'
  [ "$status" -eq 2 ]
}

@test "engine: fails when rules dir is missing" {
  GUARDRAIL_RULES_DIR="/nonexistent/rules" run bash "$GUARDRAIL_SCRIPT" <<< "$(make_request read "/home/testuser/.env")"
  [ "$status" -eq 2 ]
}

@test "engine: well-formed allow request exits 0 with decision allow" {
  run_guardrail "$(make_request read "/home/testuser/project/README.md")"
  assert_success
  assert_decision allow
}

@test "engine: well-formed deny request exits 0 with decision deny" {
  run_guardrail "$(make_request read "/home/testuser/project/.env")"
  assert_success
  assert_decision deny
}
