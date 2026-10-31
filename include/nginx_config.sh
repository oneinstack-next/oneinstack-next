#!/bin/bash
# Used by every Nginx-family writer, certificate deploy and binary switch.
. "$current_dir/include/fs.sh"
Nginx_Requirements() {
  local tool
  [[ ${web_install_dir:-} =~ ^/[A-Za-z0-9/_.-]+$ ]] && [ -x "$web_install_dir/sbin/nginx" ] || { echo 'No configured Nginx installation binary found' >&2; return 1; }
  for tool in flock pgrep curl openssl sha256sum stat awk find; do
    command -v "$tool" >/dev/null || { echo "Install $tool from the signed OS package repository before changing Nginx" >&2; return 1; }
  done
}

Nginx_Domain_Valid() {
  local name
  for name in "$@"; do
    [[ $name =~ ^(\*\.)?[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ && $name != *..* ]] || return 1
  done
}

Nginx_Challenge() {
  printf '  location ^~ /.well-known/acme-challenge/ {\n    root %s;\n    default_type text/plain;\n    try_files $uri =404;\n  }\n' "$nginx_challenge_root"
}

Nginx_Challenge_Setup() {
  nginx_challenge_root=$web_install_dir/conf/acme
  mkdir -p "$nginx_challenge_root/.well-known/acme-challenge" || return 1
  chmod 755 "$nginx_challenge_root" "$nginx_challenge_root/.well-known" "$nginx_challenge_root/.well-known/acme-challenge"
}

Nginx_Listeners() {
  local port=$1 suffix=${2:-}
  case $port in 80) port=${nginx_http_port:-80} ;; 443) port=${nginx_https_port:-443} ;; esac
  [[ $port =~ ^[0-9]+$ ]] && [ "$port" -gt 0 ] && [ "$port" -lt 65536 ] || return 1
  printf '  listen %s%s;\n' "$port" "$suffix"
  [ "${nginx_ipv6:-false}" != true ] || printf '  listen [::]:%s%s;\n' "$port" "$suffix"
}

Nginx_TLS() {
  local suffix=' ssl'
  [ "$nginx_http2_style" != legacy ] || suffix+=' http2'
  Nginx_Listeners 443 "$suffix"
  [ "$nginx_http2_style" != modern ] || echo '  http2 on;'
  cat <<EOF
  ssl_certificate ${PATH_SSL}/${domain}.crt;
  ssl_certificate_key ${PATH_SSL}/${domain}.key;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
  ssl_prefer_server_ciphers off;
  ssl_session_cache shared:SSL:10m;
  ssl_session_timeout 1d;
  ssl_session_tickets off;
EOF
  # OpenSSL's TLS 1.3 defaults remain separate from TLS 1.2 ciphers.
  [ "${nginx_hsts:-false}" != true ] || echo '  add_header Strict-Transport-Security "max-age=15552000" always;'
}

Nginx_Probe() {
  local bin=$web_install_dir/sbin/nginx stage
  [ -x "$bin" ] || return 1
  "$bin" -V >&2
  "$bin" -V 2>&1 | grep -q -- --with-http_v2_module || { echo 'HTTP/2 module is required' >&2; return 1; }
  stage=$(mktemp -d "$web_install_dir/conf/.probe.XXXXXXXX") || return 1
  printf 'events {}\nhttp { server { listen 127.0.0.1:18443; http2 on; } }\n' > "$stage/nginx.conf"
  if "$bin" -t -p "$web_install_dir/" -c "$stage/nginx.conf" > "$stage/result" 2>&1; then
    nginx_http2_style=modern
  else
    printf 'events {}\nhttp { server { listen 127.0.0.1:18443 http2; } }\n' > "$stage/nginx.conf"
    if "$bin" -t -p "$web_install_dir/" -c "$stage/nginx.conf" > "$stage/result" 2>&1; then nginx_http2_style=legacy
    else cat "$stage/result" >&2; Remove_Private_Tree "$stage" "$web_install_dir/conf"; return 1; fi
  fi
  Remove_Private_Tree "$stage" "$web_install_dir/conf"
}

