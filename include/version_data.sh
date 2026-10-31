#!/bin/bash
# Version files are data, including the version-controlled baseline.
Read_Versions() {
  local file=$1 line key value count=0 mode=${2:-complete}
  local -A seen=() values=()
  [[ $mode =~ ^(complete|partial)$ ]] || return 2
  [ -f "$file" ] && [ "$(wc -c < "$file")" -le 65536 ] || { echo 'Invalid version file size' >&2; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    [[ $line =~ ^([a-z][a-z0-9_]*_(ver|oldver))=([A-Za-z0-9][A-Za-z0-9._+-]*)$ ]] || { echo 'Invalid version record' >&2; return 1; }
    key=${BASH_REMATCH[1]}; value=${BASH_REMATCH[3]}
    # The allowlist is maintained separately from the untrusted input.
    grep -Fxq -- "$key" "${current_dir}/config/version-keys.txt" || { echo "Unknown version key: $key" >&2; return 1; }
    [ -z "${seen[$key]+x}" ] || { echo "Duplicate version key: $key" >&2; return 1; }
    case $key in
      icu4c_ver) [[ $value =~ ^[0-9]+_[0-9]+$ ]] || return 1 ;;
      fail2ban_ver) [[ $value == master || $value =~ ^[0-9]+(\.[0-9]+)+$ ]] || return 1 ;;
      *) [[ $value =~ ^[0-9]+(\.[0-9]+)*([.-]?[A-Za-z]+[0-9]*)?(-[0-9.]+)?$ ]] || { echo "Invalid version for $key" >&2; return 1; } ;;
    esac
    seen[$key]=1; values[$key]=$value; ((count+=1))
  done < "$file"
  [ "$count" -gt 0 ] || return 1
  if [ "$mode" = complete ]; then
    while IFS= read -r key; do
      [ -n "${seen[$key]+x}" ] || { echo "Missing version key: $key" >&2; return 1; }
    done < "$current_dir/config/version-keys.txt"
  fi
  for key in "${!values[@]}"; do printf -v "$key" '%s' "${values[$key]}"; done
  if [ "$mode" = complete ]; then
    versions_baseline_sha256=$(sha256sum -- "$file") || return 1
    versions_baseline_sha256=${versions_baseline_sha256%% *}
  fi
}
