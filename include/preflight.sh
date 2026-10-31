#!/bin/bash
# Additions downloaded by post-install helpers must be checked before building
# the selected stack, not discovered only after PHP has been installed.
MongoDB_Artifact_For_PHP() {
  local version=$1 main
  if [[ $version =~ ^([5-8])([0-9])$ ]]; then
    main=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}
  elif [[ $version =~ ^([0-9]+)\.([0-9]+)(\.[0-9]+)?$ ]]; then
    main=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}
  else
    Source_Error 'Cannot select MongoDB extension without an exact supported PHP version'
    return 1
  fi
  case $main in
    5.[3-6]) printf '%s\n' mongo-1.6.16.tgz ;;
    7.0) printf '%s\n' mongodb-1.9.2.tgz ;;
    7.[1-3]) printf '%s\n' mongodb-1.16.2.tgz ;;
    7.4|8.0) printf '%s\n' mongodb-1.20.1.tgz ;;
    8.[1-5]) printf 'mongodb-%s.tgz\n' "$pecl_mongodb_ver" ;;
    *) Source_Error 'Selected PHP/MongoDB extension combination is unsupported'; return 1 ;;
  esac
}

Prepare_Source_Selection() {
  if [ "${Family:-}" = rhel ] && [ "${RHEL_ver:-}" = 8 ] && [[ ${db_option:-} =~ ^(9|10)$ ]] && [ "$dbinstallmethod" = 1 ]; then
    Source_Error 'Percona on this OS requires an explicitly selected, reviewed source install; choose --dbinstallmethod 2'
    return 1
  fi
  if [ "${dbinstallmethod:-1}" = 2 ]; then
    case ${db_option:-} in 2|5|6|7|10) boost_ver=$boost_oldver ;; 9) boost_ver=$boost_percona_ver ;; esac
  fi
}

Preflight_Extras() {
  local download_preflight=true
  local slot key version main filename ext
  local -a slots=(53 54 55 56 70 71 72 73 74 80 81 82 83 84 85) files=()
  slot=${mphp_ver:-}
  if [ -z "$slot" ] && [[ ${php_option:-} =~ ^([1-9]|1[0-5])$ ]]; then slot=${slots[$((php_option-1))]}; fi
  if [ -n "$slot" ]; then key=php${slot}_ver; version=${!key}; main=${version%.*}
  elif [ -x "$php_install_dir/bin/php-config" ]; then version=$("$php_install_dir/bin/php-config" --version); main=${version%.*}; fi
  if [ "${pecl_phalcon:-0}" = 1 ]; then
    case $main in
      5.5|5.6|7.0|7.1) files+=(cphalcon-3.4.5.tar.gz) ;;
      7.2|7.3|7.4) files+=(phalcon-5.4.0.tgz) ;;
      8.[0-4]) files+=("phalcon-$phalcon_ver.tgz") ;;
      *) Source_Error 'Selected PHP/Phalcon combination is unsupported'; return 1 ;;
    esac
  fi
  for ext in yaf yar; do
    key=pecl_$ext
    if [ "${!key:-0}" = 1 ]; then
      [[ $main =~ ^(7\.[0-4]|8\.[0-4])$ ]] || { Source_Error "Unsupported PHP/$ext combination"; return 1; }
      key=${ext}_ver; files+=("$ext-${!key}.tgz")
    fi
  done
  if [ "${pecl_swoole:-0}" = 1 ]; then
    case $main in
      5.[3-6]) files+=(swoole-1.10.5.tgz) ;;
      7.0|7.1) files+=(swoole-4.5.2.tgz) ;;
      7.[2-4]) files+=(swoole-4.8.12.tgz) ;;
      8.0) Source_Error 'PHP 8.0/Swoole compatibility requires a reviewed package selection'; return 1 ;;
      8.[12]) files+=(swoole-6.1.7.tgz) ;;
      8.[3-5]) files+=("swoole-$swoole_ver.tgz") ;;
      *) return 1 ;;
    esac
  fi
  if [ "${pecl_xdebug:-0}" = 1 ]; then
    Source_Error 'Xdebug/webgrind integration requires a pinned webgrind release; see source coverage'
    return 1
  fi
  if [ "${publish_diagnostics:-false}" = true ]; then files+=(xprober.php); [ "${phpcache_option:-}" != 1 ] || files+=(ocp.php); fi
  for filename in "${files[@]}"; do
    Download_Artifact "$filename" || return 1
  done
}

Preflight_Backup_Tools() {
  local download_preflight=true
  local choice arch_name=amd64 file program status=0
  [ "${ARCH:-}" != aarch64 ] || arch_name=arm64
  for choice in $desc_bk; do
    file=; program=
    case $choice in
      3) file=ossutil-linux-${ARCH}; program=ossutil ;;
      4) file=coscli-linux; program=coscli ;;
      5) file=upx_0.4.8_linux_${arch_name}.tar.gz; program=upx ;;
      6) file=qshell-v2.15.0-linux-${arch_name}.tar.gz; program=qshell ;;
      7) file=awscli-exe-linux-${ARCH}.zip; program=aws ;;
      8) file=dbxcli-linux-amd64; program=dbxcli; [ "$arch_name" != arm64 ] || file=dbxcli-linux-arm ;;
    esac
    [ -n "$file" ] || continue
    command -v "$program" >/dev/null && continue
    Download_Artifact "$file" || status=1
  done
  return "$status"
}

Preflight_WAF() {
  local download_preflight=true file
  local -a files=("luajit2-$luajit2_ver.tar.gz" "lua-resty-core-$lua_resty_core_ver.tar.gz"
    "lua-resty-lrucache-$lua_resty_lrucache_ver.tar.gz" "lua-cjson-$lua_cjson_ver.tar.gz"
    "openssl-$openssl_ver.tar.gz" "pcre-$pcre_ver.tar.gz" ngx_devel_kit.tar.gz ngx_lua_waf.tar.gz)
  if [ "$1" = nginx ]; then files+=("nginx-$nginx_ver.tar.gz" "lua-nginx-module-$lua_nginx_module_ver.tar.gz")
  else files+=("tengine-$tengine_ver.tar.gz" lua-nginx-module.tar.gz); fi
  for file in "${files[@]}"; do Download_Artifact "$file" || return 1; done
}
