#!/bin/bash
. "${current_dir}/include/source.sh"
Source_Config

# Compatibility URLs supply a filename, never an identity or a trust root.
Artifact_Resolve() {
  local filename=$1 catalog=${artifact_catalog:-${current_dir}/config/artifacts.json} record remote mirror_filename
  [[ $filename =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ && $filename != *..* ]] || { Source_Error 'Unsafe artifact filename'; return 1; }
  record=$(jq -ce --arg f "$filename" '[.artifacts[] | select(.filename == $f)] | if length == 1 then .[0] else error("missing or ambiguous reviewed artifact: " + $f) end' "$catalog") || return 1
  jq -e '.provider == "mirrorone" or .provider == "official" or .provider == "bundled"' <<< "$record" >/dev/null || return 1
  jq -e '.sha256 | type == "string" and test("^[a-f0-9]{64}$")' <<< "$record" >/dev/null || { Source_Error "Missing independently reviewed SHA-256: $filename (see docs/source-coverage.md)"; return 1; }
  jq -e '.source_url | test("^https://[^/@?#]+/")' <<< "$record" >/dev/null || return 1
  local arch=${ARCH:-$(uname -m)} libc=${artifact_libc:-glibc}
  [ "$arch" != arm64 ] || arch=aarch64
  jq -e --arg a "$arch" --arg l "$libc" '
    (.platform.os == "any" or .platform.os == "linux") and
    (.platform.arch == "any" or .platform.arch == $a) and
    (.platform.libc == null or .platform.libc == $l or
     ($l == "glibc" and (.platform.libc | test("^glibc[0-9]+(\\.[0-9]+)*$"))))' <<< "$record" >/dev/null || { Source_Error "Unsupported platform: $filename / $arch / $libc"; return 1; }
  if [ "$(jq -r .platform.os <<< "$record")" = linux ] && [ "$(uname -s)" != Linux ]; then Source_Error 'Linux binary requested on a non-Linux host'; return 1; fi
  local glibc_min glibc_current
  glibc_min=$(jq -r '.glibc_min // empty' <<< "$record")
  if [ -z "$glibc_min" ]; then
    glibc_min=$(jq -r '(.platform.libc // "") | if startswith("glibc") then sub("^glibc"; "") else "" end' <<< "$record")
  fi
  if [ -n "$glibc_min" ]; then
    glibc_current=$(getconf GNU_LIBC_VERSION 2>/dev/null) || return 1
    glibc_current=${glibc_current##* }
    [ "$(printf '%s\n%s\n' "$glibc_min" "$glibc_current" | sort -V | head -1)" = "$glibc_min" ] || { Source_Error "Requires glibc >= $glibc_min"; return 1; }
  fi
  if [ "$(jq -r .provider <<< "$record")" = bundled ]; then
    [ "$(jq -r .local_path <<< "$record")" = "src/$filename" ] || return 1
    artifact_url=bundled:src/$filename
    artifact_record=$record
    return 0
  fi
  if [ "$download_provider" = mirrorone ] && [ "$(jq -r .provider <<< "$record")" != official ]; then
    Manifest_Fetch || return 1
    mirror_filename=$(jq -r '.mirror_filename // .filename' <<< "$record")
    [[ $mirror_filename =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ && $mirror_filename != *..* ]] || return 1
    remote=$(jq -ce --argjson r "$record" '
      if any(.conflicts[]; .filename == $r.filename or .filename == ($r.mirror_filename // $r.filename)) then error("conflicting artifact") else
      [.artifacts[] | select(.filename == ($r.mirror_filename // $r.filename) and
       (.filename == $r.filename or (.aliases | index($r.filename) != null)) and .component == $r.component and
       .version == $r.version and .kind == $r.kind and .channel == $r.channel and
       .platform == $r.platform)] |
      if length != 1 then error("missing or ambiguous exact artifact") else .[0] end end |
      select(.mirror.available and .mirror.cache_status != "quarantined" and .mirror.integrity_status != "checksum_mismatch")' "$manifest_snapshot") || return 1
    [ -n "$remote" ] || return 1
    [ "$(jq -r .mirror.path <<< "$remote")" = "/src/$mirror_filename" ] || return 1
    [ "$(jq -r .source.url <<< "$remote")" = "$(jq -r .source_url <<< "$record")" ] || { Source_Error 'Upstream identity changed; review catalog'; return 1; }
    local remote_sha
    remote_sha=$(jq -r '.checksums.sha256 // empty' <<< "$remote")
    [ -z "$remote_sha" ] || [ "$remote_sha" = "$(jq -r .sha256 <<< "$record")" ] || { Source_Error 'Manifest digest conflicts with reviewed pin'; return 1; }
    artifact_url=$mirror_link/src/$mirror_filename
    [ "$mirror_force_redirect" != true ] || artifact_url+='?force_redirect=true'
    record=$(jq --arg id "$(jq -r .id <<< "$remote")" --arg revision "$(jq -r .manifest_revision "$manifest_snapshot")" '. + {manifest_id:$id,manifest_revision:$revision}' <<< "$record") || return 1
  else
    artifact_url=$(jq -r .source_url <<< "$record")
    [ "$(jq -r .provider <<< "$record")" != official ] || printf 'Official source exception: %s (%s)\n' "$filename" "$(jq -r .reason <<< "$record")" >&2
  fi
  artifact_record=$record
}

Artifact_Verify() {
  local file=$1 record=$2 expected actual size format listing member top required
  [ -f "$file" ] && [ ! -L "$file" ] && [ -s "$file" ] || return 1
  expected=$(jq -r .sha256 <<< "$record")
  actual=$(sha256sum -- "$file") || return 1
  [ "${actual%% *}" = "$expected" ] || return 1
  size=$(jq -r '.size // 0' <<< "$record")
  [ "$size" = 0 ] || [ "$(wc -c < "$file")" -eq "$size" ] || return 1
  format=$(jq -r .format <<< "$record")
  case $format in
    tar.gz|tgz) listing=$(tar tzf "$file") || return 1 ;;
    tar.xz) listing=$(tar tJf "$file") || return 1 ;;
    tar.bz2) listing=$(tar tjf "$file") || return 1 ;;
    zip) unzip -tq "$file" >/dev/null 2>&1 || return 1; listing=$(unzip -Z1 "$file") || return 1 ;;
    raw) return 0 ;;
    phar) [ "$(head -1 "$file")" = '#!/usr/bin/env php' ]; return $? ;;
    *) return 1 ;;
  esac
  [ -n "$listing" ] || return 1
  listing=$(sed 's@^\./@@' <<< "$listing")
  top=$(jq -r '.top_dir // empty' <<< "$record")
  if [ -n "$listing" ]; then
    while IFS= read -r member; do
      member=${member#./}
      [[ $member != /* && $member != *\\* && ! $member =~ (^|/)\.\.(/|$) ]] || return 1
      [ -z "$top" ] || [[ $member == "$top" || $member == "$top/"* ]] || return 1
    done <<< "$listing"
  fi
  while IFS= read -r required; do
    [ -n "$top" ] && [[ $required =~ ^[A-Za-z0-9_./+-]+$ && $required != *..* && $required != /* ]] || return 1
    grep -Fx -- "$top/$required" <<< "$listing" >/dev/null || return 1
  done < <(jq -r '.required_paths // [] | .[]' <<< "$record")
}

# No resume: partial bytes never become an accepted artifact cache entry.
Download_Artifact() {
  local filename=$1 dest=${2:-.} record url stage maxbytes
  Source_Validate && Source_Dependencies && Artifact_Resolve "$filename" || return 1
  record=$artifact_record; url=$artifact_url
  if [ -n "${source_runtime:-}" ]; then
    jq -c --arg url "$url" '. + {resolved_url:$url}' <<< "$record" >> "$source_runtime/plan.ndjson" || return 1
  fi
  maxbytes=$(jq -r '.size // 2147483648' <<< "$record")
  [ "${download_preflight:-false}" != true ] || { printf '%s\t%s\n' "$filename" "$url"; return 0; }
  [ -d "$dest" ] && [ ! -L "$dest/$filename" ] || return 1
  if Artifact_Verify "$dest/$filename" "$record"; then echo "[$filename] verified cache"; return 0; fi
  stage=$(mktemp -d "$dest/.download.XXXXXXXX") || return 1
  if [ "$(jq -r .provider <<< "$record")" = bundled ]; then
    if ! Artifact_Verify "$current_dir/src/$filename" "$record" || ! cp "$current_dir/src/$filename" "$stage/payload"; then
      Remove_Private_Tree "$stage" "$dest"; Source_Error "Missing or modified bundled artifact: $filename"; return 1
    fi
  elif ! Source_HTTP --max-filesize "$maxbytes" -o "$stage/payload" "$url"; then
    [ "$download_fallback" != official ] || printf 'Explicit official fallback for %s\n' "$filename" >&2
    if [ "$download_fallback" != official ] || [ "$url" = "$(jq -r .source_url <<< "$record")" ] ||
       ! Source_HTTP --max-filesize "$maxbytes" -o "$stage/payload" "$(jq -r .source_url <<< "$record")"; then
      Remove_Private_Tree "$stage" "$dest"; Source_Error "Transport failed: $filename"; return 1
    fi
  fi
  if ! Artifact_Verify "$stage/payload" "$record"; then
    Remove_Private_Tree "$stage" "$dest"; Source_Error "Integrity/format check failed: $filename"; return 1
  fi
  chmod 644 "$stage/payload" && mv -f -- "$stage/payload" "$dest/$filename"
  local result=$?
  Remove_Private_Tree "$stage" "$dest"
  return "$result"
}

# Deprecated compatibility entrypoint. All in-tree consumers use explicit
# filenames now; remove this wrapper in the next incompatible helper API.
Download_src() {
  local filename=${src_filename:-${src_url%%\?*}}
  filename=${filename##*/}
  Download_Artifact "$filename" || exit 1
}
