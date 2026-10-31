#!/bin/bash
# The acme client is a tool artifact; its own --upgrade bypass is not used.
Install_Acme() (
  local stage filename=acme.sh-${acme_ver}.tar.gz
  stage=$(mktemp -d "${current_dir}/src/.acme.XXXXXXXX") || exit 1
  trap 'Remove_Private_Tree "$stage" "$current_dir/src"' EXIT
  Download_Artifact "$filename" "$stage" || exit 1
  tar xzf "$stage/$filename" -C "$stage" || exit 1
  [ -f "$stage/acme.sh-${acme_ver}/acme.sh" ] || exit 1
  cd "$stage/acme.sh-${acme_ver}" || exit 1
  ./acme.sh --install --auto-upgrade 0
)

Upgrade_Acme() {
  Install_Acme
}

Issue_Nginx_Certificate() {
  local name issue_status expected_receipt inbox=$web_install_dir/conf/acme-certs/$domain
  local -a names=(-d "$domain") mode=() server=() aliases=()
  read -r -a aliases <<< "$moredomainame"
  Nginx_Domain_Valid "$domain" "${aliases[@]}" || return 1
  [[ $current_dir =~ ^/[A-Za-z0-9/_.-]+$ ]] || return 1
  [ -x "$HOME/.acme.sh/acme.sh" ] || Install_Acme || return 1
  if [ -z "${CERT_KEYLENGTH:-}" ]; then
    echo 'RSA: 2048, 3072, 4096, 8192; ECC: ec-256, ec-384, ec-521'
    read -r -e -p 'Please enter your cert key length (default ec-256): ' CERT_KEYLENGTH
    CERT_KEYLENGTH=${CERT_KEYLENGTH:-ec-256}
  fi
  case $CERT_KEYLENGTH in 2048|3072|4096|8192|ec-256|ec-384|ec-521) ;; *) return 1 ;; esac
  for name in "${aliases[@]}"; do names+=(-d "$name"); done
  [ "${acme_staging:-false}" != true ] || server=(--staging)
  if [ ! -s "$HOME/.acme.sh/account.conf" ]; then
    read -r -e -p 'Please enter your email: ' EMAIL
    [[ $EMAIL =~ ^[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+$ ]] || return 1
    "$HOME/.acme.sh/acme.sh" --register-account --auto-upgrade 0 --server letsencrypt "${server[@]}" -m "$EMAIL" || return 1
  fi
  if [ "${dnsapi_flag:-n}" = y ] || [[ $moredomainame == *'*.'* ]]; then
    if [ -z "${DNS_PRO:-}" ]; then read -r -e -p 'Please enter your DNS provider (credentials must be exported before running): ' DNS_PRO; fi
    [[ $DNS_PRO =~ ^[a-z0-9_]+$ ]] && [ -f "$HOME/.acme.sh/dnsapi/dns_$DNS_PRO.sh" ] || return 1
    mode=(--dns "dns_$DNS_PRO")
  else
    Nginx_Temporary_Challenge || return 1
    mode=(-w "$web_install_dir/conf/acme")
  fi
  "$HOME/.acme.sh/acme.sh" --issue --auto-upgrade 0 --server letsencrypt "${server[@]}" -k "$CERT_KEYLENGTH" "${mode[@]}" "${names[@]}"
  issue_status=$?
  if [ "$issue_status" -ne 0 ] && [ "$issue_status" -ne 2 ]; then
    Nginx_Temporary_Cleanup
    return 1
  fi
  Prepare_Private_Dir "$web_install_dir/conf/acme-certs" && Prepare_Private_Dir "$inbox" || return 1
  local -a ecc=()
  [[ $CERT_KEYLENGTH != ec-* ]] || ecc=(--ecc)
  rm -f "$inbox/deployment.receipt"
  "$HOME/.acme.sh/acme.sh" --install-cert --auto-upgrade 0 "${ecc[@]}" -d "$domain" \
    --fullchain-file "$inbox/fullchain.pem" --key-file "$inbox/key.pem" \
    --reloadcmd "bash '$current_dir/tools/deploy-certificate.sh' '$web_install_dir' '$domain' '$inbox' '$CERT_KEYLENGTH'" || return 1
  # acme.sh can log a failed reload command without returning a failure. A
  # receipt from our own successful deployment is required before continuing.
  expected_receipt=$(sha256sum "$inbox/fullchain.pem"); expected_receipt=${expected_receipt%% *}
  [ -f "$inbox/deployment.receipt" ] && [ "$(head -1 "$inbox/deployment.receipt")" = "$expected_receipt" ] &&
    [ "$(sed -n '2p' "$inbox/deployment.receipt")" = "$CERT_KEYLENGTH" ] || return 1
}

Nginx_Selfsigned_Certificate() (
  local stage inbox=$web_install_dir/conf/acme-certs/$domain name san='' sep=''
  local -a names=()
  read -r -a names <<< "$domain $moredomainame"
  Nginx_Domain_Valid "${names[@]}" || exit 1
  stage=$(mktemp -d "$PATH_SSL/.selfsigned.XXXXXXXX") || exit 1
  trap 'Remove_Private_Tree "$stage" "$PATH_SSL"' EXIT
  for name in "${names[@]}"; do
    if [[ $name =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then san+="${sep}IP:$name"; else san+="${sep}DNS:$name"; fi
    sep=,
  done
  printf 'subjectAltName=%s\n' "$san" > "$stage/extensions"
  openssl req -utf8 -new -newkey rsa:2048 -sha256 -nodes -out "$stage/site.csr" -keyout "$stage/site.key" \
    -subj "/C=${SELFSIGNEDSSL_C}/ST=${SELFSIGNEDSSL_ST}/L=${SELFSIGNEDSSL_L}/O=${SELFSIGNEDSSL_O}/OU=${SELFSIGNEDSSL_OU}/CN=$domain" || exit 1
  openssl x509 -req -days 365 -sha256 -in "$stage/site.csr" -signkey "$stage/site.key" -extfile "$stage/extensions" -out "$stage/site.crt" || exit 1
  Nginx_Temporary_Challenge || exit 1
  Prepare_Private_Dir "$web_install_dir/conf/acme-certs" && Prepare_Private_Dir "$inbox" || exit 1
  install -m 644 "$stage/site.crt" "$inbox/fullchain.pem" && install -m 600 "$stage/site.key" "$inbox/key.pem" || exit 1
  bash "$current_dir/tools/deploy-certificate.sh" "$web_install_dir" "$domain" "$inbox" || exit 1
  install -m 600 "$stage/site.csr" "$PATH_SSL/$domain.csr"
)
