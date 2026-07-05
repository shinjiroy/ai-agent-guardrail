#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install.sh <agent> [--scope user|project] [--fail-closed]

Install guardrail hooks for the specified AI coding agent.

Arguments:
  agent          claude | cursor

Options:
  --scope        user (default) or project
  --fail-closed  Enable fail-closed policy for Cursor hooks
  -h, --help     Show this help
EOF
}

resolve_guardrail_home() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  printf '%s' "$script_dir"
}

GUARDRAIL_HOME="$(resolve_guardrail_home)"
AGENT=""
SCOPE="user"
FAIL_CLOSED="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --scope)
      SCOPE="${2:-}"
      shift 2
      ;;
    --fail-closed)
      FAIL_CLOSED="true"
      shift
      ;;
    claude|cursor)
      AGENT="$1"
      shift
      ;;
    *)
      echo "install.sh: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$AGENT" ]]; then
  echo "install.sh: agent is required" >&2
  usage >&2
  exit 1
fi

if [[ "$SCOPE" != "user" && "$SCOPE" != "project" ]]; then
  echo "install.sh: scope must be user or project" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "install.sh: jq is required" >&2
  exit 1
fi

install_claude() {
  local settings_file hook_cmd
  if [[ "$SCOPE" == "user" ]]; then
    settings_file="${HOME}/.claude/settings.json"
  else
    settings_file="${PWD}/.claude/settings.json"
  fi

  hook_cmd="${GUARDRAIL_HOME}/adapters/claude/pretooluse.sh"
  mkdir -p "$(dirname "$settings_file")"

  local hook_entry
  hook_entry="$(jq -n \
    --arg cmd "$hook_cmd" \
    '{
      matcher: "Bash|Read|Grep|Write|Edit|MultiEdit|NotebookEdit",
      hooks: [{type: "command", command: $cmd, timeout: 10}]
    }')"

  if [[ -f "$settings_file" ]]; then
    jq --argjson entry "$hook_entry" \
      '.hooks.PreToolUse = (((.hooks.PreToolUse // []) | map(select(.hooks[0].command != $entry.hooks[0].command))) + [$entry])' \
      "$settings_file" > "${settings_file}.tmp"
    mv "${settings_file}.tmp" "$settings_file"
  else
    jq -n --argjson entry "$hook_entry" \
      '{hooks: {PreToolUse: [$entry]}}' > "$settings_file"
  fi

  echo "Installed Claude Code hook: $settings_file"
}

install_cursor() {
  local hooks_file fail_closed_json
  if [[ "$SCOPE" == "user" ]]; then
    hooks_file="${HOME}/.cursor/hooks.json"
  else
    hooks_file="${PWD}/.cursor/hooks.json"
  fi

  fail_closed_json="$FAIL_CLOSED"
  mkdir -p "$(dirname "$hooks_file")"

  local shell_hook read_hook after_hook
  shell_hook="$(jq -n \
    --arg cmd "${GUARDRAIL_HOME}/adapters/cursor/before-shell.sh" \
    --argjson fc "$fail_closed_json" \
    '{command: $cmd, type: "command", failClosed: $fc}')"
  read_hook="$(jq -n \
    --arg cmd "${GUARDRAIL_HOME}/adapters/cursor/before-read-file.sh" \
    --argjson fc "$fail_closed_json" \
    '{command: $cmd, type: "command", failClosed: $fc}')"
  after_hook="$(jq -n \
    --arg cmd "${GUARDRAIL_HOME}/adapters/cursor/after-file-edit.sh" \
    '{command: $cmd, type: "command"}')"

  if [[ -f "$hooks_file" ]]; then
    jq \
      --argjson shell "$shell_hook" \
      --argjson read "$read_hook" \
      --argjson after "$after_hook" \
      '.hooks.beforeShellExecution = (((.hooks.beforeShellExecution // []) | map(select(.command != $shell.command))) + [$shell])
       | .hooks.beforeReadFile = (((.hooks.beforeReadFile // []) | map(select(.command != $read.command))) + [$read])
       | .hooks.afterFileEdit = (((.hooks.afterFileEdit // []) | map(select(.command != $after.command))) + [$after])' \
      "$hooks_file" > "${hooks_file}.tmp"
    mv "${hooks_file}.tmp" "$hooks_file"
  else
    jq -n \
      --argjson shell "$shell_hook" \
      --argjson read "$read_hook" \
      --argjson after "$after_hook" \
      '{hooks: {
        beforeShellExecution: [$shell],
        beforeReadFile: [$read],
        afterFileEdit: [$after]
      }}' > "$hooks_file"
  fi

  echo "Installed Cursor hooks: $hooks_file"
}

case "$AGENT" in
  claude) install_claude ;;
  cursor) install_cursor ;;
esac
