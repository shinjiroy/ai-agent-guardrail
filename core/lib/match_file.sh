#!/usr/bin/env bash
# glob パターンを正規表現へ変換し、パス全体にマッチするか判定する

glob_to_regex() {
  local pattern="$1"
  local regex="" char i len

  len=${#pattern}
  i=0
  while (( i < len )); do
    char="${pattern:i:1}"
    case "$char" in
      '*')
        if (( i + 1 < len )) && [[ "${pattern:i+1:1}" == '*' ]]; then
          if (( i + 2 < len )) && [[ "${pattern:i+2:1}" == '/' ]]; then
            regex+='(.*/)?'
            i=$((i + 3))
          else
            regex+='.*'
            i=$((i + 2))
          fi
        else
          regex+='[^/]*'
          i=$((i + 1))
        fi
        ;;
      '?')
        regex+='[^/]'
        i=$((i + 1))
        ;;
      '.')
        regex+='\.'
        i=$((i + 1))
        ;;
      '+'|'('|')'|'['|']'|'{'|'}'|'^'|'$'|'|'|'\\')
        regex+="\\$char"
        i=$((i + 1))
        ;;
      *)
        regex+="$char"
        i=$((i + 1))
        ;;
    esac
  done

  printf '^%s$' "$regex"
}

match_file_path() {
  local path="$1"
  local pattern="$2"
  local regex

  regex="$(glob_to_regex "$pattern")"
  if printf '%s\n' "$path" | grep -Eq "$regex"; then
    return 0
  fi
  return 1
}

# パターン内のプレースホルダを展開する。
# ${GUARDRAIL_INSTALL_DIR} … 実行中のガードレール自身の設置先（自己保護ルールで使用）。
# 値が未解決の場合はパターンを不定に広げないため 1 を返し、呼び出し側でスキップする。
expand_pattern_placeholders() {
  local pattern="$1"

  if [[ "$pattern" == *'${GUARDRAIL_INSTALL_DIR}'* ]]; then
    local install_dir="${GUARDRAIL_INSTALL_DIR:-}"
    if [[ -z "$install_dir" ]]; then
      return 1
    fi
    pattern="${pattern//'${GUARDRAIL_INSTALL_DIR}'/${install_dir%/}}"
  fi

  printf '%s' "$pattern"
}

# ルール1件が、正規化済みパス・操作に適用されるか（パターンに一致するか）判定する
file_rule_applies() {
  local rule_json="$1"
  local normalized_path="$2"
  local operation="$3"

  if ! jq -e --arg op "$operation" '.operations | index($op) != null' <<<"$rule_json" >/dev/null; then
    return 1
  fi

  local pattern patterns
  patterns="$(jq -r '.patterns[]' <<<"$rule_json")"
  while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue
    pattern="$(expand_pattern_placeholders "$pattern")" || continue
    if match_file_path "$normalized_path" "$pattern"; then
      return 0
    fi
  done <<<"$patterns"

  return 1
}

# 正規化済みパスが deny-files ルールで禁止されているか判定し、
# 禁止なら該当ルールIDを標準出力へ出して 0 を返す。非該当なら 1 を返す。
denied_file_rule_id() {
  local normalized_path="$1"
  local operation="$2"
  local rules_file="$3"

  local rule_count i rule
  rule_count="$(jq '.rules | length' "$rules_file")"
  for (( i = 0; i < rule_count; i++ )); do
    rule="$(jq -c ".rules[$i]" "$rules_file")"
    if file_rule_applies "$rule" "$normalized_path" "$operation"; then
      jq -r '.id' <<<"$rule"
      return 0
    fi
  done

  return 1
}

normalize_path() {
  local path="$1"
  local cwd="${2:-}"

  if [[ -z "$path" ]]; then
    return 1
  fi

  if [[ "$path" == "~/"* ]]; then
    local home="${HOME:-}"
    if [[ -z "$home" ]]; then
      printf '%s' "$path"
      return 0
    fi
    path="${home}/${path:2}"
  elif [[ "$path" == "~" ]]; then
    printf '%s' "${HOME:-~}"
    return 0
  fi

  if [[ "$path" != /* ]]; then
    if [[ -n "$cwd" ]]; then
      path="${cwd%/}/$path"
    fi
  fi

  if command -v realpath >/dev/null 2>&1; then
    realpath -m "$path" 2>/dev/null || printf '%s' "$path"
  else
    printf '%s' "$path"
  fi
}

path_is_under_home() {
  local path="$1"
  local home="$2"

  if [[ -z "$home" ]]; then
    return 1
  fi

  home="${home%/}"
  path="${path%/}"

  if [[ "$path" == "$home" ]] || [[ "$path" == "$home"/* ]]; then
    return 0
  fi
  return 1
}
