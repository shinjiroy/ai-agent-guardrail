#!/usr/bin/env bash
# builtin 評価関数群。該当（deny）のとき exit 0、非該当のとき exit 1

# コマンド文字列を検査単位のセグメントへ分割する。
# コマンド区切り（; & |）に加えて、コマンド置換 $(...) ・バックティック ・
# サブシェル (...) の境界も区切りに変換し、それらの内側のコマンドも検査対象に含める。
_split_command_segments() {
  printf '%s' "$1" | sed -E 's/\$\(/\n/g; s/`/\n/g; s/[();&|]+/\n/g'
}

# セグメント先頭の VAR=val 代入と sudo / env を除去する。
_strip_segment_prefix() {
  printf '%s' "$1" | sed -E 's/^([[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//; s/^((sudo|env)[[:space:]]+)+//'
}

# 引用符（先頭末尾の " '）を除去する。
_strip_quotes() {
  local c="$1"
  c="${c%\"}"; c="${c#\"}"; c="${c%\'}"; c="${c#\'}"
  printf '%s' "$c"
}

# グロブ文字を含むパスを cwd 基準で実ファイルへ展開する。
# 一致するファイルが無ければ何も出力しない（nullglob）。
_glob_expand() {
  local pat="$1"
  local cwd="$2"
  (
    [[ -n "$cwd" ]] && cd "$cwd" 2>/dev/null
    shopt -s nullglob dotglob 2>/dev/null
    set +f
    local m
    # shellcheck disable=SC2206
    for m in $pat; do
      printf '%s\n' "$m"
    done
  )
}

builtin_rm_wildcard_outside_home() {
  local command="$1"
  local cwd="$2"
  local home="$3"

  if [[ -z "$home" ]]; then
    return 1
  fi

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
  done < <(_split_command_segments "$command")

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
# オペランドにファイルパスを取るコマンド（cat 系・テキスト処理・インタプリタ等）を列挙する。
GUARDRAIL_READER_COMMANDS="cat tac nl head tail less more bat grep egrep fgrep rg ag awk sed cut tr sort uniq wc od xxd hexdump strings base64 base32 cp install view vi vim nano emacs xclip xsel jq yq diff comm paste join column fold fmt pr expand unexpand rev look tsort python python2 python3 perl ruby node php lua Rscript openssl gpg"

# コマンドをラップして別コマンドを実行する名前（xargs 等）。
# これらの後続トークンを実コマンドとして再評価する。
GUARDRAIL_WRAPPER_COMMANDS="xargs nice nohup timeout stdbuf ionice"

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
  done < <(_split_command_segments "$command")

  return 1
}

