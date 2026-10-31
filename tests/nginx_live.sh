#!/bin/bash
# Runs only against a privately installed real Nginx-family binary.
set -Eeo pipefail
current_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
web_install_dir=$1
domain=example.test
moredomainame=' alias.example.test'
nginx_http_port=18080
nginx_https_port=18443
export nginx_http_port nginx_https_port
nginx_ssl_flag=y
https_flag=y
nginx_ipv6=false
nginx_hsts=false
nginx_replace_managed=true
redirect_flag=y
PATH_SSL=$web_install_dir/conf/ssl
. "$current_dir/include/nginx_config.sh"
mkdir -p "$PATH_SSL" "$web_install_dir/conf/vhost" "$web_install_dir/conf/rewrite" "$web_install_dir/logs" "$web_install_dir/www"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -keyout "$PATH_SSL/$domain.key" -out "$PATH_SSL/$domain.crt" -subj "/CN=$domain" -addext "subjectAltName=DNS:$domain,DNS:alias.example.test" >/dev/null 2>&1
chmod 600 "$PATH_SSL/$domain.key"
cat > "$web_install_dir/conf/nginx.conf" <<EOF
pid $web_install_dir/logs/nginx.pid;
error_log $web_install_dir/logs/error.log notice;
events {}
http { include $web_install_dir/conf/vhost/*.conf; }
EOF
"$web_install_dir/sbin/nginx" -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf"
backend_pid=
cleanup() {
  local status=$? file
  if [ "$status" -ne 0 ]; then
    printf 'Live integration failed at line %s: %s (HTTP status: %s)\n' "${failure_line:-unknown}" "${failure_command:-unknown}" "${code:-unset}" >&2
    for file in "$web_install_dir/logs/error.log" "$web_install_dir/logs/backend.log"; do
      if [ -f "$file" ]; then printf '\n--- %s ---\n' "$file" >&2; tail -80 "$file" >&2; fi
    done
  fi
  "$web_install_dir/sbin/nginx" -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" -s quit || true
  [ -z "$backend_pid" ] || kill "$backend_pid" || true
  return "$status"
}
trap 'failure_line=$LINENO; failure_command=$BASH_COMMAND' ERR
trap cleanup EXIT
# Load the actual writer definitions without invoking vhost.sh's entrypoint.
python3 - "$current_dir/vhost.sh" "$web_install_dir/.vhost-functions.sh" <<'PY'
from pathlib import Path
import sys
body=Path(sys.argv[1]).read_text()
Path(sys.argv[2]).write_text(body[body.index('Choose_ENV() {'):body.rindex('\nif [ ${ARG_NUM} == 0 ]; then')])
PY
. "$web_install_dir/.vhost-functions.sh"
# The real renderer, target binary, activation and requests remain in use.
# Only the interactive certificate information display is suppressed.
Print_SSL() { :; }
cd "$current_dir"
Nginx_conf='# ONEINSTACK_LISTEN'
Nginx_log='access_log off;'
wwwlogs_dir=$web_install_dir/logs
vhostdir=$web_install_dir/www
mphp_ver=85
rewrite_flag=n
mkdir -p "$vhostdir/pub"
printf 'application-static-route' > "$vhostdir/health.txt"
printf 'application-static-route' > "$vhostdir/pub/health.txt"
: > "$web_install_dir/conf/rewrite/none.conf"
NGX_CONF='location ~ \.php$ { include fastcgi_params; fastcgi_pass unix:/dev/shm/php85-cgi.sock; }'
for app in php proxy magento; do
  rewrite=none
  writer=Create_nginx_phpfpm_conf
  case $app in
    proxy)
      writer=Create_nginx_proxy_conf
      python3 -m http.server 18181 --bind 127.0.0.1 --directory "$vhostdir" > "$web_install_dir/logs/backend.log" 2>&1 & backend_pid=$!
      sleep 1
      Proxy_Pass=http://127.0.0.1:18181 ;;
    magento) rewrite=magento2 ;;
  esac
  for https_flag in y n; do
    "$writer"
    code=$(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' --resolve "$domain:18080:127.0.0.1" "http://$domain:18080/health.txt?q=1")
    if [ "$https_flag" = y ]; then [ "$code" = 301 ]; else [ "$code" = 200 ]; fi
    token=$web_install_dir/conf/acme/.well-known/acme-challenge/contract
    echo challenge > "$token"
    [ "$(curl --noproxy '*' -fsS --resolve "$domain:18080:127.0.0.1" "http://$domain:18080/.well-known/acme-challenge/contract")" = challenge ]
    version=$(curl --noproxy '*' --http2 -fsS -o /dev/null -w '%{http_version}' --cacert "$PATH_SSL/$domain.crt" --resolve "$domain:18443:127.0.0.1" "https://$domain:18443/health.txt")
    [ "$version" = 2 ]
    [ "$(curl --noproxy '*' -fsS --cacert "$PATH_SSL/$domain.crt" --resolve "$domain:18443:127.0.0.1" "https://$domain:18443/health.txt")" = application-static-route ]
    for tls in 1.2 1.3; do
      curl --noproxy '*' -fsS --tlsv"$tls" --tls-max "$tls" --cacert "$PATH_SSL/$domain.crt" --resolve "$domain:18443:127.0.0.1" "https://$domain:18443/health.txt" >/dev/null
    done
    if curl --noproxy '*' -sS --tlsv1.0 --tls-max 1.1 --cacert "$PATH_SSL/$domain.crt" --resolve "$domain:18443:127.0.0.1" "https://$domain:18443/health.txt" >/dev/null 2>&1; then echo 'Legacy TLS unexpectedly accepted' >&2; exit 1; fi
  done
done
# HSTS is opt-in, HTTPS-only, including errors and custom-header locations.
Nginx_Begin_Candidate
cat > "$nginx_candidate" <<EOF
server {
  # ONEINSTACK_LISTEN
  server_name $domain$moredomainame;
  location /headers {
    add_header X-Example yes;
    return 200 "headers";
  }
  location / { return 404; }
}
EOF
nginx_hsts=true
Nginx_Commit_Candidate
for path in /headers /missing; do
  curl --noproxy '*' -sS -D "$web_install_dir/https.headers" -o /dev/null --cacert "$PATH_SSL/$domain.crt" --resolve "$domain:18443:127.0.0.1" "https://$domain:18443$path"
  grep -qi '^Strict-Transport-Security:' "$web_install_dir/https.headers"
  curl --noproxy '*' -sS -D "$web_install_dir/http.headers" -o /dev/null --resolve "$domain:18080:127.0.0.1" "http://$domain:18080$path"
  if grep -qi '^Strict-Transport-Security:' "$web_install_dir/http.headers"; then echo 'HSTS leaked to HTTP' >&2; exit 1; fi
done
# A renewed certificate is delivered to a private inbox; deployment validates
# both files, tests a complete tree, reloads, and checks the actual listener.
inbox=$web_install_dir/conf/acme-certs/$domain
mkdir -p "$inbox"; chmod 700 "$inbox"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -keyout "$inbox/key.pem" -out "$inbox/fullchain.pem" -subj "/CN=$domain" -addext "subjectAltName=DNS:$domain" >/dev/null 2>&1
bash "$current_dir/tools/deploy-certificate.sh" "$web_install_dir" "$domain" "$inbox"
before=$(sha256sum "$PATH_SSL/$domain.key")
printf broken > "$inbox/key.pem"
if bash "$current_dir/tools/deploy-certificate.sh" "$web_install_dir" "$domain" "$inbox"; then echo 'Bad key was accepted' >&2; exit 1; fi
[ "$(sha256sum "$PATH_SSL/$domain.key")" = "$before" ]
# Invalid syntax must leave the active host and its actual response intact.
before=$(sha256sum "$web_install_dir/conf/vhost/$domain.conf")
Nginx_Begin_Candidate
printf 'this_is_not_a_valid_directive;\n' > "$nginx_candidate"
if Nginx_Activate "$nginx_candidate" "$web_install_dir/conf/vhost/$domain.conf"; then echo 'Invalid configuration was accepted' >&2; exit 1; fi
rm -f "$nginx_candidate"
[ "$(sha256sum "$web_install_dir/conf/vhost/$domain.conf")" = "$before" ]

# Exercise IPv6 only where the kernel provides an IPv6 loopback listener.
if python3 -c 'import socket; s=socket.socket(socket.AF_INET6); s.bind(("::1", 0)); s.close()' 2>/dev/null; then
  Nginx_Begin_Candidate
  cat > "$nginx_candidate" <<EOF
server {
  # ONEINSTACK_LISTEN
  server_name $domain;
  location / { return 200 "ipv6-route"; }
}
EOF
  nginx_ipv6=true
  Nginx_Commit_Candidate
  [ "$(curl --noproxy '*' -6 -fsS --resolve "$domain:18443:[::1]" --cacert "$PATH_SSL/$domain.crt" "https://$domain:18443/")" = ipv6-route ]
else
  echo 'IPv6 loopback unavailable: real IPv6 request skipped'
fi

# Use the real executable and real USR2/WINCH/QUIT master lifecycle. Reusing
# its bytes tests the switch protocol, not cross-version ABI compatibility.
binary_candidate=$web_install_dir/sbin/nginx.contract-candidate
cp -p "$web_install_dir/sbin/nginx" "$binary_candidate"
old_master=$(cat "$web_install_dir/logs/nginx.pid")
nginx_upgrade_health_url=http://127.0.0.1:18080/.well-known/acme-challenge/contract
Nginx_Upgrade_Binary "$binary_candidate" "$web_install_dir"
new_master=$(cat "$web_install_dir/logs/nginx.pid")
[ "$new_master" != "$old_master" ]
[ "$(sha256sum < "$binary_candidate")" = "$(sha256sum < "$web_install_dir/sbin/nginx.previous")" ]
# Nginx ignores another USR2 until the previous parent master exits.
for attempt in 1 2 3 4 5; do
  [ -d "/proc/$old_master" ] || break
  grep -q '^State:.*Z' "/proc/$old_master/status" && break
  sleep 1
done

# A failed request after the new master starts must restore the old master
# and confirm its workers before shutting down the new one.
old_master=$new_master
nginx_upgrade_health_url=http://127.0.0.1:18080/.well-known/acme-challenge/absent-contract
if Nginx_Upgrade_Binary "$binary_candidate" "$web_install_dir"; then echo 'Failed upgrade health check was accepted' >&2; exit 1; fi
[ "$(cat "$web_install_dir/logs/nginx.pid")" = "$old_master" ]
pgrep -P "$old_master" -f 'nginx: worker process' >/dev/null
[ "$(curl --noproxy '*' -fsS --resolve "$domain:18080:127.0.0.1" "http://$domain:18080/.well-known/acme-challenge/contract")" = challenge ]
rm -f "$binary_candidate"

echo 'Real binary HTTP/TLS, certificate, configuration rejection and live-switch/rollback checks passed'
