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
