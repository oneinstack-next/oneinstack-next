#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
# BLOG:  https://linuxeye.com

Upgrade_phpMyAdmin() {
  pushd ${current_dir}/src > /dev/null
  [ ! -e "${wwwroot_dir}/default/phpMyAdmin" ] && echo "${CWARNING}phpMyAdmin is not installed on your system! ${CEND}" && exit 1
  OLD_phpmyadmin_ver=`grep Version ${wwwroot_dir}/default/phpMyAdmin/README | awk '{print $2}'`
  Latest_phpmyadmin_ver=${phpmyadmin_ver}
  echo "Current phpMyAdmin Version: ${CMSG}${OLD_phpmyadmin_ver}${CEND}"
  while :; do echo
    [ "${phpmyadmin_flag}" != 'y' ] && read -e -p "Please input upgrade phpMyAdmin Version(default: ${Latest_phpmyadmin_ver}): " NEW_phpmyadmin_ver
    NEW_phpmyadmin_ver=${NEW_phpmyadmin_ver:-${Latest_phpmyadmin_ver}}
    if [ "${NEW_phpmyadmin_ver}" != "${OLD_phpmyadmin_ver}" ]; then
      Download_Artifact "phpMyAdmin-${NEW_phpmyadmin_ver}-all-languages.tar.gz" || exit 1
      if [ -e "phpMyAdmin-${NEW_phpmyadmin_ver}-all-languages.tar.gz" ]; then
        echo "Download [${CMSG}phpMyAdmin-${NEW_phpmyadmin_ver}-all-languages.tar.gz${CEND}] successfully! "
        break
      else
        echo "${CWARNING}phpMyAdmin version does not exist! ${CEND}"
      fi
    else
      echo "${CWARNING}input error! Upgrade phpMyAdmin version is the same as the old version${CEND}"
      exit
    fi
  done

  if [ -e "phpMyAdmin-${NEW_phpmyadmin_ver}-all-languages.tar.gz" ]; then
    echo "[${CMSG}phpMyAdmin-${NEW_phpmyadmin_ver}-all-languages.tar.gz${CEND}] found"
    if [ "${phpmyadmin_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    tar xzf phpMyAdmin-${NEW_phpmyadmin_ver}-all-languages.tar.gz
    rm -rf ${wwwroot_dir}/default/phpMyAdmin
    /bin/mv phpMyAdmin-${NEW_phpmyadmin_ver}-all-languages ${wwwroot_dir}/default/phpMyAdmin
    /bin/cp ${wwwroot_dir}/default/phpMyAdmin/{config.sample.inc.php,config.inc.php}
    mkdir ${wwwroot_dir}/default/phpMyAdmin/{upload,save}
    sed -i "s@UploadDir.*@UploadDir'\] = 'upload';@" ${wwwroot_dir}/default/phpMyAdmin/config.inc.php
    sed -i "s@SaveDir.*@SaveDir'\] = 'save';@" ${wwwroot_dir}/default/phpMyAdmin/config.inc.php
    sed -i "s@host'\].*@host'\] = '127.0.0.1';@" ${wwwroot_dir}/default/phpMyAdmin/config.inc.php
    sed -i "s@blowfish_secret.*;@blowfish_secret\'\] = \'$(cat /dev/urandom | head -1 | base64 | head -c 45)\';@" ${wwwroot_dir}/default/phpMyAdmin/config.inc.php
    chown -R ${run_user}:${run_group} ${wwwroot_dir}/default/phpMyAdmin
    echo "You have ${CMSG}successfully${CEND} upgrade from ${CWARNING}$OLD_phpmyadmin_ver${CEND} to ${CWARNING}$NEW_phpmyadmin_ver${CEND}"
  fi
  popd > /dev/null
}
