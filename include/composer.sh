#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
# BLOG:  https://linuxeye.com

Install_composer() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    if [ -e "/usr/local/bin/composer" ]; then
      echo "${CWARNING}PHP Composer already installed! ${CEND}"
    else
      composer_php_ver=$("${php_install_dir}/bin/php-config" --version) || return 1
      [ "$(printf '%s\n7.2.5\n' "$composer_php_ver" | sort -V | head -1)" = 7.2.5 ] || {
        echo 'Pinned Composer requires PHP >= 7.2.5; legacy Composer needs a separately reviewed artifact' >&2
        return 1
      }
      pushd ${current_dir}/src > /dev/null
      Download_Artifact composer.phar "${current_dir}/src" || return 1
      install -m 755 "${current_dir}/src/composer.phar" /usr/local/bin/composer || return 1
      chmod +x /usr/local/bin/composer
      if [ -e "/usr/local/bin/composer" ]; then
        echo; echo "${CSUCCESS}PHP Composer installed successfully! ${CEND}"
      else
        echo; echo "${CFAILURE}PHP Composer install failed, Please try again! ${CEND}"
      fi
      popd > /dev/null
    fi
  fi
}

Uninstall_composer() {
  if [ -e "/usr/local/bin/composer" ]; then
    rm -f /usr/local/bin/composer
    echo; echo "${CMSG}Composer uninstall completed${CEND}";
  else
    echo; echo "${CWARNING}Composer does not exist! ${CEND}"
  fi
}
