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

builtin_dispatch() {
  local evaluator="$1"
  local command="$2"
  local cwd="$3"
  local home="$4"

  case "$evaluator" in
    rm_wildcard_outside_home)
      builtin_rm_wildcard_outside_home "$command" "$cwd" "$home"
      ;;
    *)
      echo "guardrail: unknown builtin evaluator: $evaluator" >&2
      return 1
      ;;
  esac
}