# Candidate contains exactly one application server. Listener marker occurs
# only at server scope; routing is reused as data for HTTP and HTTPS.
Nginx_Render() {
  local candidate=$1 stage names=${domain}${moredomainame}
  local -a domain_names
  [[ ${nginx_hsts:-false} =~ ^(true|false)$ && ${nginx_ipv6:-false} =~ ^(true|false)$ ]] || { echo 'nginx_hsts and nginx_ipv6 must be true or false' >&2; return 1; }
  read -r -a domain_names <<< "$names"
  Nginx_Domain_Valid "${domain_names[@]}" || return 1
  [[ $web_install_dir =~ ^/[A-Za-z0-9/_.-]+$ ]] || return 1
  if [ "${nginx_ssl_flag:-n}" = y ]; then [[ $PATH_SSL =~ ^/[A-Za-z0-9/_.-]+$ ]] || return 1; fi
  Nginx_Challenge_Setup || return 1
  stage=$(mktemp -d "$web_install_dir/conf/.render.XXXXXXXX") || return 1
  cp "$candidate" "$stage/app" || return 1
  : > "$stage/result"
  if [ "${nginx_ssl_flag:-n}" = y ]; then
    Nginx_Probe || { Remove_Private_Tree "$stage" "$web_install_dir/conf"; return 1; }
    Nginx_TLS > "$stage/listeners"
    nginx_render_tls=true
    Nginx_Render_App "$stage/app" "$stage/listeners" >> "$stage/result" || return 1
    Nginx_Render_Aliases https >> "$stage/result"
    nginx_render_tls=false
    if [ "${https_flag:-n}" = y ]; then
      {
        echo 'server {'; Nginx_Listeners 80
        printf '  server_name %s;\n' "$names"
        Nginx_Challenge
        printf '  location / { return 301 https://%s$request_uri; }\n}\n' "$domain"
      } >> "$stage/result"
    else
      Nginx_Listeners 80 > "$stage/listeners"
      Nginx_Render_App "$stage/app" "$stage/listeners" >> "$stage/result" || return 1
      Nginx_Render_Aliases http >> "$stage/result"
    fi
  else
    Nginx_Listeners 80 > "$stage/listeners"
    Nginx_Render_App "$stage/app" "$stage/listeners" >> "$stage/result" || return 1
    Nginx_Render_Aliases http >> "$stage/result"
  fi
  printf '# oneinstack-next managed v1; domain=%s\n' "$domain" > "$candidate"
  cat "$stage/result" >> "$candidate"
  Remove_Private_Tree "$stage" "$web_install_dir/conf"
}

Nginx_Render_App() {
  local input=$1 listeners=$2 line previous_line=
  # The header is inserted at a deliberate marker, independent of root/layout.
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ $line == *'# ONEINSTACK_LISTEN'* ]]; then
      cat "$listeners"
      Nginx_Challenge
    elif [[ $line == *'if ($host != '* ]]; then
      : # Canonical host redirects are emitted as dedicated servers below.
    elif [[ $line == *'server_name '* && ${redirect_flag:-n} = y ]]; then
      printf '  server_name %s;\n' "$domain"
    else
      printf '%s\n' "$line"
      # Preserve HSTS in locations defining their own add_header. At most one
      # HSTS header is added per scope (adjacent add_header directives).
      if [[ ${nginx_render_tls:-false} = true && ${nginx_hsts:-false} = true && $line =~ ^[[:space:]]*add_header[[:space:]] && ! $previous_line =~ ^[[:space:]]*add_header[[:space:]] ]]; then
        echo '    add_header Strict-Transport-Security "max-age=15552000" always;'
      fi
    fi
    previous_line=$line
  done < "$input"
}

Nginx_Render_Aliases() {
  local scheme=$1
  [ "${redirect_flag:-n}" = y ] && [ -n "$moredomainame" ] || return 0
  echo 'server {'
  if [ "$scheme" = https ]; then Nginx_TLS; else Nginx_Listeners 80; fi
  printf '  server_name %s;\n' "$moredomainame"
  Nginx_Challenge
  printf '  location / { return 301 %s://%s$request_uri; }\n}\n' "$scheme" "$domain"
}

