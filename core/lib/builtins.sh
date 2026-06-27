#!/usr/bin/env bash
# builtin 評価関数群。該当（deny）のとき exit 0、非該当のとき exit 1

builtin_rm_wildcard_outside_home() {
  local command="$1"
  local cwd="$2"
  local home="$3"

  if [[ -z "$home" ]]; then
    return 1
  fi

  # コマンドをセグメントへ分割する。コマンド区切り（; & |）に加えて、
  # コマンド置換 $(...) ・バックティック ・サブシェル (...) の境界も区切りに変換し、
  # それらの内側に書かれた rm も検査対象に含める。
  local seg
  while IFS= read -r seg || [[ -n "$seg" ]]; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    if [[ -z "$seg" ]]; then
      continue
    fi

    if [[ "$seg" =~ (^|[[:space:]])(sudo[[:space:]]+)?rm[[:space:]] ]]; then
      if _builtin_rm_segment_has_outside_home_wildcard "$seg" "$cwd" "$home"; then
        return 0
      fi
    fi
  done < <(printf '%s' "$command" | sed -E 's/\$\(/\n/g; s/`/\n/g; s/[();&|]+/\n/g')

  return 1
}

_builtin_rm_segment_has_outside_home_wildcard() {
  local seg="$1"
  local cwd="$2"
  local home="$3"

  local args
  args="$(printf '%s' "$seg" | sed -E 's/^(sudo[[:space:]]+)?rm[[:space:]]+//')"
  if [[ -z "$args" ]]; then
    return 1
  fi

  local arg
  local noglob_was_set=0
  if [[ $- == *f* ]]; then
    noglob_was_set=1
  else
    set -f
  fi

  for arg in $args; do
    case "$arg" in
      -*) continue ;;
    esac

    if [[ "$arg" != *'*'* && "$arg" != *'?'* && "$arg" != *'['* ]]; then
      continue
    fi

    local resolved
    resolved="$(normalize_path "$arg" "$cwd")"
    if ! path_is_under_home "$resolved" "$home"; then
      [[ "$noglob_was_set" -eq 0 ]] && set +f
      return 0
    fi
  done

  [[ "$noglob_was_set" -eq 0 ]] && set +f
  return 1
}

# ファイルを読むコマンド名の一覧。ここに追記すれば検査対象が増える。
GUARDRAIL_READER_COMMANDS="cat tac nl head tail less more bat grep egrep fgrep rg ag awk sed cut tr sort uniq wc od xxd hexdump strings base64 cp install view vi vim nano emacs xclip"

# cat/grep 等のコマンドやリダイレクト・source 経由で、deny-files の
# 読み取り禁止ファイルへアクセスしていれば該当（deny）とする。
builtin_reads_denied_file() {
  local command="$1"
  local cwd="$2"
  local home="$3"

  local rules_file="${GUARDRAIL_RULES_DIR:-}/deny-files.json"
  [[ -f "$rules_file" ]] || return 1

  local seg
  while IFS= read -r seg || [[ -n "$seg" ]]; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -z "$seg" ]] && continue
    if _builtin_segment_reads_denied_file "$seg" "$cwd" "$home" "$rules_file"; then
      return 0
    fi
  done < <(printf '%s' "$command" | sed -E 's/\$\(/\n/g; s/`/\n/g; s/[();&|]+/\n/g')

  return 1
}

_builtin_segment_reads_denied_file() {
  local seg="$1"
  local cwd="$2"
  local home="$3"
  local rules_file="$4"

  local candidates=()

  # 入力リダイレクト（< file）の対象を候補に加える
  local redir
  while IFS= read -r redir; do
    [[ -n "$redir" ]] && candidates+=("$redir")
  done < <(printf '%s' "$seg" | grep -oE '<[[:space:]]*[^[:space:]<>&|;]+' | sed -E 's/^<[[:space:]]*//')

  # 先頭の VAR=val 代入と sudo を除去する
  local stripped
  stripped="$(printf '%s' "$seg" | sed -E 's/^([[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//; s/^(sudo[[:space:]]+)+//')"

  local noglob_was_set=0
  if [[ $- == *f* ]]; then
    noglob_was_set=1
  else
    set -f
  fi
  # shellcheck disable=SC2206
  local tokens=($stripped)
  [[ "$noglob_was_set" -eq 0 ]] && set +f

  local cmdname="${tokens[0]:-}"
  cmdname="${cmdname##*/}"

  case " $GUARDRAIL_READER_COMMANDS " in
    *" $cmdname "*)
      local t
      for t in "${tokens[@]:1}"; do
        case "$t" in
          -*) continue ;;
          '<'|'>'|'>>') continue ;;
          *=*) continue ;;
          *) candidates+=("$t") ;;
        esac
      done
      ;;
  esac

  # source / . によるファイル読み込み
  if [[ "$cmdname" == "source" || "$cmdname" == "." ]]; then
    [[ -n "${tokens[1]:-}" ]] && candidates+=("${tokens[1]}")
  fi

  [[ ${#candidates[@]} -eq 0 ]] && return 1

  local c resolved
  for c in "${candidates[@]}"; do
    c="${c%\"}"; c="${c#\"}"; c="${c%\'}"; c="${c#\'}"
    [[ -z "$c" ]] && continue
    resolved="$(normalize_path "$c" "$cwd")"
    if denied_file_rule_id "$resolved" "read" "$rules_file" >/dev/null; then
      return 0
    fi
  done

  return 1
}

builtin_dispatch() {
  local evaluator="$1"
  local command="$2"
  local cwd="$3"
  local home="$4"

  case "$evaluator" in
    rm_wildcard_outside_home)
      builtin_rm_wildcard_outside_home "$command" "$cwd" "$home"
      ;;
    reads_denied_file)
      builtin_reads_denied_file "$command" "$cwd" "$home"
      ;;
    *)
      echo "guardrail: unknown builtin evaluator: $evaluator" >&2
      return 1
      ;;
  esac
}