# セグメントから読み取り対象ファイル候補を集めて _out 配列へ追加する。
# find -exec / xargs 等のラッパは剥がして内側コマンドを再評価する。
_collect_read_candidates() {
  local seg="$1"
  local -n _out="$2"

  # 入力リダイレクト（< file）の対象を候補に加える
  local redir
  while IFS= read -r redir; do
    [[ -n "$redir" ]] && _out+=("$redir")
  done < <(printf '%s' "$seg" | grep -oE '<[[:space:]]*[^[:space:]<>&|;]+' | sed -E 's/^<[[:space:]]*//')

  local stripped
  stripped="$(_strip_segment_prefix "$seg")"

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

  # find ... -exec <reader> ... {} 形式の内側コマンドを検査する
  if [[ "$cmdname" == "find" ]]; then
    local i n=${#tokens[@]}
    for (( i = 1; i < n; i++ )); do
      if [[ "${tokens[i]}" == "-exec" || "${tokens[i]}" == "-execdir" ]]; then
        local inner="${tokens[i+1]:-}"
        inner="${inner##*/}"
        case " $GUARDRAIL_READER_COMMANDS " in
          *" $inner "*)
            local j
            for (( j = i + 2; j < n; j++ )); do
              case "${tokens[j]}" in
                ';'|'\;'|'+'|'{}') continue ;;
                -*) continue ;;
                *) _out+=("${tokens[j]}") ;;
              esac
            done
            ;;
        esac
      fi
    done
    return 0
  fi

  # ラッパコマンド（xargs 等）は剥がして後続を実コマンドとして再帰評価する
  case " $GUARDRAIL_WRAPPER_COMMANDS " in
    *" $cmdname "*)
      local rest=()
      local t skip_next=0
      for t in "${tokens[@]:1}"; do
        if [[ "$skip_next" -eq 1 ]]; then skip_next=0; continue; fi
        case "$t" in
          # 引数を取る代表的な xargs/timeout フラグは値を読み飛ばす
          -I|-n|-P|-d|-E|-s|-a) skip_next=1; continue ;;
          -*) continue ;;
          *) rest+=("$t") ;;
        esac
      done
      if [[ ${#rest[@]} -gt 0 ]]; then
        _collect_read_candidates "${rest[*]}" _out
      fi
      return 0
      ;;
  esac

  case " $GUARDRAIL_READER_COMMANDS " in
    *" $cmdname "*)
      local -a rops=()
      local t
      for t in "${tokens[@]:1}"; do
        case "$t" in
          -*) continue ;;
          '<'|'>'|'>>') continue ;;
          *=*) continue ;;
          *) rops+=("$t") ;;
        esac
      done
      # cp/mv/install/rsync/scp は末尾が宛先（write）なので読み取り候補から除く。
      # 宛先の書き込み判定は writes_denied_file が担当する。
      case "$cmdname" in
        cp|mv|install|rsync|scp)
          [[ ${#rops[@]} -ge 1 ]] && unset 'rops[${#rops[@]}-1]'
          ;;
      esac
      local o
      for o in "${rops[@]}"; do _out+=("$o"); done
      ;;
  esac

  # source / . によるファイル読み込み
  if [[ "$cmdname" == "source" || "$cmdname" == "." ]]; then
    [[ -n "${tokens[1]:-}" ]] && _out+=("${tokens[1]}")
  fi

  return 0
}

_builtin_segment_reads_denied_file() {
  local seg="$1"
  local cwd="$2"
  local home="$3"
  local rules_file="$4"

  local candidates=()
  _collect_read_candidates "$seg" candidates

  [[ ${#candidates[@]} -eq 0 ]] && return 1

  if _candidates_hit_rule candidates "read" "$cwd" "$rules_file"; then
    return 0
  fi
  return 1
}

# 候補パス配列を正規化し、指定操作の deny-files ルールに一致すれば 0 を返す。
# グロブ文字を含む候補は cwd 基準で実ファイルへ展開してから照合する。
_candidates_hit_rule() {
  local -n _cands="$1"
  local operation="$2"
  local cwd="$3"
  local rules_file="$4"

  local c resolved
  for c in "${_cands[@]}"; do
    c="$(_strip_quotes "$c")"
    [[ -z "$c" ]] && continue

    if [[ "$c" == *'*'* || "$c" == *'?'* || "$c" == *'['* ]]; then
      local ec
      while IFS= read -r ec; do
        [[ -z "$ec" ]] && continue
        resolved="$(normalize_path "$ec" "$cwd")"
        if denied_file_rule_id "$resolved" "$operation" "$rules_file" >/dev/null; then
          return 0
        fi
      done < <(_glob_expand "$c" "$cwd")
      continue
    fi

    resolved="$(normalize_path "$c" "$cwd")"
    if denied_file_rule_id "$resolved" "$operation" "$rules_file" >/dev/null; then
      return 0
    fi
  done
  return 1
}

# echo x > .env / tee .env / cp foo .env 等、シェル経由で deny-files の
# 書き込み禁止ファイルへ書き込もうとしていれば該当（deny）とする。
builtin_writes_denied_file() {
  local command="$1"
  local cwd="$2"
  local home="$3"

  local rules_file="${GUARDRAIL_RULES_DIR:-}/deny-files.json"
  [[ -f "$rules_file" ]] || return 1

  local seg
  while IFS= read -r seg || [[ -n "$seg" ]]; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -z "$seg" ]] && continue
    if _builtin_segment_writes_denied_file "$seg" "$cwd" "$home" "$rules_file"; then
      return 0
    fi
  done < <(_split_command_segments "$command")

  return 1
}

_builtin_segment_writes_denied_file() {
  local seg="$1"
  local cwd="$2"
  local home="$3"
  local rules_file="$4"

  local candidates=()

  # 出力リダイレクト（> file / >> file、N> file 含む。>&1 等は除外）
  local redir tgt
  while IFS= read -r redir; do
    [[ -z "$redir" ]] && continue
    tgt="$(printf '%s' "$redir" | sed -E 's/^[0-9]*>>?[[:space:]]*//')"
    [[ -n "$tgt" ]] && candidates+=("$tgt")
  done < <(printf '%s' "$seg" | grep -oE '[0-9]*>>?[[:space:]]*[^[:space:]<>&|;]+')

  local stripped
  stripped="$(_strip_segment_prefix "$seg")"

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

  local -a operands=()
  local t
  for t in "${tokens[@]:1}"; do
    case "$t" in
      '<'*|'>'*) continue ;;
      -*) continue ;;
      *=*) continue ;;
      *) operands+=("$t") ;;
    esac
  done

  case "$cmdname" in
    tee)
      local o
      for o in "${operands[@]}"; do candidates+=("$o"); done
      ;;
    cp|mv|install|rsync|scp|ln)
      # 末尾オペランドが宛先
      if [[ ${#operands[@]} -ge 1 ]]; then
        candidates+=("${operands[${#operands[@]}-1]}")
      fi
      ;;
    truncate)
      local o
      for o in "${operands[@]}"; do candidates+=("$o"); done
      ;;
    dd)
      local ddt
      ddt="$(printf '%s' "$seg" | grep -oE 'of=[^[:space:]]+' | sed -E 's/^of=//' | head -n1)"
      [[ -n "$ddt" ]] && candidates+=("$ddt")
      ;;
    sed)
      # -i / --in-place のときオペランドは書き込み対象
      if printf '%s\n' "${tokens[@]}" | grep -qE '^(-i|--in-place)'; then
        local o
        for o in "${operands[@]}"; do candidates+=("$o"); done
      fi
      ;;
  esac

  [[ ${#candidates[@]} -eq 0 ]] && return 1

  if _candidates_hit_rule candidates "write" "$cwd" "$rules_file"; then
    return 0
  fi
  return 1
}

# 保護ブランチ（main / master）への force push を deny する。
GUARDRAIL_PROTECTED_BRANCHES="main master"

builtin_git_push_force_protected() {
  local command="$1"

  local seg
  while IFS= read -r seg || [[ -n "$seg" ]]; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -z "$seg" ]] && continue
    if _builtin_segment_is_force_push_protected "$seg"; then
      return 0
    fi
  done < <(_split_command_segments "$command")

  return 1
}