# Complete config-tree validation, then atomic managed-file replacement. The
# lock serializes all cooperating writers and certificate/binary operations.
Nginx_Activate() (
  local candidate=$1 target=$2 remove=${3:-} stage bin=$web_install_dir/sbin/nginx had_old=false result=1 baseline
  Nginx_Requirements || exit 1
  exec 9> "$web_install_dir/conf/.oneinstack.lock" || exit 1
  [ "${nginx_group_lock:-false}" = true ] || flock -x 9 || exit 1
  [ -f "$candidate" ] && [ ! -L "$target" ] || exit 1
  stage=$(mktemp -d "$web_install_dir/.activate.XXXXXXXX") || exit 1
  trap 'Remove_Private_Tree "$stage" "$web_install_dir"' EXIT
  baseline=$(Nginx_Tree_Digest) || exit 1
  Nginx_Capture_Workers || exit 1
  cp -a "$web_install_dir/conf" "$stage/tree" || exit 1
  cp "$candidate" "$stage/tree/vhost/$(basename "$target")" || exit 1
  if [ -n "$remove" ]; then
    [ "$remove" = "$web_install_dir/conf/vhost/_acme-$domain.conf" ] || exit 1
    [ "$(head -1 "$remove")" = "# oneinstack-next temporary ACME: $domain" ] || exit 1
    cp -p "$remove" "$stage/temporary" || exit 1
    rm -f -- "$stage/tree/vhost/$(basename "$remove")"
  fi
  Nginx_Test_Config_Tree "$stage/tree" || exit 1
  [ "$baseline" = "$(Nginx_Tree_Digest)" ] || { echo 'Configuration changed during validation' >&2; exit 1; }
  if [ -e "$target" ]; then cp -p "$target" "$stage/old" || exit 1; had_old=true; fi
  install -m 644 "$candidate" "$stage/new" || exit 1
  if [ "$had_old" = true ]; then
    chmod --reference="$target" "$stage/new" && chown --reference="$target" "$stage/new" || exit 1
  fi
  mv -f "$stage/new" "$target" || exit 1
  [ -z "$remove" ] || rm -f -- "$remove"
  if "$bin" -t -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" && "$bin" -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" -s reload && Nginx_Health; then
    result=0
  fi
  if [ "$result" -ne 0 ]; then
    if [ "$had_old" = true ]; then cp -p "$stage/old" "$stage/restore" && mv -f "$stage/restore" "$target"
    else rm -f -- "$target"; fi
    [ -z "$remove" ] || cp -p "$stage/temporary" "$remove"
    "$bin" -t -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" && "$bin" -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" -s reload
    echo 'Nginx activation failed; previous managed configuration restored' >&2
  fi
  exit "$result"
)

Nginx_Test_Config_Tree() {
  local tree=$1 file rewrite=$1/.rewrite
  # Literal replacement, never interpreting paths as sed programs/regexes.
  while IFS= read -r -d '' file; do
    awk -v old="$web_install_dir/conf/" -v new="$tree/" '
      { out=""; rest=$0; while ((p=index(rest,old))>0) {out=out substr(rest,1,p-1) new; rest=substr(rest,p+length(old))} print out rest }' "$file" > "$rewrite" || return 1
    cat "$rewrite" > "$file" || return 1
  done < <(find "$tree" -type f -name '*.conf' -print0)
  rm -f -- "$rewrite"
  "$web_install_dir/sbin/nginx" -t -p "$web_install_dir/" -c "$tree/nginx.conf"
}

Nginx_Tree_Digest() (
  set -o pipefail
  cd "$web_install_dir/conf" || exit 1
  find . \( -type f -o -type l \) -print0 | sort -z |
    while IFS= read -r -d '' file; do
      sha256sum -- "$file" && stat -c '%a:%u:%g:%n' -- "$file" || exit 1
    done | sha256sum
)

