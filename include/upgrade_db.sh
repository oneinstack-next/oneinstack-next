#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
# BLOG:  https://linuxeye.com

Extract_DB_Upgrade_Artifact() {
  local artifact=$1 directory=$2
  case $artifact in
    *.tar.xz) tar xJf "$artifact" || return 1 ;;
    *.tar.gz) tar xzf "$artifact" || return 1 ;;
    *) echo "Unsupported database archive: $artifact" >&2; return 1 ;;
  esac
  [ -d "$directory" ] && [ ! -L "$directory" ] &&
    [ -x "$directory/bin/mysql" ] && [ -x "$directory/bin/mysqld" ] || {
      echo 'Database archive did not produce the expected executable layout' >&2
      return 1
    }
}

Upgrade_DB() {
  pushd ${current_dir}/src > /dev/null
  [ ! -e "${db_install_dir}/bin/mysql" ] && echo "${CWARNING}MySQL/MariaDB/Percona is not installed on your system! ${CEND}" && exit 1
  [ "${armplatform}" == 'y' ] && echo "${CWARNING}The arm architecture operating system does not support upgrading MySQL/MariaDB/Percona! ${CEND}" && exit 1

  # check db passwd
  while :; do
    ${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "quit" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      break
    else
      echo
      read -e -p "Please input the root password of database: " NEW_dbrootpwd
      ${db_install_dir}/bin/mysql -uroot -p${NEW_dbrootpwd} -e "quit" >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        dbrootpwd=${NEW_dbrootpwd}
        sed -i "s+^dbrootpwd.*+dbrootpwd='$dbrootpwd'+" ../options.conf
        break
      else
        echo "${CFAILURE}${DB} root password incorrect,Please enter again! ${CEND}"
      fi
    fi
  done

  OLD_db_ver_tmp=`${db_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e 'select version()\G;' | grep version | awk '{print $2}'`
  if [ -n "`${db_install_dir}/bin/mysql -V | grep -o MariaDB`" ]; then
    DB=MariaDB
    OLD_db_ver=`echo ${OLD_db_ver_tmp} | awk -F'-' '{print $1}'`
  elif [ -n "`${db_install_dir}/bin/mysql -V | grep -o Percona`" ]; then
    DB=Percona
    OLD_db_ver=${OLD_db_ver_tmp}
  else
    DB=MySQL
    OLD_db_ver=${OLD_db_ver_tmp%%-log}
  fi

  #upgrade
  echo
  echo "Current ${DB} Version: ${CMSG}${OLD_db_ver}${CEND}"
  while :; do echo
    [ "${db_flag}" != 'y' ] && read -e -p "Please input upgrade ${DB} Version(example: ${OLD_db_ver}): " NEW_db_ver
    if [ `echo ${NEW_db_ver} | awk -F. '{print $1"."$2}'` == `echo ${OLD_db_ver} | awk -F. '{print $1"."$2}'` ]; then
      if [ "${DB}" == 'MariaDB' ]; then
        DB_filename=mariadb-${NEW_db_ver}-linux-systemd-x86_64
        DB_artifact=${DB_filename}.tar.gz
      elif [ "${DB}" == 'Percona' ]; then
        if [[ "`echo ${NEW_db_ver} | awk -F. '{print $1"."$2}'`" =~ ^5.[5-6]$ ]]; then
          perconaVerStr1=$(echo ${NEW_db_ver} | sed "s@-@-rel@")
        else
          perconaVerStr1=${NEW_db_ver}
        fi
        if [[ "`echo ${NEW_db_ver} | awk -F. '{print $1"."$2}'`" =~ ^8.4$|^8.0$|^5.7$ ]]; then
           DB_filename=Percona-Server-${perconaVerStr1}-Linux.x86_64.glibc2.35
        else
           DB_filename=Percona-Server-${perconaVerStr1}-Linux.x86_64.${sslLibVer}
        fi
        DB_artifact=${DB_filename}.tar.gz
      elif [ "${DB}" == 'MySQL' ]; then
        if [[ ${OLD_db_ver} == 8.4.* || ${OLD_db_ver} == 8.0.* ]]; then
          DB_filename=mysql-${NEW_db_ver}-linux-glibc2.28-x86_64
          DB_artifact=${DB_filename}.tar.xz
        else
          DB_filename=mysql-${NEW_db_ver}-linux-glibc2.12-x86_64
          DB_artifact=${DB_filename}.tar.gz
        fi
      fi
      Download_Artifact "${DB_artifact}" || exit 1
      [ -f "$DB_artifact" ] || return 1
      echo "Download [${CMSG}${DB_artifact}${CEND}] successfully! "
      break
    else
      echo "${CWARNING}input error! ${CEND}Please only input '${CMSG}${OLD_db_ver%.*}.xx${CEND}'"
      [ "${db_flag}" == 'y' ] && exit
    fi
  done

  # Extraction and layout verification must finish before backup, service stop,
  # or moving either the installation or its data directory.
  Extract_DB_Upgrade_Artifact "$DB_artifact" "$DB_filename" || return 1

  #backup
  echo
  echo "${CSUCCESS}Starting ${DB} backup${CEND}......"
  ${db_install_dir}/bin/mysqldump -uroot -p${dbrootpwd} --opt --all-databases > DB_all_backup_$(date +"%Y%m%d").sql || return 1
  [ -s "DB_all_backup_$(date +"%Y%m%d").sql" ] || return 1
  echo "${DB} backup success, Backup file: ${MSG}`pwd`/DB_all_backup_$(date +"%Y%m%d").sql${CEND}"


  if [ -f "$DB_artifact" ]; then
    echo "[${CMSG}${DB_artifact}${CEND}] found"
    if [ "${db_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    if [ "${DB}" == 'MariaDB' ]; then
      service mysqld stop
      mv ${mariadb_install_dir}{,_old_`date +"%Y%m%d_%H%M%S"`}
      mv ${mariadb_data_dir}{,_old_`date +"%Y%m%d_%H%M%S"`}
      [ ! -d "${mariadb_install_dir}" ] && mkdir -p ${mariadb_install_dir}
      mkdir -p ${mariadb_data_dir};chown mysql:mysql -R ${mariadb_data_dir}
      mv ${DB_filename}/* ${mariadb_install_dir}/
      sed -i 's@executing mysqld_safe@executing mysqld_safe\nexport LD_PRELOAD=/usr/local/lib/libjemalloc.so@' ${mariadb_install_dir}/bin/mysqld_safe
      ${mariadb_install_dir}/scripts/mysql_install_db --user=mysql --basedir=${mariadb_install_dir} --datadir=${mariadb_data_dir}
      chown mysql:mysql -R ${mariadb_data_dir}
      service mysqld start
      ${mariadb_install_dir}/bin/mysql < DB_all_backup_$(date +"%Y%m%d").sql
      service mysqld restart
      ${mariadb_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "drop database test;" >/dev/null 2>&1
      ${mariadb_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "reset master;" >/dev/null 2>&1
      ${mariadb_install_dir}/bin/mysql_upgrade -uroot -p${dbrootpwd} >/dev/null 2>&1
      [ $? -eq 0 ] &&  echo "You have ${CMSG}successfully${CEND} upgrade from ${CMSG}${OLD_db_ver}${CEND} to ${CMSG}${NEW_db_ver}${CEND}"
    elif [ "${DB}" == 'Percona' ]; then
      service mysqld stop
      mv ${percona_install_dir}{,_old_`date +"%Y%m%d_%H%M%S"`}
      mv ${percona_data_dir}{,_old_`date +"%Y%m%d_%H%M%S"`}
      [ ! -d "${percona_install_dir}" ] && mkdir -p ${percona_install_dir}
      mkdir -p ${percona_data_dir};chown mysql:mysql -R ${percona_data_dir}
      mv ${DB_filename}/* ${percona_install_dir}/
      sed -i 's@executing mysqld_safe@executing mysqld_safe\nexport LD_PRELOAD=/usr/local/lib/libjemalloc.so@' ${percona_install_dir}/bin/mysqld_safe
      sed -i "s@/usr/local/${DB_filename}@${percona_install_dir}@g" ${percona_install_dir}/bin/mysqld_safe
      if [[ "`echo ${NEW_db_ver} | awk -F. '{print $1"."$2}'`" =~ ^5.[5-6]$ ]]; then
        ${percona_install_dir}/scripts/mysql_install_db --user=mysql --basedir=${percona_install_dir} --datadir=${percona_data_dir}
      else
        ${percona_install_dir}/bin/mysqld --initialize-insecure --user=mysql --basedir=${percona_install_dir} --datadir=${percona_data_dir}
      fi
      chown mysql:mysql -R ${percona_data_dir}
      service mysqld start
      ${percona_install_dir}/bin/mysql < DB_all_backup_$(date +"%Y%m%d").sql
      service mysqld restart
      ${percona_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "drop database test;" >/dev/null 2>&1
      ${percona_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "reset master;" >/dev/null 2>&1
      ${percona_install_dir}/bin/mysql_upgrade -uroot -p${dbrootpwd} >/dev/null 2>&1
      [ $? -eq 0 ] &&  echo "You have ${CMSG}successfully${CEND} upgrade from ${CMSG}${OLD_db_ver}${CEND} to ${CMSG}${NEW_db_ver}${CEND}"
    elif [ "${DB}" == 'MySQL' ]; then
      service mysqld stop
      mv ${mysql_install_dir}{,_old_`date +"%Y%m%d_%H%M%S"`}
      mv ${mysql_data_dir}{,_old_`date +"%Y%m%d_%H%M%S"`}
      [ ! -d "${mysql_install_dir}" ] && mkdir -p ${mysql_install_dir}
      mkdir -p ${mysql_data_dir};chown mysql:mysql -R ${mysql_data_dir}
      mv ${DB_filename}/* ${mysql_install_dir}/
      sed -i 's@executing mysqld_safe@executing mysqld_safe\nexport LD_PRELOAD=/usr/local/lib/libjemalloc.so@' ${mysql_install_dir}/bin/mysqld_safe
      sed -i "s@/usr/local/mysql@${mysql_install_dir}@g" ${mysql_install_dir}/bin/mysqld_safe
      if [[ "`echo ${NEW_db_ver} | awk -F. '{print $1"."$2}'`" =~ ^5.[5-6]$ ]]; then
        ${mysql_install_dir}/scripts/mysql_install_db --user=mysql --basedir=${mysql_install_dir} --datadir=${mysql_data_dir}
      else
        ${mysql_install_dir}/bin/mysqld --initialize-insecure --user=mysql --basedir=${mysql_install_dir} --datadir=${mysql_data_dir}
      fi

      chown mysql:mysql -R ${mysql_data_dir}
      [ -e "${mysql_install_dir}/my.cnf" ] && rm -rf ${mysql_install_dir}/my.cnf
      sed -i '/myisam_repair_threads/d' /etc/my.cnf
      service mysqld start
      ${mysql_install_dir}/bin/mysql < DB_all_backup_$(date +"%Y%m%d").sql
      service mysqld restart
      ${mysql_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "drop database test;" >/dev/null 2>&1
      ${mysql_install_dir}/bin/mysql -uroot -p${dbrootpwd} -e "reset master;" >/dev/null 2>&1
      ${mysql_install_dir}/bin/mysql_upgrade -uroot -p${dbrootpwd} >/dev/null 2>&1
      [ $? -eq 0 ] &&  echo "You have ${CMSG}successfully${CEND} upgrade from ${CMSG}${OLD_db_ver}${CEND} to ${CMSG}${NEW_db_ver}${CEND}"
    fi
  fi
}
