#!/bin/bash
# Shared source configuration. No network or system mutation while sourcing.
. "$current_dir/include/fs.sh"
Source_Error() { printf 'Source error: %s\n' "$*" >&2; return 1; }

Source_Version_Validate() {
  [[ $1 =~ ^[0-9]+(\.[0-9]+){1,3}([.-]?[A-Za-z]+[0-9]*)?(-[0-9.]+)?$ ]] || { Source_Error 'An exact numeric release version is required'; return 1; }
}

Source_Config() {
  download_provider=${ONEINSTACK_DOWNLOAD_PROVIDER:-${download_provider:-mirrorone}}
  mirror_link=${ONEINSTACK_MIRROR_LINK:-${mirror_link:-https://mirror.dal.ao}}
  case "$mirror_link" in http://mirrors.linuxeye.com|https://mirrors.linuxeye.com) mirror_link=https://mirror.dal.ao ;; esac
  mirror_link=${mirror_link%/}
  mirror_force_redirect=${ONEINSTACK_MIRROR_FORCE_REDIRECT:-${mirror_force_redirect:-true}}
  download_fallback=${ONEINSTACK_DOWNLOAD_FALLBACK:-${download_fallback:-none}}
  version_source=${version_source:-local}
  verification_policy=${verification_policy:-strict}
}

Source_Validate() {
  mirror_link=${mirror_link%/}
  [[ $download_provider =~ ^(mirrorone|official)$ ]] || { Source_Error 'download_provider must be mirrorone or official'; return 1; }
  [[ $mirror_force_redirect =~ ^(true|false)$ ]] || { Source_Error 'mirror_force_redirect must be true or false'; return 1; }
  [[ $download_fallback =~ ^(none|official)$ ]] || { Source_Error 'download_fallback must be none or official'; return 1; }
  [[ $mirror_link =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~-]+)*$ ]] || { Source_Error 'mirror_link must be a clean HTTPS base URL'; return 1; }
  [ "$version_source" = local ] && [ "$verification_policy" = strict ] || { Source_Error 'Only local baseline and strict verification are supported'; return 1; }
}

Source_Dependencies() {
  local tool
  for tool in jq curl sha256sum flock; do
    command -v "$tool" >/dev/null || { Source_Error "Install $tool from your signed OS package repository before continuing"; return 1; }
  done
}

Source_Cache_Dir() {
  local cache=$current_dir/.metadata
  [ ! -L "$cache" ] || { Source_Error 'Metadata cache must not be a symlink'; return 1; }
  if [ ! -d "$cache" ]; then mkdir -m 700 "$cache" 2>/dev/null || [ -d "$cache" ] || return 1; fi
  [ ! -L "$cache" ] || return 1
  [ "$(stat -c %u "$cache")" = "$(id -u)" ] || { Source_Error 'Metadata cache has a different owner'; return 1; }
  chmod 700 "$cache"
}

Source_Start_Run() {
  Source_Validate && Source_Dependencies || return 1
  [ -z "${source_runtime:-}" ] || return 0
  Source_Cache_Dir || return 1
  source_runtime=$(mktemp -d "$current_dir/.metadata/.run.XXXXXXXX") || return 1
  source_runtime_owner=$BASHPID
  trap 'Source_Cleanup' EXIT
  cp "${artifact_catalog:-$current_dir/config/artifacts.json}" "$source_runtime/catalog.json" || return 1
  if [ -n "${versions_baseline_sha256:-}" ]; then
    local current_digest
    current_digest=$(sha256sum "$current_dir/versions.txt") || return 1
    [ "${current_digest%% *}" = "$versions_baseline_sha256" ] || { Source_Error 'Version baseline changed after selection; restart the command'; return 1; }
    cp "$current_dir/versions.txt" "$source_runtime/versions.txt" || return 1
  fi
  artifact_catalog=$source_runtime/catalog.json
  export artifact_catalog
}

