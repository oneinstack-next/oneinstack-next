#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
# BLOG:  https://linuxeye.com

Upgrade_Memcached() {
  pushd ${current_dir}/src > /dev/null
  [ ! -e "${memcached_install_dir}/bin/memcached" ] && echo "${CWARNING}Memcached is not installed on your system! ${CEND}" && exit 1
  OLD_memcached_ver=`${memcached_install_dir}/bin/memcached -V | awk '{print $2}'`
  Latest_memcached_ver=${memcached_ver}
  echo "Current Memcached Version: ${CMSG}${OLD_memcached_ver}${CEND}"
  while :; do echo
    [ "${memcached_flag}" != 'y' ] && read -e -p "Please input upgrade Memcached Version(default: ${Latest_memcached_ver}): " NEW_memcached_ver
    NEW_memcached_ver=${NEW_memcached_ver:-${Latest_memcached_ver}}
    if [ "${NEW_memcached_ver}" != "${OLD_memcached_ver}" ]; then
      Download_Artifact "memcached-${NEW_memcached_ver}.tar.gz" || exit 1
      if [ -e "memcached-${NEW_memcached_ver}.tar.gz" ]; then
        echo "Download [${CMSG}memcached-${NEW_memcached_ver}.tar.gz${CEND}] successfully! "
        break
      else
        echo "${CWARNING}Memcached version does not exist! ${CEND}"
      fi
    else
      echo "${CWARNING}input error! Upgrade Memcached version is the same as the old version${CEND}"
      exit
    fi
  done

  if [ -e "memcached-${NEW_memcached_ver}.tar.gz" ]; then
    echo "[${CMSG}memcached-${NEW_memcached_ver}.tar.gz${CEND}] found"
    if [ "${memcached_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    tar xzf memcached-${NEW_memcached_ver}.tar.gz
    pushd memcached-${NEW_memcached_ver}
    make clean
    ./configure --prefix=${memcached_install_dir}
    make -j ${THREAD}

    if [ -e "memcached" ]; then
      echo "Restarting Memcached..."
      service memcached stop
      make install
      service memcached start
      popd > /dev/null
      echo "You have ${CMSG}successfully${CEND} upgrade from ${CWARNING}${OLD_memcached_ver}${CEND} to ${CWARNING}${NEW_memcached_ver}${CEND}"
      rm -rf memcached-${NEW_memcached_ver}
    else
      echo "${CFAILURE}Upgrade Memcached failed! ${CEND}"
    fi
  fi
  popd > /dev/null
}