Nginx_Health() {
  local token attempt response workers old_pid old_active code challenge=$web_install_dir/conf/acme/.well-known/acme-challenge
  mkdir -p "$challenge" || return 1
  token=$(mktemp "$challenge/oneinstack.XXXXXXXX") || return 1
  printf '%s' "${token##*/}" > "$token"
  chmod 644 "$token" || { rm -f "$token"; return 1; }
  for attempt in 1 2 3 4 5; do
    if [ -n "${nginx_health_master:-}" ]; then
      workers=$(pgrep -P "$nginx_health_master" -f 'nginx: worker process$' | sort) || workers=
      old_active=false
      for old_pid in $nginx_health_workers; do
        case $'\n'$workers$'\n' in *$'\n'"$old_pid"$'\n'*) old_active=true ;; esac
      done
      # A reload briefly runs old and new accepting workers together. Wait
      # until every old worker has exited or entered graceful shutdown.
      if [ -z "$workers" ] || [ "$old_active" = true ]; then sleep 1; continue; fi
    fi
    response=$(curl --noproxy '*' --silent --show-error --max-time 3 --resolve "$domain:${nginx_http_port:-80}:127.0.0.1" "http://$domain:${nginx_http_port:-80}/.well-known/acme-challenge/${token##*/}")
    if [ "$response" = "${token##*/}" ]; then
      if [ "${nginx_temporary_only:-false}" != true ] && [ "${nginx_ssl_flag:-n}" = y ]; then
        response=$(curl --noproxy '*' --silent --show-error --max-time 3 --cacert "$PATH_SSL/$domain.crt" --resolve "$domain:${nginx_https_port:-443}:127.0.0.1" "https://$domain:${nginx_https_port:-443}/.well-known/acme-challenge/${token##*/}")
        [ "$response" = "${token##*/}" ] || { sleep 1; continue; }
        if [ "${https_flag:-n}" = y ]; then
          code=$(curl --noproxy '*' --silent --max-time 3 -o /dev/null -w '%{http_code}' --resolve "$domain:${nginx_http_port:-80}:127.0.0.1" "http://$domain:${nginx_http_port:-80}/oneinstack-redirect-probe?q=1")
          [ "$code" = 301 ] || { sleep 1; continue; }
        fi
      fi
      rm -f "$token"; return 0
    fi
    sleep 1
  done
  rm -f "$token"
  return 1
}

