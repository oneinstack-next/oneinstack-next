#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
# BLOG:  https://linuxeye.com
#
#

Show_Help() {
  echo
  echo "Usage: $0  command ...[version]....
  --help, -h                  Show this help message
  --nginx        [version]    Upgrade Nginx
  --tengine      [version]    Upgrade Tengine
  --openresty    [version]    Upgrade OpenResty
  --apache       [version]    Upgrade Apache
  --tomcat       [version]    Upgrade Tomcat
  --db           [version]    Upgrade MySQL/MariaDB/Percona
  --php          [version]    Upgrade PHP
  --redis        [version]    Upgrade Redis
  --memcached    [version]    Upgrade Memcached
  --phpmyadmin   [version]    Upgrade phpMyAdmin
  --script                    Upgrade scripts latest
  --acme.sh                   Upgrade acme.sh latest
  --download_provider [mirrorone|official]
  --mirror_link [https://host] MirrorOne base URL
  --mirror_force_redirect [true|false]
  --download_fallback [none|official]
  --check-versions            Check remote candidates without installing
  "
}

for early_arg in "$@"; do
  case $early_arg in
    -h|--help) Show_Help; exit 0 ;;
  esac
done
if [ "${1:-}" = --check-versions ]; then
  exec bash "$(dirname -- "${BASH_SOURCE[0]}")/tools/sourcectl.sh" --check-versions "${@:2}"
fi

export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
clear
printf "
#######################################################################
#                    Upgrade Software versions                        #
#######################################################################
"
# Check if user is root
[ $(id -u) != "0" ] && { echo "${CFAILURE}Error: You must be root to run this script${CEND}"; exit 1; }

current_dir=$(dirname "`readlink -f $0`")
pushd ${current_dir} > /dev/null
. ./include/version_data.sh
Read_Versions "${current_dir}/versions.txt" || exit 1
. ./options.conf
# The checkout path is runtime state, not a migrated user setting.
current_dir=$PWD
. ./include/color.sh
. ./include/download.sh
. ./include/get_char.sh
. ./include/upgrade_web.sh
. ./include/upgrade_db.sh
. ./include/upgrade_php.sh
. ./include/upgrade_redis.sh
. ./include/upgrade_memcached.sh
. ./include/upgrade_phpmyadmin.sh
. ./include/upgrade_script.sh
. ./include/acme.sh
. ./include/nginx_config.sh

# get the out ip country


ARG_NUM=$#
TEMP=`getopt -o h --long download_provider:,mirror_link:,mirror_force_redirect:,download_fallback:,help,nginx:,tengine:,openresty:,apache:,tomcat:,db:,php:,redis:,memcached:,phpmyadmin:,script,acme.sh -- "$@" 2>/dev/null`
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
eval set -- "${TEMP}"
while :; do
  [ -z "$1" ] && break;
  case "$1" in
    --download_provider|--mirror_link|--mirror_force_redirect|--download_fallback)
      printf -v "${1#--}" '%s' "$2"; shift 2
      ;;
    -h|--help)
      Show_Help; exit 0
      ;;
    --nginx)
      Source_Version_Validate "$2" || exit 2
      nginx_flag=y; NEW_nginx_ver=$2; shift 2
      ;;
    --tengine)
      Source_Version_Validate "$2" || exit 2
      tengine_flag=y; NEW_tengine_ver=$2; shift 2
      ;;
    --openresty)
      Source_Version_Validate "$2" || exit 2
      openresty_flag=y; NEW_openresy_ver=$2; shift 2
      ;;
    --apache)
      Source_Version_Validate "$2" || exit 2
      apache_flag=y; NEW_apache_ver=$2; shift 2
      ;;
    --tomcat)
      Source_Version_Validate "$2" || exit 2
      tomcat_flag=y; NEW_tomcat_ver=$2; shift 2
      ;;
    --db)
      Source_Version_Validate "$2" || exit 2
      db_flag=y; NEW_db_ver=$2; shift 2
      ;;
    --php)
      Source_Version_Validate "$2" || exit 2
      php_flag=y; NEW_php_ver=$2; shift 2
      ;;
    --redis)
      Source_Version_Validate "$2" || exit 2
      redis_flag=y; NEW_redis_ver=$2; shift 2
      ;;
    --memcached)
      Source_Version_Validate "$2" || exit 2
      memcached_flag=y; NEW_memcached_ver=$2; shift 2
      ;;
    --phpmyadmin)
      Source_Version_Validate "$2" || exit 2
      phpmyadmin_flag=y; NEW_phpmyadmin_ver=$2; shift 2
      ;;
    --script)
      NEW_Script_ver=latest; shift 1
      ;;
    --acme.sh)
      NEW_acme_ver=latest; shift 1
      ;;
    --)
      shift
      ;;
    *)
      echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
      ;;
  esac
