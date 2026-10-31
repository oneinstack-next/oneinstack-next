#!/bin/bash
# Read-only metadata and artifact planning; never installs OS dependencies.
current_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd) || exit 1
. "$current_dir/options.conf"
. "$current_dir/include/version_data.sh"
Read_Versions "$current_dir/versions.txt" || exit 1
. "$current_dir/include/download.sh"
action=${1:---help}; [ $# -eq 0 ] || shift
while [ $# -gt 0 ]; do
  case $1 in
    --download_provider|--mirror_link|--mirror_force_redirect|--download_fallback)
      [ $# -ge 2 ] || exit 2
      printf -v "${1#--}" '%s' "$2"; shift 2 ;;
    *) break ;;
  esac
done
Source_Validate || exit 2
case $action in --summary|--check-versions|--help|-h)
  [ $# -eq 0 ] || { echo 'Unexpected arguments for read-only action' >&2; exit 2; } ;;
esac
case $action in
  --help|-h) echo 'Usage: sourcectl.sh --summary | --check-versions | --preflight [source options] filename ...' ;;
  --summary) Source_Summary ;;
  --check-versions) Versions_Check ;;
  --preflight)
    [ $# -gt 0 ] || { echo 'Specify exact artifact filenames' >&2; exit 2; }
    download_preflight=true
    Source_Start_Run || exit 1
    status=0
    for filename in "$@"; do Download_Artifact "$filename" || status=1; done
    [ "$status" -ne 0 ] || Source_Save_Plan || exit 1
    Source_Summary
    exit "$status" ;;
  *) echo 'Unknown sourcectl action' >&2; exit 2 ;;
esac
