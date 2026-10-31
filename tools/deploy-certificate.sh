#!/bin/bash
# acme.sh writes only to a private inbox; this hook validates the complete pair
# and rolls both managed files back if nginx test/reload fails.
set -o pipefail
current_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd) || exit 1
. "$current_dir/include/nginx_config.sh"
web_install_dir=$1 domain=$2 inbox=$3 expected_key=${4:-}
[[ $web_install_dir =~ ^/[A-Za-z0-9/_.-]+$ && $domain =~ ^[A-Za-z0-9][A-Za-z0-9.-]+$ && $domain != *..* ]] || exit 2
[ "$inbox" = "$web_install_dir/conf/acme-certs/$domain" ] || exit 2
Nginx_Requirements || exit 1
Prepare_Private_Dir "$web_install_dir/conf/acme-certs" && Prepare_Private_Dir "$inbox" || exit 1
(
  flock -x 9 || exit 1
  stage=$(mktemp -d "$web_install_dir/.certificate.XXXXXXXX") || exit 1
  trap 'Remove_Private_Tree "$stage" "$web_install_dir"' EXIT
  bin=$web_install_dir/sbin/nginx
  ssl=$web_install_dir/conf/ssl
  [ ! -L "$ssl" ] || exit 1
  PATH_SSL=$ssl
  nginx_ssl_flag=y
  nginx_temporary_only=false
  [ -f "$web_install_dir/conf/vhost/$domain.conf" ] || nginx_temporary_only=true
  mkdir -p "$ssl" || exit 1
  rm -f "$inbox/deployment.receipt"
  openssl x509 -in "$inbox/fullchain.pem" -noout -checkend 0 || exit 1
  if [[ $domain =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
    openssl x509 -in "$inbox/fullchain.pem" -noout -checkip "$domain" || exit 1
  else openssl x509 -in "$inbox/fullchain.pem" -noout -checkhost "$domain" || exit 1; fi
  cert_public=$(openssl x509 -in "$inbox/fullchain.pem" -pubkey -noout | openssl pkey -pubin -outform DER | sha256sum) || exit 1
  key_public=$(openssl pkey -in "$inbox/key.pem" -pubout -outform DER | sha256sum) || exit 1
  [ "$cert_public" = "$key_public" ] || exit 1
  if [ -n "$expected_key" ]; then
    case $expected_key in 2048|3072|4096|8192|ec-256|ec-384|ec-521) ;; *) exit 2 ;; esac
    public_info=$(openssl pkey -in "$inbox/key.pem" -text_pub -noout) || exit 1
    expected_bits=${expected_key#ec-}
    grep -F "Public-Key: ($expected_bits bit)" <<< "$public_info" >/dev/null || { echo 'Certificate key length differs from selection; renew explicitly or select the cached key size' >&2; exit 1; }
    if [[ $expected_key == ec-* ]]; then grep -F 'ASN1 OID:' <<< "$public_info" >/dev/null || exit 1
    else grep -F 'Modulus:' <<< "$public_info" >/dev/null || exit 1; fi
  fi
  Nginx_Capture_Workers || exit 1
  baseline=$(Nginx_Tree_Digest) || exit 1
  for ext in crt key; do
    [ ! -L "$ssl/$domain.$ext" ] || exit 1
    [ ! -e "$ssl/$domain.$ext" ] || cp -p "$ssl/$domain.$ext" "$stage/old.$ext" || exit 1
  done
  install -m 644 "$inbox/fullchain.pem" "$stage/new.crt" && install -m 600 "$inbox/key.pem" "$stage/new.key" || exit 1
  cp -a "$web_install_dir/conf" "$stage/tree" || exit 1
  cp "$stage/new.crt" "$stage/tree/ssl/$domain.crt" && cp "$stage/new.key" "$stage/tree/ssl/$domain.key" || exit 1
  Nginx_Test_Config_Tree "$stage/tree" || exit 1
  [ "$baseline" = "$(Nginx_Tree_Digest)" ] || { echo 'Certificate/configuration baseline changed' >&2; exit 1; }
  if mv -f "$stage/new.crt" "$ssl/$domain.crt" && mv -f "$stage/new.key" "$ssl/$domain.key" &&
      "$bin" -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" -t && "$bin" -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" -s reload && Nginx_Health; then
    receipt_stage=$(mktemp "$inbox/.receipt.XXXXXXXX") || receipt_stage=
    receipt_digest=$(sha256sum "$ssl/$domain.crt") || receipt_digest=''
    receipt_digest=${receipt_digest%% *}
    if [ -n "$receipt_stage" ] && [ -n "$receipt_digest" ] && printf '%s\n%s\n' "$receipt_digest" "$expected_key" > "$receipt_stage" && chmod 600 "$receipt_stage" && mv -f "$receipt_stage" "$inbox/deployment.receipt"; then exit 0; fi
    [ -z "$receipt_stage" ] || rm -f "$receipt_stage"
  fi
  for ext in crt key; do
    if [ -e "$stage/old.$ext" ]; then cp -p "$stage/old.$ext" "$ssl/$domain.$ext"; else rm -f -- "$ssl/$domain.$ext"; fi
  done
  "$bin" -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" -t && "$bin" -p "$web_install_dir/" -c "$web_install_dir/conf/nginx.conf" -s reload
  echo 'Certificate deployment failed; previous certificate pair restored' >&2
  exit 1
) 9> "$web_install_dir/conf/.oneinstack.lock"