Source_Cleanup() {
  [ "${source_runtime_owner:-}" = "$BASHPID" ] || return 0
  if [ -n "${nginx_candidate:-}" ] && [ -n "${nginx_candidate_parent:-}" ]; then
    Remove_Private_File "$nginx_candidate" "$nginx_candidate_parent"
  fi
  [ -z "${source_runtime:-}" ] || Remove_Private_Tree "$source_runtime" "$current_dir/.metadata"
}

Source_Save_Plan() {
  [ -n "${source_runtime:-}" ] && [ -s "$source_runtime/plan.ndjson" ] || return 0
  local snapshot_hash='' snapshot_revision=local staging catalog_digest
  if [ -n "${manifest_snapshot:-}" ]; then
    snapshot_hash=$(sha256sum "$manifest_snapshot"); snapshot_hash=${snapshot_hash%% *}
    snapshot_revision=$(jq -r .manifest_revision "$manifest_snapshot")
    mkdir -p "$current_dir/.metadata/snapshots" || return 1
    staging=$(mktemp "$current_dir/.metadata/snapshots/.snapshot.XXXXXXXX") || return 1
    cp "$manifest_snapshot" "$staging" && mv -f "$staging" "$current_dir/.metadata/snapshots/$snapshot_hash.json" || return 1
  fi
  catalog_digest=$(sha256sum "$artifact_catalog"); catalog_digest=${catalog_digest%% *}
  jq -s --arg baseline "${versions_baseline_sha256:-unknown}" --arg provider "$download_provider" --arg mirror "$mirror_link" \
    --argjson redirect "$mirror_force_redirect" --arg fallback "$download_fallback" --arg catalog "$catalog_digest" --arg revision "$snapshot_revision" --arg sha "$snapshot_hash" \
    '{status:"preflight-only",versions_sha256:$baseline,provider:$provider,mirror:$mirror,force_redirect:$redirect,
      download_fallback:$fallback,catalog_sha256:$catalog,manifest_revision:$revision,manifest_sha256:$sha,artifacts:unique_by(.filename)}' "$source_runtime/plan.ndjson" > "$source_runtime/plan.json" || return 1
  staging=$(mktemp "$current_dir/.metadata/.plan.XXXXXXXX") || return 1
  install -m 600 "$source_runtime/plan.json" "$staging" && mv -f "$staging" "$current_dir/.metadata/last-plan.json"
}

Source_Summary() {
  printf 'Download source: %s (%s)\nForce upstream redirect: %s; fallback: %s\nVersion source: local baseline; verification: strict\n' "$download_provider" "$mirror_link" "$mirror_force_redirect" "$download_fallback"
  [ "$mirror_force_redirect" = true ] || echo 'Follow the MirrorOne server mode; uncached files may still redirect upstream.'
  [ -z "${manifest_snapshot:-}" ] || jq -r '"Fixed snapshot: " + .manifest_revision + " (" + .generated_at + ")"' "$manifest_snapshot"
  [ -z "${versions_baseline_sha256:-}" ] || printf 'Version baseline SHA-256: %s\n' "$versions_baseline_sha256"
}

Source_Menu() {
  local choice answer
  echo 'Please select download source:'
  printf '\t1. MirrorOne\n\t2. Official upstream\n'
  read -r -e -p 'Please input a number (Default: 1): ' choice
  case ${choice:-1} in 1) download_provider=mirrorone ;; 2) download_provider=official ;; *) return 1 ;; esac
  if [ "$download_provider" = mirrorone ]; then
    read -r -e -p 'Force redirect to upstream and bypass MirrorOne cache? [Y/n]: ' answer
    case $answer in ''|y|Y) mirror_force_redirect=true ;; n|N) mirror_force_redirect=false ;; *) return 1 ;; esac
  fi
  Source_Validate && Source_Summary
}