Nginx_Capture_Workers() {
  local pidfile
  pidfile=$("$web_install_dir/sbin/nginx" -T -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" 2>/dev/null | awk '$1=="pid" && !seen {gsub(/[;"]/,"",$2); print $2; seen=1}')
  [[ $pidfile == /* && -f $pidfile ]] || { echo 'An explicit absolute pid directive is required for managed activation' >&2; return 1; }
  nginx_health_master=$(cat "$pidfile")
  [[ $nginx_health_master =~ ^[1-9][0-9]+$ ]] && kill -0 "$nginx_health_master" || return 1
  nginx_health_workers=$(pgrep -P "$nginx_health_master" -f 'nginx: worker process$' | sort)
}

Nginx_Begin_Candidate() {
  [[ ${web_install_dir:-} =~ ^/[A-Za-z0-9/_.-]+$ ]] || return 1
  mkdir -p "$web_install_dir/conf/vhost" || return 1
  nginx_candidate=$(mktemp "$web_install_dir/conf/.vhost.XXXXXXXX") || return 1
  nginx_candidate_parent=$web_install_dir/conf
}

Nginx_Magento_Candidate() {
  local line
  [[ $vhostdir =~ ^/[A-Za-z0-9/_.-]+$ && ${mphp_ver:-0} =~ ^[0-9]+$ ]] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      '  listen 80;') echo '  # ONEINSTACK_LISTEN' ;;
      '  set $MAGE_ROOT '*) printf '  set $MAGE_ROOT %s;\n' "$vhostdir" ;;
      '  server_name '*) printf '  server_name %s%s;\n  %s\n' "$domain" "$moredomainame" "$Nginx_log" ;;
      '  root $MAGE_ROOT/pub;') printf '%s\n  %s\n' "$line" "$anti_hotlinking" ;;
      *) printf '%s\n' "${line//\/dev\/shm\/php-cgi.sock/\/dev\/shm\/php${mphp_ver}-cgi.sock}" ;;
    esac
  done < "$current_dir/config/magento2.conf" > "$nginx_candidate"
}

Nginx_Commit_Candidate() {
  local temporary=
  if [ -e "$web_install_dir/conf/vhost/$domain.conf" ]; then
    if [ "${nginx_replace_managed:-false}" != true ] || [ "$(head -1 "$web_install_dir/conf/vhost/$domain.conf")" != "# oneinstack-next managed v1; domain=$domain" ]; then
      echo 'Host appeared during creation, or is customized; refusing replacement' >&2
      rm -f -- "$nginx_candidate"
      Nginx_Temporary_Cleanup
      return 1
    fi
  fi
  [ ! -f "$web_install_dir/conf/vhost/_acme-$domain.conf" ] || temporary=$web_install_dir/conf/vhost/_acme-$domain.conf
  Nginx_Render "$nginx_candidate" && Nginx_Activate "$nginx_candidate" "$web_install_dir/conf/vhost/$domain.conf" "$temporary"
  local result=$?
  rm -f -- "$nginx_candidate"
  [ "$result" -eq 0 ] || Nginx_Temporary_Cleanup
  return "$result"
}

Nginx_Temporary_Challenge() {
  local nginx_temporary_only=true
  if [ -e "$web_install_dir/conf/vhost/_acme-$domain.conf" ] && [ "$(head -1 "$web_install_dir/conf/vhost/_acme-$domain.conf")" != "# oneinstack-next temporary ACME: $domain" ]; then
    echo 'ACME temporary filename is already in use by an unmanaged file' >&2
    return 1
  fi
  Nginx_Challenge_Setup || return 1
  mkdir -p "$web_install_dir/conf/vhost" || return 1
  Nginx_Begin_Candidate || return 1
  {
    printf '# oneinstack-next temporary ACME: %s\nserver {\n' "$domain"
    Nginx_Listeners 80
    printf '  server_name %s%s;\n' "$domain" "$moredomainame"
    Nginx_Challenge
    echo '  location / { return 404; }'
    echo '}'
  } > "$nginx_candidate"
  Nginx_Activate "$nginx_candidate" "$web_install_dir/conf/vhost/_acme-$domain.conf"
  local result=$?
  rm -f -- "$nginx_candidate"
  return "$result"
}

Nginx_Temporary_Cleanup() (
  local temporary=$web_install_dir/conf/vhost/_acme-$domain.conf stage
  [ -f "$temporary" ] || exit 0
  exec 9> "$web_install_dir/conf/.oneinstack.lock" || exit 1
  [ "${nginx_group_lock:-false}" = true ] || flock -x 9 || exit 1
  [ "$(head -1 "$temporary")" = "# oneinstack-next temporary ACME: $domain" ] || exit 1
  stage=$(mktemp -d "$web_install_dir/.cleanup.XXXXXXXX") || exit 1
  trap 'Remove_Private_Tree "$stage" "$web_install_dir"' EXIT
  mv "$temporary" "$stage/temporary" || exit 1
  if "$web_install_dir/sbin/nginx" -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" -t && "$web_install_dir/sbin/nginx" -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" -s reload; then exit 0; fi
  mv "$stage/temporary" "$temporary"
  "$web_install_dir/sbin/nginx" -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" -t && "$web_install_dir/sbin/nginx" -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" -s reload
  exit 1
)

Nginx_Upgrade_Binary() (
  local candidate=$1 web_install_dir=$2 bin=$2/sbin/nginx stage pidfile old_master new_master='' attempt healthy=false
  Nginx_Requirements || exit 1
  exec 9> "$web_install_dir/conf/.oneinstack.lock" || exit 1
  flock -x 9 || exit 1
  [ -x "$candidate" ] && [ -x "$bin" ] || exit 1
  "$candidate" -V >&2
  "$candidate" -t -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" || exit 1
  pidfile=$("$bin" -T -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" 2>/dev/null | awk '$1=="pid" && !seen {gsub(/[;"]/,"",$2); print $2; seen=1}')
  [[ $pidfile == /* && -f $pidfile ]] || { echo 'An explicit absolute pid directive is required for managed upgrade' >&2; exit 1; }
  old_master=$(cat "$pidfile")
  [[ $old_master =~ ^[1-9][0-9]+$ ]] && kill -0 "$old_master" || exit 1
  stage=$(mktemp -d "$web_install_dir/.binary.XXXXXXXX") || exit 1
  trap 'Remove_Private_Tree "$stage" "$web_install_dir"' EXIT
  cp -p "$bin" "$stage/old" && install -m 755 "$candidate" "$stage/new" && mv -f "$stage/new" "$bin" || exit 1
  if kill -USR2 "$old_master"; then
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
      new_master=$(cat "$pidfile" 2>/dev/null)
      if [[ $new_master =~ ^[1-9][0-9]+$ && $new_master != "$old_master" ]] &&
          kill -0 "$new_master" && pgrep -P "$new_master" -f 'nginx: worker process' >/dev/null; then
        kill -WINCH "$old_master" || break
        sleep 1
        if curl --noproxy '*' --silent --show-error --fail --max-time 5 "${nginx_upgrade_health_url:-http://127.0.0.1/}" >/dev/null; then healthy=true; break; fi
      fi
      sleep 1
    done
  fi
  if [ "$healthy" = true ] && cp -p "$stage/old" "$stage/previous" &&
      mv -f "$stage/previous" "$web_install_dir/sbin/nginx.previous" && kill -QUIT "$old_master"; then
    exit 0
  fi
  if ! cp -p "$stage/old" "$stage/restore" || ! mv -f "$stage/restore" "$bin" || ! kill -HUP "$old_master"; then
    echo 'Binary rollback could not restore/reload the previous master; retaining any live new master for manual recovery' >&2
    exit 1
  fi
  healthy=false
  for attempt in 1 2 3 4 5; do
    if pgrep -P "$old_master" -f 'nginx: worker process' >/dev/null; then healthy=true; break; fi
    sleep 1
  done
  if [ "$healthy" != true ]; then
    echo 'Previous master did not regain workers; retaining the new master for manual recovery' >&2
    exit 1
  fi
  if [[ $new_master =~ ^[1-9][0-9]+$ && $new_master != "$old_master" ]]; then kill -QUIT "$new_master" || exit 1; fi
  for attempt in 1 2 3 4 5; do
    [ "$(cat "$pidfile" 2>/dev/null)" != "$old_master" ] || break
    sleep 1
  done
  [ "$(cat "$pidfile" 2>/dev/null)" = "$old_master" ] || {
    echo 'Previous workers resumed, but the PID-file handoff is still incomplete; inspect both masters before another upgrade' >&2
    exit 1
  }
  echo 'New Nginx master/worker/request verification failed; restored old binary/master and confirmed workers' >&2
  exit 1
)

# Frontend plus Apache/Tomcat are one rollback set. The outer lock stays held
# while the frontend helper runs; its nested activation does not reacquire it.
Nginx_Group_Run() (
  local kind=$1 writer=$2 stage index=0 path status backend_ok attempt code backend_was_running=false
  local -a paths=("$web_install_dir/conf/vhost/$domain.conf")
  [[ $kind =~ ^(apache|tomcat)$ ]] || exit 2
  Nginx_Requirements || exit 1
  if [ "$kind" = tomcat ]; then
    local target_pid target_uid java_executable
    command -v runuser >/dev/null || exit 1
    target_uid=$(id -u "$run_user") || exit 1
    [ "$target_uid" -gt 0 ] || { echo 'Tomcat runtime user must not be root' >&2; exit 1; }
    for target_pid in $(Tomcat_Target_Pids); do
      [ "$(stat -c %u "/proc/$target_pid")" = "$target_uid" ] || { echo 'Target Tomcat process user differs from run_user; migrate the service explicitly' >&2; exit 1; }
      java_executable=$(readlink -f "/proc/$target_pid/exe") || exit 1
      tomcat_runtime_java_home=${java_executable%/bin/java}
      backend_was_running=true
    done
  elif Apache_Target_Running; then backend_was_running=true; fi
  if [ "$kind" = tomcat ] && ! command -v xmllint >/dev/null; then
    echo 'Install xmllint from the signed OS package repository before creating a Tomcat host' >&2
    Nginx_Temporary_Cleanup
    exit 1
  fi
  exec 8> "$web_install_dir/conf/.oneinstack.lock" || exit 1
  flock -x 8 || exit 1
  nginx_group_lock=true
  if [ -e "$web_install_dir/conf/vhost/$domain.conf" ] && [ "${nginx_replace_managed:-false}" != true ]; then
    echo 'Host appeared during creation; refusing frontend/backend replacement' >&2
    Nginx_Temporary_Cleanup
    exit 1
  fi
  stage=$(mktemp -d "$web_install_dir/.site-change.XXXXXXXX") || exit 1
  trap 'Remove_Private_Tree "$stage" "$web_install_dir"' EXIT
  backend_candidate=$stage/backend.conf
  backend_server_candidate=$stage/server.xml
  if [ "$kind" = apache ]; then paths+=("$apache_install_dir/conf/vhost/$domain.conf")
  else paths+=("$tomcat_install_dir/conf/vhost/$domain.xml" "$tomcat_install_dir/conf/server.xml"); fi
  for path in "${paths[@]}"; do
    [ ! -L "$path" ] || { Remove_Private_Tree "$stage" "$web_install_dir"; exit 1; }
    [ ! -e "$path" ] || cp -p "$path" "$stage/old.$index" || exit 1
    ((index+=1))
  done
  [ "$kind" != tomcat ] || cp -p "$tomcat_install_dir/conf/server.xml" "$backend_server_candidate" || exit 1
  Nginx_Group_Cleanup() {
    status=$?
    if [ "$status" -ne 0 ]; then
      index=0
      for path in "${paths[@]}"; do
        if [ -f "$stage/old.$index" ]; then
          local restore
          restore=$(mktemp "$(dirname "$path")/.restore.XXXXXXXX") && cp -p "$stage/old.$index" "$restore" && mv -f "$restore" "$path" || echo "Restore failed: $path" >&2
        else rm -f -- "$path"; fi
        ((index+=1))
      done
      # A challenge-only server belongs to this failed new-site operation.
      if [ -f "$web_install_dir/conf/vhost/_acme-$domain.conf" ] && [ "$(head -1 "$web_install_dir/conf/vhost/_acme-$domain.conf")" = "# oneinstack-next temporary ACME: $domain" ]; then
        rm -f -- "$web_install_dir/conf/vhost/_acme-$domain.conf"
      fi
      "$web_install_dir/sbin/nginx" -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" -t &&
        "$web_install_dir/sbin/nginx" -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" -s reload
      if [ "$kind" = apache ]; then
        if [ "$backend_was_running" = true ]; then "$apache_install_dir/bin/apachectl" -t && "$apache_install_dir/bin/apachectl" -k graceful
        else "$apache_install_dir/bin/apachectl" -k stop; fi
      elif [ "$backend_was_running" = true ]; then Tomcat_Control restart
      else Tomcat_Control stop; fi
      echo 'Frontend/backend activation failed; previous configuration set restored' >&2
    fi
    [ -z "${nginx_candidate:-}" ] || Remove_Private_File "$nginx_candidate" "$web_install_dir/conf"
    Remove_Private_Tree "$stage" "$web_install_dir"
    return "$status"
  }
  trap Nginx_Group_Cleanup EXIT
  # Publish the writer's success summary only after backend requests pass.
  "$writer" > "$stage/writer.stdout" || exit 1
  backend_ok=false
  for attempt in 1 2 3 4 5; do
    code=$(curl --noproxy '*' --silent --max-time 3 -o /dev/null -w '%{http_code}' --resolve "$domain:${nginx_http_port:-80}:127.0.0.1" "http://$domain:${nginx_http_port:-80}/oneinstack-backend-probe")
    # Force-HTTPS hosts need an application request on the TLS listener.
    if [ "$code" = 301 ] && [ "${nginx_ssl_flag:-n}" = y ]; then
      code=$(curl --noproxy '*' --silent --max-time 3 --cacert "$PATH_SSL/$domain.crt" -o /dev/null -w '%{http_code}' --resolve "$domain:${nginx_https_port:-443}:127.0.0.1" "https://$domain:${nginx_https_port:-443}/oneinstack-backend-probe")
    fi
    if [[ $code =~ ^[2345][0-9][0-9]$ && ! $code =~ ^50[234]$ ]]; then backend_ok=true; break; fi
    sleep 1
  done
  [ "$backend_ok" = true ] || exit 1
  cat "$stage/writer.stdout"
)

Managed_Publish() {
  local candidate=$1 target=$2 staging
  [ ! -L "$target" ] || return 1
  staging=$(mktemp "$(dirname "$target")/.oneinstack.XXXXXXXX") || return 1
  install -m 644 "$candidate" "$staging" || { rm -f "$staging"; return 1; }
  if [ -e "$target" ]; then
    chmod --reference="$target" "$staging" && chown --reference="$target" "$staging" || { rm -f "$staging"; return 1; }
  fi
  mv -f "$staging" "$target"
}

Apache_Test_Candidate() {
  local tree=${backend_candidate%/*}/apache-conf file
  cp -a "$apache_install_dir/conf" "$tree" || return 1
  cp "$backend_candidate" "$tree/vhost/$domain.conf" || return 1
  while IFS= read -r -d '' file; do
    awk -v old="$apache_install_dir/conf/" -v new="$tree/" '
      {out="";rest=$0;while ((p=index(rest,old))>0) {out=out substr(rest,1,p-1) new;rest=substr(rest,p+length(old))} line=out rest;
       if (line ~ /^[[:space:]]*Include(Optional)?[[:space:]]+"?conf\//) {
         directive=$1;path=$2;gsub(/"/,"",path);sub(/^conf\//,"",path);print directive " \"" new path "\""
       } else print line}' "$file" > "$tree/.rewrite" || return 1
    cat "$tree/.rewrite" > "$file" || return 1
  done < <(find "$tree" -type f -name '*.conf' -print0)
  rm -f "$tree/.rewrite"
  "$apache_install_dir/bin/apachectl" -t -f "$tree/httpd.conf"
}

Apache_Target_Running() {
  local pid executable prefix
  prefix=$(readlink -f "$apache_install_dir") || return 1
  for pid in $(pgrep -x httpd); do
    executable=$(readlink "/proc/$pid/exe") || continue
    [[ $executable != "$prefix/bin/httpd"* ]] || return 0
  done
  return 1
}

Tomcat_Target_Pids() {
  local pid arg prefix matched
  prefix=$(readlink -f "$tomcat_install_dir") || return 1
  for pid in $(pgrep -f 'org.apache.catalina.startup.Bootstrap'); do
    matched=false
    while IFS= read -r -d '' arg; do
      case $arg in
        "-Dcatalina.base=$tomcat_install_dir"|"-Dcatalina.base=$prefix") matched=true ;;
      esac
    done < "/proc/$pid/cmdline"
    [ "$matched" != true ] || printf '%s\n' "$pid"
  done
}

Tomcat_Control() {
  local action=$1 pid executable java_home=${tomcat_runtime_java_home:-${JAVA_HOME:-}} attempt
  local -a pids=()
  while IFS= read -r pid; do [ -z "$pid" ] || pids+=("$pid"); done < <(Tomcat_Target_Pids)
  if [ ${#pids[@]} -gt 0 ]; then
    executable=$(readlink -f "/proc/${pids[0]}/exe") || return 1
    java_home=${executable%/bin/java}
    # Runtime-owned Tomcat scripts must never be evaluated with root authority.
    for pid in "${pids[@]}"; do runuser -u "$run_user" -- /bin/kill -TERM "$pid" || return 1; done
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
      [ -n "$(Tomcat_Target_Pids)" ] || break
      sleep 1
    done
    [ -z "$(Tomcat_Target_Pids)" ] || { echo 'Tomcat did not stop gracefully; refusing forced kill' >&2; return 1; }
  fi
  [ "$action" != stop ] || return 0
  if [ -z "$java_home" ] && [ -r /etc/init.d/tomcat ]; then
    java_home=$(awk '/^export JAVA_HOME=\/[A-Za-z0-9/_.-]+$/ {sub(/^export JAVA_HOME=/,""); print; found=1} END {if (!found) exit 1}' /etc/init.d/tomcat) || java_home=
  fi
  [[ $java_home =~ ^/[A-Za-z0-9/_.-]+$ ]] || { echo 'Set JAVA_HOME for a stopped/custom Tomcat service before activation' >&2; return 1; }
  [ -x "$java_home/bin/java" ] || return 1
  runuser -u "$run_user" -- env JAVA_HOME="$java_home" CATALINA_HOME="$tomcat_install_dir" CATALINA_BASE="$tomcat_install_dir" "$tomcat_install_dir/bin/startup.sh" || return 1
}
