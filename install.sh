#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install.sh <agent> [--scope user|project] [--fail-closed] [--install-dir DIR]

Install the guardrail as a versioned copy and register hooks for the
specified AI coding agent. Hooks point at the installed copy, not at
this repository, so the development clone stays editable.

Arguments:
  agent          claude | cursor

Options:
  --scope        user (default) or project
  --fail-closed  Enable fail-closed policy for Cursor hooks
  --install-dir  Installation directory
                 (default: $XDG_DATA_HOME/ai-agent-guardrail or
                  ~/.local/share/ai-agent-guardrail)
  -h, --help     Show this help
EOF
}

resolve_guardrail_home() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  printf '%s' "$script_dir"
}

GUARDRAIL_HOME="$(resolve_guardrail_home)"
INSTALL_DIR="${GUARDRAIL_INSTALL_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/ai-agent-guardrail}"
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
    --install-dir)
      INSTALL_DIR="${2:-}"
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

if [[ -z "$INSTALL_DIR" ]]; then
  echo "install.sh: --install-dir requires a directory" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "install.sh: jq is required" >&2
  exit 1
fi

# リポジトリのリリース断面（core/adapters/rules）をインストール先へコピーする。
# フックはインストール先を参照するため、開発 clone とは独立に動作する。
install_snapshot() {
  INSTALL_DIR="$(mkdir -p "$INSTALL_DIR" && cd "$INSTALL_DIR" && pwd)"

  # インストール先から直接実行された場合はコピー不要
  if [[ "$INSTALL_DIR" == "$GUARDRAIL_HOME" ]]; then
    return 0
  fi

  local dir
  for dir in core adapters rules; do
    rm -rf "${INSTALL_DIR:?}/${dir}"
    cp -R "${GUARDRAIL_HOME}/${dir}" "${INSTALL_DIR}/${dir}"
  done

  echo "Installed guardrail files: $INSTALL_DIR"
}

install_claude() {
  local settings_file hook_cmd
  if [[ "$SCOPE" == "user" ]]; then
    settings_file="${HOME}/.claude/settings.json"
  else
    settings_file="${PWD}/.claude/settings.json"
  fi

  hook_cmd="${INSTALL_DIR}/adapters/claude/pretooluse.sh"
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
    --arg cmd "${INSTALL_DIR}/adapters/cursor/before-shell.sh" \
    --argjson fc "$fail_closed_json" \
    '{command: $cmd, type: "command", failClosed: $fc}')"
  read_hook="$(jq -n \
    --arg cmd "${INSTALL_DIR}/adapters/cursor/before-read-file.sh" \
    --argjson fc "$fail_closed_json" \
    '{command: $cmd, type: "command", failClosed: $fc}')"
  after_hook="$(jq -n \
    --arg cmd "${INSTALL_DIR}/adapters/cursor/after-file-edit.sh" \
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

install_snapshot

case "$AGENT" in
  claude) install_claude ;;
  cursor) install_cursor ;;
esac