# Bounded HTTPS-only transport; a redirect cannot downgrade to HTTP/file.
Source_HTTP() {
  curl --fail --silent --show-error --location --max-redirs 5 --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 600 --retry 2 --retry-delay 1 "$@"
}

Manifest_Validate() {
  [ "$(wc -c < "$1")" -le 16777216 ] || return 1
  jq -e ' .schema_name == "mirrorone-artifacts" and .schema_version == 1 and
    (.manifest_revision | type == "string" and test("^[A-Za-z0-9._:+-]{1,160}$")) and
    (.generated_at | type == "string") and (.generator.name | type == "string") and
    (.generator.version | type == "string") and (.generator.commit | type == "string") and
    (.generator.instance_id | type == "string") and (.mirror | type == "object") and
    (.checksum_policy | type == "object") and
    (.artifacts | type == "array") and (.conflicts | type == "array") and
    all(.conflicts[]; (.filename | type == "string") and (.reason | type == "string") and (.candidates | type == "array")) and
    (.version_recommendations | type == "object") and
    all(.version_recommendations[]; type == "string" and length <= 128) and
    all(.artifacts[];
      (.id | type == "string") and (.component | type == "string") and
      (.version | type == "string") and (.channel | type == "string") and (.kind | type == "string") and
      (.filename | type == "string" and length <= 255 and test("^[A-Za-z0-9][A-Za-z0-9._+-]*$")) and
      (.aliases | type == "array") and all(.aliases[]; type == "string") and
      (.platform.os | type == "string") and (.platform.arch | type == "string") and
      (.platform.libc == null or (.platform.libc | type == "string")) and
      (.source.url | type == "string") and (.source.provider | type == "string") and
      (.mirror.path | type == "string") and (.mirror.available | type == "boolean") and
      (.mirror.cache_status == "cached" or .mirror.cache_status == "not_cached" or .mirror.cache_status == "quarantined") and
      (.checksums | type == "object") and all(.checksums[]; type == "string") and
      (.checksum_metadata | type == "object") and (.size | type == "object"))' "$1" >/dev/null
}

Manifest_Fresh() {
  jq -e '(.generated_at | fromdateiso8601) as $t | $t <= (now + 300) and (now - $t) <= 2592000' "$1" >/dev/null || {
    Source_Error 'Snapshot is older than 30 days or has an invalid/future timestamp; explicitly refresh it'
    return 1
  }
}

