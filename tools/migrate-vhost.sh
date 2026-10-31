#!/bin/bash
# Deliberately separate from generator updates. Unknown hand-written hosts are
# audited only; no directory-wide rewriting or automatic adoption takes place.
current_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd) || exit 1
. "$current_dir/include/nginx_config.sh"
action=${1:---help}
case $action in
  --help) echo 'Usage: migrate-vhost.sh --audit WEB_PREFIX | --preview WEB_PREFIX DOMAIN CANDIDATE | --apply WEB_PREFIX DOMAIN CANDIDATE'; exit 0 ;;
  --audit|--preview|--apply) ;;
  *) exit 2 ;;
esac
web_install_dir=${2:-}
[[ $web_install_dir =~ ^/[A-Za-z0-9/_.-]+$ ]] || exit 2
if [ "$action" = --audit ]; then
  for file in "$web_install_dir"/conf/vhost/*.conf; do
    [ -f "$file" ] || continue
    if [[ $(head -1 "$file") == '# oneinstack-next managed v1; domain='* ]]; then
      printf 'Managed: %s\n' "$file"
    else printf 'Manual review required; no automatic migration: %s\n' "$file"; fi
  done
  exit 0
fi
domain=${3:-}; candidate=${4:-}
Nginx_Domain_Valid "$domain" || exit 2
target=$web_install_dir/conf/vhost/$domain.conf
[ -f "$target" ] && [ -f "$candidate" ] && [ ! -L "$target" ] || exit 2
marker="# oneinstack-next managed v1; domain=$domain"
if [ "$action" = --preview ]; then
  [ "$(head -1 "$target")" = "$marker" ] || echo 'Legacy/custom host: preview only; automatic apply is disabled' >&2
  diff -u -- "$target" "$candidate"
  [ $? -le 1 ]
  exit $?
fi
[ "$(head -1 "$target")" = "$marker" ] && [ "$(head -1 "$candidate")" = "$marker" ] || {
  echo 'Unknown or customized host identity; manual review is required' >&2; exit 1;
}
Nginx_Activate "$candidate" "$target"
