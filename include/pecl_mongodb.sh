#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
# BLOG:  https://linuxeye.com
. "$current_dir/include/preflight.sh"

Install_pecl_mongodb() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    pushd ${current_dir}/src > /dev/null
    local mongodb_php_version mongodb_artifact mongodb_directory
    mongodb_php_version=$("$php_install_dir/bin/php-config" --version) || return 1
    mongodb_artifact=$(MongoDB_Artifact_For_PHP "$mongodb_php_version") || return 1
    mongodb_directory=${mongodb_artifact%.tgz}
    Download_Artifact "$mongodb_artifact" || exit 1
    phpExtensionDir=$(${php_install_dir}/bin/php-config --extension-dir)
    if [[ "$(${php_install_dir}/bin/php-config --version | awk -F. '{print $1$2}')" =~ ^5[3-6]$ ]]; then
      tar xzf "$mongodb_artifact" || return 1
      pushd "$mongodb_directory" > /dev/null || return 1
      ${php_install_dir}/bin/phpize
      ./configure --with-php-config=${php_install_dir}/bin/php-config
      make -j ${THREAD} && make install
      popd > /dev/null
      if [ -f "${phpExtensionDir}/mongo.so" ]; then
        echo 'extension=mongo.so' > ${php_install_dir}/etc/php.d/07-mongo.ini
        rm -rf mongo-1.6.16
        echo "${CSUCCESS}PHP mongo module installed successfully! ${CEND}"
      else
        echo "${CFAILURE}PHP mongo module install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
      fi
    else
      tar xzf "$mongodb_artifact" || return 1
      pushd "$mongodb_directory" > /dev/null || return 1
      ${php_install_dir}/bin/phpize
      ./configure --with-php-config=${php_install_dir}/bin/php-config
      make -j ${THREAD} && make install
      popd > /dev/null
      if [ -f "${phpExtensionDir}/mongodb.so" ]; then
        echo 'extension=mongodb.so' > ${php_install_dir}/etc/php.d/07-mongodb.ini
        echo "${CSUCCESS}PHP mongodb module installed successfully! ${CEND}"
        rm -rf -- "$mongodb_directory"
      else
        echo "${CFAILURE}PHP mongodb module install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
      fi
    fi
    popd > /dev/null
  fi
}

Uninstall_pecl_mongodb() {
  if [ -e "${php_install_dir}/etc/php.d/07-mongo.ini" ]; then
    rm -f ${php_install_dir}/etc/php.d/07-mongo.ini
    echo; echo "${CMSG}PHP mongo module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP mongo module does not exist! ${CEND}"
  fi
  if [ -e "${php_install_dir}/etc/php.d/07-mongodb.ini" ]; then
    rm -f ${php_install_dir}/etc/php.d/07-mongodb.ini
    echo; echo "${CMSG}PHP mongodb module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP mongodb module does not exist! ${CEND}"
  fi
}
