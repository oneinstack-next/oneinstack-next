#!/bin/bash
# Parse nginx -V's shell-quoted arguments as data, never eval them.
Nginx_Build_Arguments() {
  local input=$1 prefix=$2 quote=none token='' started=false escaped=false char index item has_prefix=false
  local -a parsed=() result=()
  for ((index=0; index<${#input}; index++)); do
    char=${input:index:1}
    if [ "$escaped" = true ]; then token+=$char; started=true; escaped=false; continue; fi
    case $quote in
      single) if [ "$char" = "'" ]; then quote=none; else token+=$char; fi ;;
      double)
        case $char in '"') quote=none ;; '\') escaped=true ;; *) token+=$char ;; esac ;;
      none)
        case $char in
          "'") quote=single; started=true ;;
          '"') quote=double; started=true ;;
          '\') escaped=true; started=true ;;
          ' '|$'\t'|$'\n')
            if [ "$started" = true ]; then parsed+=("$token"); token=''; started=false; fi ;;
          *) token+=$char; started=true ;;
        esac ;;
    esac
  done
  [ "$quote" = none ] && [ "$escaped" = false ] || { Source_Error 'Unterminated configure argument quoting'; return 1; }
  [ "$started" != true ] || parsed+=("$token")
  for item in "${parsed[@]}"; do
    case $item in
      --prefix=*) item=--prefix=$prefix; has_prefix=true ;;
      --with-openssl=*) item=--with-openssl=../openssl-$openssl_ver ;;
      --with-pcre=*) item=--with-pcre=../pcre-$pcre_ver ;;
      --add-module=*|--add-dynamic-module=*)
        Source_Error 'External module source needs a reviewed upgrade plan; current binary/configuration retained'
        return 1 ;;
    esac
    result+=("$item")
  done
  [ "$has_prefix" = true ] || result+=("--prefix=$prefix")
  nginx_build_args=("${result[@]}")
}

Nginx_Read_Build_Arguments() {
  local prefix=$1 info line args='' count=0
  info=$("$prefix/sbin/nginx" -V 2>&1) || return 1
  printf '%s\n' "$info" >&2
  while IFS= read -r line; do
    case $line in 'configure arguments: '*) args=${line#configure arguments: }; ((count+=1)) ;; esac
  done <<< "$info"
  [ "$count" -eq 1 ] || { Source_Error 'Cannot identify unique configure arguments from target binary'; return 1; }
  Nginx_Build_Arguments "$args" "$prefix"
}
