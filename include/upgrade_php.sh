#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
# BLOG:  https://linuxeye.com

Upgrade_PHP() {
  pushd ${current_dir}/src > /dev/null
  [ ! -e "${php_install_dir}" ] && echo "${CWARNING}PHP is not installed on your system! ${CEND}" && exit 1
  OLD_php_ver=`${php_install_dir}/bin/php-config --version`
  php_version_key=php${OLD_php_ver%.*}_ver
  php_version_key=${php_version_key//./}
  Latest_php_ver=${!php_version_key:-$OLD_php_ver}
  echo
  echo "Current PHP Version: ${CMSG}$OLD_php_ver${CEND}"
  while :; do echo
    [ "${php_flag}" != 'y' ] && read -e -p "Please input upgrade PHP Version(Default: $Latest_php_ver): " NEW_php_ver
    NEW_php_ver=${NEW_php_ver:-${Latest_php_ver}}
    if [ "${NEW_php_ver%.*}" == "${OLD_php_ver%.*}" ]; then
      Download_Artifact "php-${NEW_php_ver}.tar.gz" || exit 1
      if [ -e "php-${NEW_php_ver}.tar.gz" ]; then
        echo "Download [${CMSG}php-${NEW_php_ver}.tar.gz${CEND}] successfully! "
      else
        echo "${CWARNING}PHP version does not exist! ${CEND}"
      fi
      break
    else
      echo "${CWARNING}input error! ${CEND}Please only input '${CMSG}${OLD_php_ver%.*}.xx${CEND}'"
      [ "${php_flag}" == 'y' ] && exit
    fi
  done

  if [ -e "php-${NEW_php_ver}.tar.gz" ]; then
    echo "[${CMSG}php-${NEW_php_ver}.tar.gz${CEND}] found"
    if [ "${php_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    if [[ ${NEW_php_ver%.*} =~ ^5\.[3-5]$ ]]; then
      Download_Artifact "fpm-race-condition.patch" || exit 1
    fi
    tar xzf "php-${NEW_php_ver}.tar.gz" || return 1
    if [[ ${NEW_php_ver%.*} =~ ^5\.[3-5]$ ]]; then
      patch -d "php-${NEW_php_ver}" -p0 < fpm-race-condition.patch || return 1
    fi
    pushd "php-${NEW_php_ver}" || return 1
    if [[ "${OLD_php_ver%.*}" =~ ^7.[1-4]$|^8.[0-1]$ ]] && [ -e ext/openssl/openssl.c ] && ! grep -Eqi '^#ifdef RSA_SSLV23_PADDING' ext/openssl/openssl.c; then
      sed -i '/OPENSSL_SSLV23_PADDING/i#ifdef RSA_SSLV23_PADDING' ext/openssl/openssl.c
      sed -i '/OPENSSL_SSLV23_PADDING/a#endif' ext/openssl/openssl.c
    fi
    make clean
    export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig/:$PKG_CONFIG_PATH
    ${php_install_dir}/bin/php -i |grep 'Configure Command' | awk -F'=>' '{print $2}' | bash
    make ZEND_EXTRA_LIBS='-liconv' -j ${THREAD}
    if [ -e "${apache_install_dir}/bin/httpd" ]; then
      echo "Stoping apache..."
      service httpd stop
      make install
      echo "Starting apache..."
      service httpd start
    else
      echo "Stoping php-fpm..."
      service php-fpm stop
      make install
      echo "Starting php-fpm..."
      service php-fpm start
    fi
    popd > /dev/null
    echo "You have ${CMSG}successfully${CEND} upgrade from ${CWARNING}$OLD_php_ver${CEND} to ${CWARNING}${NEW_php_ver}${CEND}"
    rm -rf php-${NEW_php_ver}
  fi
  popd > /dev/null
}
