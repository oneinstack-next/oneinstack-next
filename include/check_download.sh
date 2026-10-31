#!/bin/bash
# Author:  Alpha Eva <kaneawk AT gmail.com>

checkDownload() {
  pushd ${current_dir}/src > /dev/null
  # icu
  if ! command -v icu-config >/dev/null 2>&1 || icu-config --version | grep '^3.' || [ "${Ubuntu_ver}" == "20" ]; then
    echo "Download icu..."
    Download_Artifact "icu4c-${icu4c_ver}-src.tgz" || exit 1
  fi

  # General system utils
  if [ "${with_old_openssl_flag}" == 'y' ]; then
    echo "Download openSSL..."
    Download_Artifact "openssl-1.0.2u.tar.gz" || exit 1
    echo "Download cacert.pem..."
    Download_Artifact "cacert.pem" || exit 1
  fi

  # openssl
  if [[ ${nginx_option} =~ ^[1-3]$ ]]; then
      echo "Download openSSL..."
      Download_Artifact "openssl-${openssl_ver}.tar.gz" || exit 1
  fi

  # jemalloc
  if [[ ${nginx_option} =~ ^[1-3]$ ]] || [[ "${db_option}" =~ ^[1-9]$|^1[0-2]$ ]]; then
    echo "Download jemalloc..."
    Download_Artifact "jemalloc-${jemalloc_ver}.tar.bz2" || exit 1
  fi

  # nginx/tengine/openresty
  case "${nginx_option}" in
    1)
      echo "Download nginx..."
      Download_Artifact "nginx-${nginx_ver}.tar.gz" || exit 1
      ;;
    2)
      echo "Download tengine..."
      Download_Artifact "tengine-${tengine_ver}.tar.gz" || exit 1
      ;;
    3)
      echo "Download openresty..."
      Download_Artifact "openresty-${openresty_ver}.tar.gz" || exit 1
      ;;
  esac

  # pcre
  if [[ "${nginx_option}" =~ ^[1-3]$ ]] || [ "${apache_flag}" == 'y' ]; then
    echo "Download pcre..."
    Download_Artifact "pcre-${pcre_ver}.tar.gz" || exit 1
  fi

  # apache
  if [ "${apache_flag}" == 'y' ]; then
    echo "Download apache 2.4..."
    Download_Artifact "httpd-${apache_ver}.tar.gz" || exit 1
    Download_Artifact "apr-${apr_ver}.tar.gz" || exit 1
    Download_Artifact "apr-util-${apr_util_ver}.tar.gz" || exit 1
    Download_Artifact "nghttp2-${nghttp2_ver}.tar.gz" || exit 1
  fi

  # tomcat
  case "${tomcat_option}" in
    1)
      echo "Download tomcat 10..."
      Download_Artifact "apache-tomcat-${tomcat10_ver}.tar.gz" || exit 1
      ;;
    2)
      echo "Download tomcat 9..."
      Download_Artifact "apache-tomcat-${tomcat9_ver}.tar.gz" || exit 1
      ;;
    3)
      echo "Download tomcat 8..."
      Download_Artifact "apache-tomcat-${tomcat8_ver}.tar.gz" || exit 1
      ;;
    4)
      echo "Download tomcat 7..."
      Download_Artifact "apache-tomcat-${tomcat7_ver}.tar.gz" || exit 1
      Download_Artifact "catalina-jmx-remote.jar" || exit 1
      ;;
  esac

  # jdk apr
  if [[ "${jdk_option}"  =~ ^[1-3]$ ]]; then
    echo "Download apr..."
    Download_Artifact "apr-${apr_ver}.tar.gz" || exit 1
  fi

  if [[ "${db_option}" =~ ^[1-9]$|^1[0-4]$ ]]; then
    if [[ "${db_option}" =~ ^[1,2,5,6,7,9]$|^10$ ]] && [ "${dbinstallmethod}" == "2" ]; then
      echo "Download boost..."
      boostVersion2=$(echo ${boost_ver} | awk -F. '{print $1"_"$2"_"$3}')
      Download_Artifact "boost_${boostVersion2}.tar.gz" || exit 1
    fi

    case "${db_option}" in
      1)
        # MySQL 8.4
        if [ "${dbinstallmethod}" == '1' ]; then
          echo "Download MySQL 8.4 binary package..."
          FILE_NAME=mysql-${mysql84_ver}-linux-glibc2.28-x86_64.tar.xz
        elif [ "${dbinstallmethod}" == '2' ]; then
          echo "Download MySQL 8.4 source package..."
          FILE_NAME=mysql-${mysql84_ver}.tar.gz
        fi
        # start download
        Download_Artifact "${FILE_NAME}" || exit 1
        ;;
      2)
        # MySQL 8.0
        if [ "${dbinstallmethod}" == '1' ]; then
          echo "Download MySQL 8.0 binary package..."
          FILE_NAME=mysql-${mysql80_ver}-linux-glibc2.28-x86_64.tar.xz
        elif [ "${dbinstallmethod}" == '2' ]; then
          echo "Download MySQL 8.0 source package..."
          FILE_NAME=mysql-${mysql80_ver}.tar.gz
        fi
        # start download
        Download_Artifact "${FILE_NAME}" || exit 1
        ;;
      3)
        # MySQL 5.7
        if [ "${dbinstallmethod}" == '1' ]; then
          echo "Download MySQL 5.7 binary package..."
          FILE_NAME=mysql-${mysql57_ver}-linux-glibc2.12-x86_64.tar.gz
        elif [ "${dbinstallmethod}" == '2' ]; then
          echo "Download MySQL 5.7 source package..."
          FILE_NAME=mysql-${mysql57_ver}.tar.gz
        fi
        # start download
        Download_Artifact "${FILE_NAME}" || exit 1
        ;;
      4)
        # MySQL 5.5
        if [ "${dbinstallmethod}" == '1' ]; then
          echo "Download MySQL 5.5 binary package..."
          FILE_NAME=mysql-${mysql55_ver}-linux-glibc2.12-x86_64.tar.gz
        elif [ "${dbinstallmethod}" == '2' ]; then
          echo "Download MySQL 5.5 source package..."
          FILE_NAME=mysql-${mysql55_ver}.tar.gz
          Download_Artifact "mysql-5.5-fix-arm-client_plugin.patch" || exit 1
        fi
        # start download
        Download_Artifact "${FILE_NAME}" || exit 1
        ;;
      [5-8])
	case "${db_option}" in
          5)
            mariadb_ver=${mariadb118_ver}
	    ;;
          6)
            mariadb_ver=${mariadb114_ver}
	    ;;
          7)
            mariadb_ver=${mariadb1011_ver}
	    ;;
          8)
            mariadb_ver=${mariadb55_ver}
	    ;;
        esac

        if [ "${dbinstallmethod}" == '1' ]; then
          FILE_NAME=mariadb-${mariadb_ver}-linux-systemd-x86_64.tar.gz
        elif [ "${dbinstallmethod}" == '2' ]; then
          FILE_NAME=mariadb-${mariadb_ver}.tar.gz
        fi



        echo "Download MariaDB ${FILE_NAME} package..."
        Download_Artifact "${FILE_NAME}" || exit 1
        ;;
      9)
        # Percona 8.4
        if [ "${dbinstallmethod}" == '1' ]; then
          echo "Download Percona 8.4 binary package..."
          FILE_NAME=Percona-Server-${percona84_ver}-Linux.x86_64.glibc2.35.tar.gz
        elif [ "${dbinstallmethod}" == '2' ]; then
          echo "Download Percona 8.4 source package..."
          FILE_NAME=percona-server-${percona84_ver}.tar.gz
        fi
        # start download
        Download_Artifact "${FILE_NAME}" || exit 1
        ;;
      10)
        # Percona 8.0
        if [ "${dbinstallmethod}" == '1' ]; then
          echo "Download Percona 8.0 binary package..."
          FILE_NAME=Percona-Server-${percona80_ver}-Linux.x86_64.glibc2.35.tar.gz
        elif [ "${dbinstallmethod}" == '2' ]; then
          echo "Download Percona 8.0 source package..."
          FILE_NAME=percona-server-${percona80_ver}.tar.gz
        fi
        # start download
        Download_Artifact "${FILE_NAME}" || exit 1
        ;;
      11)
        # Precona 5.7
        if [ "${dbinstallmethod}" == '1' ]; then
          echo "Download Percona 5.7 binary package..."
          FILE_NAME=Percona-Server-${percona57_ver}-Linux.x86_64.glibc2.35.tar.gz
        elif [ "${dbinstallmethod}" == '2' ]; then
          echo "Download Percona 5.7 source package..."
          FILE_NAME=percona-server-${percona57_ver}.tar.gz
        fi
        # start download
        Download_Artifact "${FILE_NAME}" || exit 1
        ;;
      12)
        # Percona 5.5
        if [ "${dbinstallmethod}" == '1' ]; then
          echo "Download Percona 5.5 binary package..."
          perconaVerStr1=$(echo ${percona55_ver} | sed "s@-@-rel@")
          FILE_NAME=Percona-Server-${perconaVerStr1}-Linux.x86_64.${sslLibVer}.tar.gz
        elif [ "${dbinstallmethod}" == '2' ]; then
          echo "Download Percona 5.5 source package..."
          FILE_NAME=percona-server-${percona55_ver}.tar.gz
        fi
        # start download
        Download_Artifact "${FILE_NAME}" || exit 1
        ;;
      13)
        FILE_NAME=postgresql-${pgsql_ver}.tar.gz
        Download_Artifact "${FILE_NAME}" || exit 1
        ;;
      14)
        # MongoDB
        echo "Download MongoDB binary package..."
        FILE_NAME=mongodb-linux-x86_64-${mongodb_ver}.tgz
        Download_Artifact "${FILE_NAME}" || exit 1
        ;;
    esac
  fi

  # PHP
  if [[ "${php_option}" =~ ^[1-9]$|^1[0-5]$ ]] || [[ "${mphp_ver}" =~ ^5[3-6]$|^7[0-4]$|^8[0-5]$ ]]; then
    echo "PHP common..."
    Download_Artifact "libiconv-${libiconv_ver}.tar.gz" || exit 1
    Download_Artifact "curl-${curl_ver}.tar.gz" || exit 1
    Download_Artifact "mhash-${mhash_ver}.tar.gz" || exit 1
    Download_Artifact "libmcrypt-${libmcrypt_ver}.tar.gz" || exit 1
    Download_Artifact "mcrypt-${mcrypt_ver}.tar.gz" || exit 1
    Download_Artifact "freetype-${freetype_ver}.tar.gz" || exit 1
  fi

  if [ "${php_option}" == '1' ] || [ "${mphp_ver}" == '53' ]; then
    Download_Artifact "debian_patches_disable_SSLv2_for_openssl_1_0_0.patch" || exit 1
    Download_Artifact "php5.3patch" || exit 1
    Download_Artifact "php-${php53_ver}.tar.gz" || exit 1
    Download_Artifact "fpm-race-condition.patch" || exit 1
  elif [ "${php_option}" == '2' ] || [ "${mphp_ver}" == '54' ]; then
    Download_Artifact "php-${php54_ver}.tar.gz" || exit 1
    Download_Artifact "fpm-race-condition.patch" || exit 1
  elif [ "${php_option}" == '3' ] || [ "${mphp_ver}" == '55' ]; then
    Download_Artifact "php-${php55_ver}.tar.gz" || exit 1
    Download_Artifact "fpm-race-condition.patch" || exit 1
  elif [ "${php_option}" == '4' ] || [ "${mphp_ver}" == '56' ]; then
    Download_Artifact "php-${php56_ver}.tar.gz" || exit 1
  elif [ "${php_option}" == '5' ] || [ "${mphp_ver}" == '70' ]; then
    Download_Artifact "php-${php70_ver}.tar.gz" || exit 1
  elif [ "${php_option}" == '6' ] || [ "${mphp_ver}" == '71' ]; then
    Download_Artifact "php-${php71_ver}.tar.gz" || exit 1
  elif [ "${php_option}" == '7' ] || [ "${mphp_ver}" == '72' ]; then
    Download_Artifact "php-${php72_ver}.tar.gz" || exit 1
    Download_Artifact "argon2-${argon2_ver}.tar.gz" || exit 1
    Download_Artifact "libsodium-${libsodium_ver}.tar.gz" || exit 1
  elif [ "${php_option}" == '8' ] || [ "${mphp_ver}" == '73' ]; then
    Download_Artifact "php-${php73_ver}.tar.gz" || exit 1
    Download_Artifact "argon2-${argon2_ver}.tar.gz" || exit 1
    Download_Artifact "libsodium-${libsodium_ver}.tar.gz" || exit 1
  elif [ "${php_option}" == '9' ] || [ "${mphp_ver}" == '74' ]; then
    Download_Artifact "php-${php74_ver}.tar.gz" || exit 1
    Download_Artifact "argon2-${argon2_ver}.tar.gz" || exit 1
    Download_Artifact "libsodium-${libsodium_ver}.tar.gz" || exit 1
    Download_Artifact "libzip-${libzip_ver}.tar.gz" || exit 1
  elif [ "${php_option}" == '10' ] || [ "${mphp_ver}" == '80' ]; then
    Download_Artifact "php-${php80_ver}.tar.gz" || exit 1
    Download_Artifact "argon2-${argon2_ver}.tar.gz" || exit 1
    Download_Artifact "libsodium-${libsodium_ver}.tar.gz" || exit 1
    Download_Artifact "libzip-${libzip_ver}.tar.gz" || exit 1
  elif [ "${php_option}" == '11' ] || [ "${mphp_ver}" == '81' ]; then
    Download_Artifact "php-${php81_ver}.tar.gz" || exit 1
    Download_Artifact "argon2-${argon2_ver}.tar.gz" || exit 1
    Download_Artifact "libsodium-${libsodium_ver}.tar.gz" || exit 1
    Download_Artifact "libzip-${libzip_ver}.tar.gz" || exit 1
  elif [ "${php_option}" == '12' ] || [ "${mphp_ver}" == '82' ]; then
    Download_Artifact "php-${php82_ver}.tar.gz" || exit 1
    Download_Artifact "argon2-${argon2_ver}.tar.gz" || exit 1
    Download_Artifact "libsodium-${libsodium_ver}.tar.gz" || exit 1
    Download_Artifact "libzip-${libzip_ver}.tar.gz" || exit 1
  elif [ "${php_option}" == '13' ] || [ "${mphp_ver}" == '83' ]; then
    Download_Artifact "php-${php83_ver}.tar.gz" || exit 1
    Download_Artifact "argon2-${argon2_ver}.tar.gz" || exit 1
    Download_Artifact "libsodium-${libsodium_ver}.tar.gz" || exit 1
    Download_Artifact "libzip-${libzip_ver}.tar.gz" || exit 1
    Download_Artifact "binutils-${binutils_ver}.tar.gz" || exit 1
  elif [ "${php_option}" == '14' ] || [ "${mphp_ver}" == '84' ]; then
    Download_Artifact "php-${php84_ver}.tar.gz" || exit 1
    Download_Artifact "argon2-${argon2_ver}.tar.gz" || exit 1
    Download_Artifact "libsodium-${libsodium_ver}.tar.gz" || exit 1
    Download_Artifact "libzip-${libzip_ver}.tar.gz" || exit 1
    Download_Artifact "binutils-${binutils_ver}.tar.gz" || exit 1
  elif [ "${php_option}" == '15' ] || [ "${mphp_ver}" == '85' ]; then
    Download_Artifact "php-${php85_ver}.tar.gz" || exit 1
    Download_Artifact "argon2-${argon2_ver}.tar.gz" || exit 1
    Download_Artifact "libsodium-${libsodium_ver}.tar.gz" || exit 1
    Download_Artifact "libzip-${libzip_ver}.tar.gz" || exit 1
    Download_Artifact "binutils-${binutils_ver}.tar.gz" || exit 1
  fi

  # PHP OPCache
  case "${phpcache_option}" in
    1)
      if [[ "${php_option}" =~ ^[1-2]$ ]]; then
        # php 5.3 5.4
        echo "Download Zend OPCache..."
        Download_Artifact "zendopcache-${zendopcache_ver}.tgz" || exit 1
      fi
      ;;
    2)
      echo "Download apcu..."
      if [[ "${php_option}" =~ ^[1-4]$ ]]; then
        Download_Artifact "apcu-4.0.11.tgz" || exit 1
      else
        Download_Artifact "apcu-${apcu_ver}.tgz" || exit 1
      fi
      ;;
    3)
      # php 5.3 5.4
      if [ "${php_option}" == '1' ]; then
        echo "Download eaccelerator 0.9..."
        Download_Artifact "eaccelerator-${eaccelerator_ver}.tar.bz2" || exit 1
      elif [ "${php_option}" == '2' ]; then
        echo "Download eaccelerator 1.0 dev..."
        Download_Artifact "master" || exit 1
      fi
      ;;
  esac

  # Zend Guard Loader
  if [ "${pecl_zendguardloader}" == '1' -a "${armplatform}" != 'y' ]; then
    case "${php_option}" in
      4)
        echo "Download zend loader for php 5.6..."
        Download_Artifact "zend-loader-php5.6-linux-x86_64.tar.gz" || exit 1
        ;;
      3)
        echo "Download zend loader for php 5.5..."
        Download_Artifact "zend-loader-php5.5-linux-x86_64.tar.gz" || exit 1
        ;;
      2)
        echo "Download zend loader for php 5.4..."
        Download_Artifact "ZendGuardLoader-70429-PHP-5.4-linux-glibc23-x86_64.tar.gz" || exit 1
        ;;
      1)
        echo "Download zend loader for php 5.3..."
        Download_Artifact "ZendGuardLoader-php-5.3-linux-glibc23-x86_64.tar.gz" || exit 1
        ;;
    esac
  fi

  # ioncube
  if [ "${pecl_ioncube}" == '1' ]; then
    echo "Download ioncube..."
    Download_Artifact "ioncube_loaders_lin_${SYS_ARCH_i}.tar.gz" || exit 1
  fi

  # SourceGuardian
  if [ "${pecl_sourceguardian}" == '1' ]; then
    echo "Download SourceGuardian..."
    Download_Artifact "loaders.linux-${ARCH}.tar.gz" || exit 1
  fi

  # imageMagick
  if [ "${pecl_imagick}" == '1' ]; then
    echo "Download ImageMagick..."
    Download_Artifact "ImageMagick-${imagemagick_ver}.tar.gz" || exit 1
    echo "Download imagick..."
    if [[ "${php_option}" =~ ^1$ ]]; then
      Download_Artifact "imagick-3.4.4.tgz" || exit 1
    elif [[ "${php_option}" =~ ^[2-3]$ ]]; then
      Download_Artifact "imagick-3.7.0.tgz" || exit 1
    else
      Download_Artifact "imagick-${imagick_ver}.tgz" || exit 1
    fi
  fi

  # graphicsmagick
  if [ "${pecl_gmagick}" == '1' ]; then
    echo "Download graphicsmagick..."
    Download_Artifact "GraphicsMagick-${graphicsmagick_ver}.tar.xz" || exit 1
    if [[ "${php_option}" =~ ^[1-4]$ ]]; then
      echo "Download gmagick for php..."
      Download_Artifact "gmagick-1.1.7RC3.tgz" || exit 1
    else
      echo "Download gmagick for php 7.x..."
      Download_Artifact "gmagick-${gmagick_ver}.tgz" || exit 1
    fi
  fi

  # redis-server
  if [ "${redis_flag}" == 'y' ]; then
    echo "Download redis-server..."
    Download_Artifact "redis-${redis_ver}.tar.gz" || exit 1
  fi

  # pecl_redis
  if [ "${pecl_redis}" == '1' ]; then
    if [[ "${php_option}" =~ ^[1-4]$ ]]; then
      echo "Download pecl_redis for php 5.x..."
      Download_Artifact "redis-4.3.0.tgz" || exit 1
    elif [[ "${php_option}" =~ ^[5-6]$ ]]; then
      echo "Download pecl_redis for php 7.0~7.1..."
      Download_Artifact "redis-5.3.7.tgz" || exit 1
    elif [[ "${php_option}" =~ ^[7-8]$ ]]; then
      echo "Download pecl_redis for php 7.2~7.3..."
      Download_Artifact "redis-6.0.2.tgz" || exit 1
    else
      echo "Download pecl_redis for php 7.4+..."
      Download_Artifact "redis-${pecl_redis_ver}.tgz" || exit 1
    fi
  fi

  # memcached-server
  if [ "${memcached_flag}" == 'y' ]; then
    echo "Download memcached-server..."
    Download_Artifact "memcached-${memcached_ver}.tar.gz" || exit 1
  fi

  # pecl_memcached
  if [ "${pecl_memcached}" == '1' ]; then
    echo "Download libmemcached..."
    Download_Artifact "libmemcached-${libmemcached_ver}.tar.gz" || exit 1
    if [[ "${php_option}" =~ ^[1-4]$ ]]; then
      echo "Download pecl_memcached for php..."
      Download_Artifact "memcached-2.2.0.tgz" || exit 1
    else
      echo "Download pecl_memcached for php 7.x..."
      Download_Artifact "memcached-${pecl_memcached_ver}.tgz" || exit 1
    fi
  fi

  # memcached-server pecl_memcached pecl_memcache
  if [ "${pecl_memcache}" == '1' ]; then
    if [[ "${php_option}" =~ ^[1-4]$ ]]; then
      echo "Download pecl_memcache for php 5.x..."
      Download_Artifact "memcache-3.0.8.tgz" || exit 1
    elif [[ "${php_option}" =~ ^[5-9]$ ]]; then
      echo "Download pecl_memcache for php 7.x..."
      Download_Artifact "memcache-4.0.5.2.tgz" || exit 1
    else
      echo "Download pecl_memcache for php 8.x..."
      Download_Artifact "memcache-${pecl_memcache_ver}.tgz" || exit 1
    fi
  fi

  # pecl_mongodb
  if [ "${pecl_mongodb}" == '1' ]; then
    if [[ "${php_option}" =~ ^[1-4]$ ]]; then
      echo "Download pecl mongo for php 5.x..."
      Download_Artifact "mongo-1.6.16.tgz" || exit 1
    elif [[ "${php_option}" =~ ^5$ ]]; then
      echo "Download pecl mongo for php 7.0..."
      Download_Artifact "mongodb-1.9.2.tgz" || exit 1
    elif [[ "${php_option}" =~ ^[6-8]$ ]]; then
      echo "Download pecl mongo for php 7.1~7.3..."
      Download_Artifact "mongodb-1.16.2.tgz" || exit 1
    else
      echo "Download pecl mongodb for php..."
      Download_Artifact "mongodb-${pecl_mongodb_ver}.tgz" || exit 1
    fi
  fi

  # nodejs
  if [ "${nodejs_flag}" == 'y' ]; then
    echo "Download Nodejs..."
    Download_Artifact "node-v${nodejs_ver}-linux-${SYS_ARCH_n}.tar.gz" || exit 1
  fi

  # pureftpd
  if [ "${pureftpd_flag}" == 'y' ]; then
    echo "Download pureftpd..."
    Download_Artifact "pure-ftpd-${pureftpd_ver}.tar.gz" || exit 1
  fi

  # phpMyAdmin
  if [ "${phpmyadmin_flag}" == 'y' ]; then
    echo "Download phpMyAdmin..."
    if [[ "${php_option}" =~ ^[1-5]$ ]] || [[ "${mphp_ver}" =~ ^5[3-6]$|^70$ ]]; then
      Download_Artifact "phpMyAdmin-4.4.15.10-all-languages.tar.gz" || exit 1
    else
      Download_Artifact "phpMyAdmin-${phpmyadmin_ver}-all-languages.tar.gz" || exit 1
    fi
  fi

  popd > /dev/null
}