done

Source_Validate || exit 2
. ./include/check_os.sh
. ./include/check_dir.sh
[ "$ARG_NUM" -ne 0 ] || Source_Menu || exit 2
Source_Summary
Source_Start_Run || exit 1

Menu() {
  while :; do
    printf "
What Are You Doing?
\t${CMSG} 1${CEND}. Upgrade Nginx/Tengine/OpenResty
\t${CMSG} 2${CEND}. Upgrade Apache
\t${CMSG} 3${CEND}. Upgrade Tomcat
\t${CMSG} 4${CEND}. Upgrade MySQL/MariaDB/Percona
\t${CMSG} 5${CEND}. Upgrade PHP
\t${CMSG} 6${CEND}. Upgrade Redis
\t${CMSG} 7${CEND}. Upgrade Memcached
\t${CMSG} 8${CEND}. Upgrade phpMyAdmin
\t${CMSG} 9${CEND}. Upgrade scripts latest
\t${CMSG}10${CEND}. Upgrade acme.sh latest
\t${CMSG} q${CEND}. Exit
"
    echo
    read -e -p "Please input the correct option: " Upgrade_flag
    if [[ ! "${Upgrade_flag}" =~ ^[1-9,q]$|^10$ ]]; then
      echo "${CWARNING}input error! Please only input 1~10 and q${CEND}"
    else
      case "${Upgrade_flag}" in
        1)
          [ -e "${nginx_install_dir}/sbin/nginx" ] && Upgrade_Nginx
          [ -e "${tengine_install_dir}/sbin/nginx" ] && Upgrade_Tengine
          [ -e "${openresty_install_dir}/nginx/sbin/nginx" ] && Upgrade_OpenResty
          ;;
        2)
          Upgrade_Apache
          ;;
        3)
          Upgrade_Tomcat
          ;;
        4)
          Upgrade_DB
          ;;
        5)
          Upgrade_PHP
          ;;
        6)
          Upgrade_Redis
          ;;
        7)
          Upgrade_Memcached
          ;;
        8)
          Upgrade_phpMyAdmin
          ;;
        9)
          Upgrade_Script
          ;;
        10)
          [ -e ~/.acme.sh/acme.sh ] && { Upgrade_Acme || exit 1; }
          ;;
        q)
          exit
          ;;
      esac
    fi
  done
}

if [ ${ARG_NUM} == 0 ]; then
  Menu
else
  if [ "${nginx_flag}" = y ]; then Upgrade_Nginx || exit 1; fi
  if [ "${tengine_flag}" = y ]; then Upgrade_Tengine || exit 1; fi
  if [ "${openresty_flag}" = y ]; then Upgrade_OpenResty || exit 1; fi
  if [ "${apache_flag}" = y ]; then Upgrade_Apache || exit 1; fi
  if [ "${tomcat_flag}" = y ]; then Upgrade_Tomcat || exit 1; fi
  if [ "${db_flag}" = y ]; then Upgrade_DB || exit 1; fi
  if [ "${php_flag}" = y ]; then Upgrade_PHP || exit 1; fi
  if [ "${redis_flag}" = y ]; then Upgrade_Redis || exit 1; fi
  if [ "${memcached_flag}" = y ]; then Upgrade_Memcached || exit 1; fi
  if [ "${phpmyadmin_flag}" = y ]; then Upgrade_phpMyAdmin || exit 1; fi
  if [ "${NEW_Script_ver}" = latest ]; then Upgrade_Script || exit 1; fi
  if [ "${NEW_acme_ver}" = latest ] && [ -e ~/.acme.sh/acme.sh ]; then Upgrade_Acme || exit 1; fi
fi
exit 0