_builtin_segment_is_force_push_protected() {
  local seg="$1"

  local stripped
  stripped="$(_strip_segment_prefix "$seg")"

  # shellcheck disable=SC2206
  local tokens=($stripped)

  [[ "${tokens[0]:-}" == "git" ]] || return 1

  local has_push=0 has_force=0 has_protected=0 t
  for t in "${tokens[@]:1}"; do
    case "$t" in
      push) has_push=1 ;;
      --force|--force-with-lease|--force-with-lease=*|--force-if-includes) has_force=1 ;;
      -f) has_force=1 ;;
      -[a-zA-Z]*) [[ "$t" =~ ^-[a-zA-Z]*f[a-zA-Z]*$ ]] && has_force=1 ;;
    esac
    case " $GUARDRAIL_PROTECTED_BRANCHES " in
      *" $t "*) has_protected=1 ;;
    esac
    # refspec 形式（main / master / HEAD:main / +main など）
    case "$t" in
      main|master|*:main|*:master|+main|+master) has_protected=1 ;;
    esac
  done

  [[ "$has_push" -eq 1 && "$has_force" -eq 1 && "$has_protected" -eq 1 ]]
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
    writes_denied_file)
      builtin_writes_denied_file "$command" "$cwd" "$home"
      ;;
    git_push_force_protected)
      builtin_git_push_force_protected "$command" "$cwd" "$home"
      ;;
    *)
      echo "guardrail: unknown builtin evaluator: $evaluator" >&2
      return 1
      ;;
  esac
}
