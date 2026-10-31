#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
# BLOG:  https://linuxeye.com
. "$current_dir/include/nginx_build.sh"

Upgrade_Nginx() {
  pushd ${current_dir}/src > /dev/null || exit 1
  [ ! -e "${nginx_install_dir}/sbin/nginx" ] && echo "${CWARNING}Nginx is not installed on your system! ${CEND}" && exit 1
  OLD_nginx_ver_tmp=`${nginx_install_dir}/sbin/nginx -v 2>&1`
  OLD_nginx_ver=${OLD_nginx_ver_tmp##*/}
  Nginx_Read_Build_Arguments "$nginx_install_dir" || exit 1
  Latest_nginx_ver=${nginx_ver}
  echo
  echo "Current Nginx Version: ${CMSG}${OLD_nginx_ver}${CEND}"
  while :; do echo
    [ "${nginx_flag}" != 'y' ] && read -e -p "Please input upgrade Nginx Version(default: ${Latest_nginx_ver}): " NEW_nginx_ver
    NEW_nginx_ver=${NEW_nginx_ver:-${Latest_nginx_ver}}
    if [ "${NEW_nginx_ver}" != "${OLD_nginx_ver}" ]; then
      Download_Artifact "nginx-${NEW_nginx_ver}.tar.gz" || exit 1
      if [ -e "nginx-${NEW_nginx_ver}.tar.gz" ]; then
        Download_Artifact "openssl-${openssl_ver}.tar.gz" || exit 1
        Download_Artifact "pcre-${pcre_ver}.tar.gz" || exit 1
        tar xzf openssl-${openssl_ver}.tar.gz || exit 1
        tar xzf pcre-${pcre_ver}.tar.gz || exit 1
        echo "Download [${CMSG}nginx-${NEW_nginx_ver}.tar.gz${CEND}] successfully! "
        break
      else
        echo "${CWARNING}Nginx version does not exist! ${CEND}"
      fi
    else
      echo "${CWARNING}input error! Upgrade Nginx version is the same as the old version${CEND}"
      exit
    fi
  done

  if [ -e "nginx-${NEW_nginx_ver}.tar.gz" ]; then
    echo "[${CMSG}nginx-${NEW_nginx_ver}.tar.gz${CEND}] found"
    if [ "${nginx_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    tar xzf nginx-${NEW_nginx_ver}.tar.gz || exit 1
    pushd nginx-${NEW_nginx_ver} || exit 1
    make clean
    sed -i 's@CFLAGS="$CFLAGS -g"@#CFLAGS="$CFLAGS -g"@' auto/cc/gcc # close debug
    export LUAJIT_LIB=/usr/local/lib
    export LUAJIT_INC=/usr/local/include/luajit-2.1
    ./configure "${nginx_build_args[@]}" || exit 1
    make -j ${THREAD} || exit 1
    if [ -f "objs/nginx" ]; then
      Nginx_Upgrade_Binary "objs/nginx" "${nginx_install_dir}" || exit 1
      popd > /dev/null
      echo "You have ${CMSG}successfully${CEND} upgrade from ${CWARNING}${OLD_nginx_ver}${CEND} to ${CWARNING}${NEW_nginx_ver}${CEND}"
      rm -rf nginx-${NEW_nginx_ver}
    else
      echo "${CFAILURE}Upgrade Nginx failed! ${CEND}"
    fi
  fi
  popd > /dev/null
}

Upgrade_Tengine() {
  pushd ${current_dir}/src > /dev/null || exit 1
  [ ! -e "${tengine_install_dir}/sbin/nginx" ] && echo "${CWARNING}Tengine is not installed on your system! ${CEND}" && exit 1
  OLD_tengine_ver_tmp=`${tengine_install_dir}/sbin/nginx -v 2>&1`
  OLD_tengine_ver="`echo ${OLD_tengine_ver_tmp#*/} | awk '{print $1}'`"
  Nginx_Read_Build_Arguments "$tengine_install_dir" || exit 1
  Latest_tengine_ver=${tengine_ver}
  echo
  echo "Current Tengine Version: ${CMSG}${OLD_tengine_ver}${CEND}"
  while :; do echo
    [ "${tengine_flag}" != 'y' ] && read -e -p "Please input upgrade Tengine Version(default: ${Latest_tengine_ver}): " NEW_tengine_ver
    NEW_tengine_ver=${NEW_tengine_ver:-${Latest_tengine_ver}}
    if [ "${NEW_tengine_ver}" != "${OLD_tengine_ver}" ]; then
      Download_Artifact "tengine-${NEW_tengine_ver}.tar.gz" || exit 1
      if [ -e "tengine-${NEW_tengine_ver}.tar.gz" ]; then
        Download_Artifact "openssl-${openssl_ver}.tar.gz" || exit 1
        Download_Artifact "pcre-${pcre_ver}.tar.gz" || exit 1
        tar xzf openssl-${openssl_ver}.tar.gz || exit 1
        tar xzf pcre-${pcre_ver}.tar.gz || exit 1
        echo "Download [${CMSG}tengine-${NEW_tengine_ver}.tar.gz${CEND}] successfully! "
        break
      else
        echo "${CWARNING}Tengine version does not exist! ${CEND}"
      fi
    else
      echo "${CWARNING}input error! Upgrade Tengine version is the same as the old version${CEND}"
      exit
    fi
  done

  if [ -e "tengine-${NEW_tengine_ver}.tar.gz" ]; then
    echo "[${CMSG}tengine-${NEW_tengine_ver}.tar.gz${CEND}] found"
    if [ "${tengine_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    tar xzf tengine-${NEW_tengine_ver}.tar.gz || exit 1
    pushd tengine-${NEW_tengine_ver} || exit 1
    make clean
    export LUAJIT_LIB=/usr/local/lib
    export LUAJIT_INC=/usr/local/include/luajit-2.1
    ./configure "${nginx_build_args[@]}" || exit 1
    make || exit 1
    if [ -f "objs/nginx" ]; then
      Nginx_Upgrade_Binary "objs/nginx" "${tengine_install_dir}" || exit 1
      popd > /dev/null
      echo "You have ${CMSG}successfully${CEND} upgrade from ${CWARNING}$OLD_tengine_ver${CEND} to ${CWARNING}${NEW_tengine_ver}${CEND}"
      rm -rf tengine-${NEW_tengine_ver}
    else
      echo "${CFAILURE}Upgrade Tengine failed! ${CEND}"
    fi
  fi
  popd > /dev/null
}

Upgrade_OpenResty() {
  pushd ${current_dir}/src > /dev/null || exit 1
  [ ! -e "${openresty_install_dir}/nginx/sbin/nginx" ] && echo "${CWARNING}OpenResty is not installed on your system! ${CEND}" && exit 1
  OLD_openresy_ver_tmp=`${openresty_install_dir}/nginx/sbin/nginx -v 2>&1`
  OLD_openresy_ver="`echo ${OLD_openresy_ver_tmp#*/} | awk '{print $1}'`"
  Latest_openresy_ver=${openresty_ver}
  echo
  echo "Current OpenResty Version: ${CMSG}${OLD_openresy_ver}${CEND}"
  while :; do echo
    [ "${openresty_flag}" != 'y' ] && read -e -p "Please input upgrade OpenResty Version(default: ${Latest_openresy_ver}): " NEW_openresy_ver
    NEW_openresy_ver=${NEW_openresy_ver:-${Latest_openresy_ver}}
    if [ "${NEW_openresy_ver}" != "${OLD_openresy_ver}" ]; then
      Download_Artifact "openresty-${NEW_openresy_ver}.tar.gz" || exit 1
      if [ -e "openresty-${NEW_openresy_ver}.tar.gz" ]; then
        Download_Artifact "openssl-${openssl_ver}.tar.gz" || exit 1
        Download_Artifact "pcre-${pcre_ver}.tar.gz" || exit 1
        tar xzf openssl-${openssl_ver}.tar.gz || exit 1
        tar xzf pcre-${pcre_ver}.tar.gz || exit 1
        echo "Download [${CMSG}openresty-${NEW_openresy_ver}.tar.gz${CEND}] successfully! "
        break
      else
        echo "${CWARNING}OpenResty version does not exist! ${CEND}"
      fi
    else
      echo "${CWARNING}input error! Upgrade OpenResty version is the same as the old version${CEND}"
      exit
    fi
  done

  if [ -e "openresty-${NEW_openresy_ver}.tar.gz" ]; then
    echo "[${CMSG}openresty-${NEW_openresy_ver}.tar.gz${CEND}] found"
    if [ "${openresty_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    tar xzf openresty-${NEW_openresy_ver}.tar.gz || exit 1
    pushd openresty-${NEW_openresy_ver} || exit 1
    make clean
    sed -i 's@CFLAGS="$CFLAGS -g"@#CFLAGS="$CFLAGS -g"@' bundle/nginx-${NEW_openresy_ver%.*}/auto/cc/gcc # close debug
    ./configure --prefix=${openresty_install_dir} --user=${run_user} --group=${run_user} --with-http_stub_status_module --with-http_sub_module --with-http_v2_module --with-http_ssl_module --with-http_gzip_static_module --with-http_realip_module --with-http_flv_module --with-http_mp4_module --with-openssl=../openssl-${openssl_ver} --with-pcre=../pcre-${pcre_ver} --with-pcre-jit --with-ld-opt='-ljemalloc -Wl,-u,pcre_version' ${nginx_modules_options} || exit 1
    make -j ${THREAD} || exit 1
    if [ -f "build/nginx-${NEW_openresy_ver%.*}/objs/nginx" ]; then
      Nginx_Upgrade_Binary "build/nginx-${NEW_openresy_ver%.*}/objs/nginx" "${openresty_install_dir}/nginx" || exit 1
      popd > /dev/null
      echo "You have ${CMSG}successfully${CEND} upgrade from ${CWARNING}${OLD_openresy_ver}${CEND} to ${CWARNING}${NEW_openresy_ver}${CEND}"
      rm -rf openresty-${NEW_openresy_ver}
    else
      echo "${CFAILURE}Upgrade OpenResty failed! ${CEND}"
    fi
  fi
  popd > /dev/null
}

Upgrade_Apache() {
  pushd ${current_dir}/src > /dev/null || exit 1
  [ ! -e "${apache_install_dir}/bin/httpd" ] && echo "${CWARNING}Apache is not installed on your system! ${CEND}" && exit 1
  OLD_apache_ver="`${apache_install_dir}/bin/httpd -v | grep version | awk -F'/| ' '{print $4}'`"
  Latest_apache_ver=${apache_ver}
  echo
  echo "Current Apache Version: ${CMSG}${OLD_apache_ver}${CEND}"
  while :; do echo
    [ "${apache_flag}" != 'y' ] && read -e -p "Please input upgrade Apache Version(Default: ${Latest_apache_ver}): " NEW_apache_ver
    NEW_apache_ver=${NEW_apache_ver:-${Latest_apache_ver}}
    if [ `echo ${NEW_apache_ver} | awk -F. '{print $1$2}'` == "24" ]; then
      if [ "${NEW_apache_ver}" != "${OLD_apache_ver}" ]; then
        Download_Artifact "apr-${apr_ver}.tar.gz" || exit 1
        Download_Artifact "apr-util-${apr_util_ver}.tar.gz" || exit 1
        Download_Artifact "httpd-${NEW_apache_ver}.tar.gz" || exit 1
        if [ -e "httpd-${NEW_apache_ver}.tar.gz" ]; then
          echo "Download [${CMSG}apache-${NEW_apache_ver}.tar.gz${CEND}] successfully! "
          break
        else
          echo "${CWARNING}Apache version does not exist! ${CEND}"
        fi
      else
        echo "${CWARNING}input error! Upgrade Apache version is the same as the old version${CEND}"
        exit
      fi
    else
      echo "${CWARNING}input error! ${CEND}Please only input '${CMSG}${OLD_apache_ver%.*}.xx${CEND}'"
      [ "${apache_flag}" == 'y' ] && exit
    fi
  done

  if [ -e "httpd-${NEW_apache_ver}.tar.gz" ]; then
    echo "[${CMSG}httpd-${NEW_apache_ver}.tar.gz${CEND}] found"
    if [ "${apache_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    # install apr
    if [ ! -e "${apr_install_dir}/bin/apr-1-config" ]; then
      tar xzf apr-${apr_ver}.tar.gz || exit 1
      pushd apr-${apr_ver} > /dev/null || exit 1
      ./configure --prefix=${apr_install_dir} || exit 1
      make -j ${THREAD} && make install || exit 1
      popd > /dev/null
      rm -rf apr-${apr_ver}
    fi
    # install apr-util
    if [ ! -e "${apr_install_dir}/bin/apu-1-config" ]; then
      tar xzf apr-util-${apr_util_ver}.tar.gz || exit 1
      pushd apr-util-${apr_util_ver} > /dev/null || exit 1
      ./configure --prefix=${apr_install_dir} --with-apr=${apr_install_dir} || exit 1
      make -j ${THREAD} && make install || exit 1
      popd > /dev/null
      rm -rf apr-util-${apr_util_ver}
    fi
    tar xzf httpd-${NEW_apache_ver}.tar.gz || exit 1
    pushd httpd-${NEW_apache_ver} || exit 1
    make clean
    LDFLAGS=-ldl ./configure --prefix=${apache_install_dir} --enable-mpms-shared=all --with-pcre --with-apr=${apr_install_dir} --with-apr-util=${apr_install_dir} --enable-headers --enable-mime-magic --enable-deflate --enable-proxy --enable-so --enable-dav --enable-rewrite --enable-remoteip --enable-expires --enable-static-support --enable-suexec --enable-mods-shared=most --enable-nonportable-atomics=yes --enable-ssl --with-ssl=${openssl_install_dir} --enable-http2 --with-nghttp2=/usr/local
    make -j ${THREAD} || exit 1
    if [ -e 'httpd' ]; then
      [[ -d ${apache_install_dir}_bak && -d ${apache_install_dir} ]] && rm -rf ${apache_install_dir}_bak
      service httpd stop
      /bin/cp -R ${apache_install_dir}{,_bak}
      make install && unset LDFLAGS
      service httpd start
      popd > /dev/null
      echo "You have ${CMSG}successfully${CEND} upgrade from ${CWARNING}${OLD_apache_ver}${CEND} to ${CWARNING}${NEW_apache_ver}${CEND}"
      rm -rf httpd-${NEW_apache_ver}
    else
      echo "${CFAILURE}Upgrade Apache failed! ${CEND}"
    fi
  fi
  popd > /dev/null
}

Upgrade_Tomcat() {
  pushd ${current_dir}/src > /dev/null || exit 1
  [ ! -e "${tomcat_install_dir}/conf/server.xml" ] && echo "${CWARNING}Tomcat is not installed on your system! ${CEND}" && exit 1
  OLD_tomcat_ver="`${tomcat_install_dir}/bin/version.sh | awk '/Server number/{print $3}' | awk -F. '{print $1"."$2"."$3}'`"
  Tomcat_flag="`echo ${OLD_tomcat_ver} | awk -F. '{print $1}'`"
  Latest_tomcat_ver=${tomcat_ver}
  echo
  echo "Current Tomcat Version: ${CMSG}${OLD_tomcat_ver}${CEND}"
  while :; do echo
    [ "${tomcat_flag}" != 'y' ] && read -e -p "Please input upgrade Tomcat Version(Default: ${Latest_tomcat_ver}): " NEW_tomcat_ver
    NEW_tomcat_ver=${NEW_tomcat_ver:-${Latest_tomcat_ver}}
    if [ "`echo ${NEW_tomcat_ver} | awk -F. '{print $1}'`" == "${Tomcat_flag}" ]; then
      rm -f catalina-jmx-remote.jar
      echo "Download tomcat-${NEW_tomcat_ver}..."
      Download_Artifact "apache-tomcat-${NEW_tomcat_ver}.tar.gz" || exit 1
      Download_Artifact "apache-tomcat-${NEW_tomcat_ver}.tar.gz" || exit 1
      if [ -e "${tomcat_install_dir}/lib/catalina-jmx-remote.jar" ]; then
        Download_Artifact "catalina-jmx-remote.jar" || exit 1
        Download_Artifact "catalina-jmx-remote.jar" || exit 1
      fi
      if [ -e "apache-tomcat-${NEW_tomcat_ver}.tar.gz" ]; then
        echo "Download [${CMSG}apache-tomcat-${NEW_tomcat_ver}.tar.gz${CEND}] successfully! "
        break
      else
        echo "${CWARNING}Tomcat version does not exist! ${CEND}"
      fi
    else
      echo "${CWARNING}input error! ${CEND}Please only input '${CMSG}${Tomcat_flag}.xx${CEND}'"
    fi
  done

  if [ -e "apache-tomcat-${NEW_tomcat_ver}.tar.gz" ]; then
    echo "[${CMSG}apache-tomcat-${NEW_tomcat_ver}.tar.gz${CEND}] found"
    if [ "${tomcat_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    tar xzf apache-tomcat-${NEW_tomcat_ver}.tar.gz || exit 1
    /bin/mv apache-tomcat-${NEW_tomcat_ver}/conf/server.xml{,_bk}
    /bin/cp ${tomcat_install_dir}/conf/{server.xml,jmxremote.access,jmxremote.password,tomcat-users.xml} apache-tomcat-${NEW_tomcat_ver}/conf/
    [ -e "${tomcat_install_dir}/lib/catalina-jmx-remote.jar" ] && /bin/cp catalina-jmx-remote.jar apache-tomcat-${NEW_tomcat_ver}/lib
    /bin/cp ${tomcat_install_dir}/bin/setenv.sh apache-tomcat-${NEW_tomcat_ver}/bin/
    /bin/cp -R ${tomcat_install_dir}/conf/vhost apache-tomcat-${NEW_tomcat_ver}/conf/
    chmod +x apache-tomcat-${NEW_tomcat_ver}/bin/*.sh
    [[ -d ${tomcat_install_dir}_bak && -d ${tomcat_install_dir} ]] && rm -rf ${tomcat_install_dir}._bak
    service tomcat stop
    /bin/mv ${tomcat_install_dir}{,_bak}
    /bin/mv apache-tomcat-${NEW_tomcat_ver} ${tomcat_install_dir} && chown -R ${run_user}:${run_group} ${tomcat_install_dir}
    if [ -e "${tomcat_install_dir}/conf/server.xml" ]; then
      service tomcat start
      echo "You have ${CMSG}successfully${CEND} upgrade from ${CWARNING}${OLD_tomcat_ver}${CEND} to ${CWARNING}${NEW_tomcat_ver}${CEND}"
    else
      echo "${CFAILURE}Upgrade Tomcat failed! ${CEND}"
    fi
  fi
  popd > /dev/null
}