# A run owns one immutable private copy. Cache publication is serialized and
# never replaces the last accepted entity on malformed/failed responses.
Manifest_Fetch() {
  [ -z "${manifest_snapshot:-}" ] || { Manifest_Validate "$manifest_snapshot" && Manifest_Fresh "$manifest_snapshot"; return; }
  Source_Validate && Source_Dependencies || return 1
  local cache=${current_dir}/.metadata stage code attempt digest etag
  Source_Cache_Dir || return 1
  stage=$(mktemp -d "$cache/.fetch.XXXXXXXX") || return 1
  (
    flock -x 9 || exit 1
    for attempt in 1 2 3; do
      local -a conditional=()
      if [ -s "$cache/accepted.json" ] && [ -s "$cache/etag" ] && [ -s "$cache/base" ] && [ "$(cat "$cache/base")" = "$mirror_link" ] &&
          (cd "$cache" && sha256sum -c accepted.sha256 >/dev/null 2>&1); then
        etag=$(cat "$cache/etag")
        [[ $etag != *$'\r'* && $etag != *$'\n'* ]] && conditional=(-H "If-None-Match: $etag")
      fi
      code=$(Source_HTTP --max-filesize 16777216 -D "$stage/headers" -o "$stage/entity" -w '%{http_code}' "${conditional[@]}" "$mirror_link/manifests/artifacts.json") || exit 1
      if [ "$code" = 304 ]; then
        [ ${#conditional[@]} -gt 0 ] && Manifest_Validate "$cache/accepted.json" && Manifest_Fresh "$cache/accepted.json" || exit 1
        cp "$cache/accepted.json" "$stage/snapshot.json" || exit 1
        exit 0
      fi
      [ "$code" = 200 ] && Manifest_Validate "$stage/entity" && Manifest_Fresh "$stage/entity" || exit 1
      Source_HTTP --max-filesize 4096 -o "$stage/sidecar" "$mirror_link/manifests/artifacts.json.sha256" || exit 1
      read -r digest _ < "$stage/sidecar"
      [[ $digest =~ ^[a-fA-F0-9]{64}$ ]] || exit 1
      [ "$(sha256sum "$stage/entity" | cut -d' ' -f1)" = "${digest,,}" ] || continue
      cp "$stage/entity" "$stage/snapshot.json" || exit 1
      mv "$stage/entity" "$cache/accepted.json" || exit 1
      (cd "$cache" && sha256sum accepted.json > accepted.sha256) || exit 1
      awk 'tolower($1)=="etag:" {$1=""; sub(/^ /, ""); sub(/\r$/, ""); print}' "$stage/headers" | tail -1 > "$cache/etag"
      printf '%s' "$mirror_link" > "$cache/base"
      exit 0
    done
    Source_Error 'Manifest/sidecar changed during publication; retry later'
    exit 1
  ) 9> "$cache/lock"
  if [ $? != 0 ]; then Remove_Private_Tree "$stage" "$cache"; return 1; fi
  manifest_snapshot=$stage/snapshot.json
  if [ -n "${source_runtime:-}" ]; then
    cp "$manifest_snapshot" "$source_runtime/manifest.json" || return 1
    manifest_snapshot=$source_runtime/manifest.json
    Remove_Private_Tree "$stage" "$cache"
  fi
  export manifest_snapshot
}

Versions_Check() {
  Source_Start_Run && Manifest_Fetch || return 1
  Source_Summary
  # No automatic adoption: channels and precise artifacts still need review.
  jq -r '.version_recommendations | to_entries[] | [.key,.value] | @tsv' "$manifest_snapshot" |
  while IFS=$'\t' read -r key value; do
    case $key in
      openssl3_ver) key=openssl_ver ;;
      openssl11_ver) continue ;;
      acme_sh_ver) key=acme_ver ;;
      icu4c_ver) value=${value#release-}; value=${value//./_} ;;
    esac
    grep -Fxq "$key" "$current_dir/config/version-keys.txt" || continue
    [[ $value =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || continue
    local component=${key%_ver} kind=source policy='review required' count pinned
    case $component in
      php[0-9]*|mysql[0-9]*|mariadb[0-9]*|percona[0-9]*) component=${component//[0-9]/} ;;
      apache) component=httpd ;;
      apr_util) component=apr ;;
      apcu|imagick|gmagick|swoole|xdebug|yaf|yar|zendopcache) kind=extension ;;
      pecl_*) component=${component#pecl_}; kind=extension ;;
      acme) component=acme.sh ;;
    esac
    if [ "$key" = nginx_ver ]; then policy='stable policy; MirrorOne recommendation is mainline, not automatically eligible'; fi
    if [ "$key" = openssl_ver ] && [ "${value%.*}" != "${openssl_ver%.*}" ]; then policy='outside selected OpenSSL branch'; fi
    count=$(jq --arg c "$component" --arg v "$value" --arg k "$kind" '[.artifacts[] | select(.component == $c and .version == $v and .kind == $k)] | length' "$manifest_snapshot")
    pinned=$(jq --arg c "$component" --arg v "$value" '[.artifacts[] | select(.component == $c and .version == $v and .sha256 != null)] | length' "$artifact_catalog")
    printf '%s: baseline=%s suggested=%s artifacts=%s reviewed_pins=%s; %s\n' "$key" "${!key:-unset}" "$value" "$count" "$pinned" "$policy"
  done
}
