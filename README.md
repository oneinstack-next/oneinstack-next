# Oneinstack-next

Bash-based LNMP installation and administration, preserving the numbered CLI.
The source/HTTPS modernization is under integration validation; read
[modernization status and migration](docs/modernization.md) and the exact
[source coverage](docs/source-coverage.md) before installing. Historical menu
entries are retained, but missing or unverified artifacts now stop preflight.

The historical shell entrypoints deploy LEMP/LAMP/LNMP/LNMPA/LTMP stacks. Historical distro and version menus are retained; the current modernization validation targets Ubuntu 24.04 and Rocky Linux 9, with explicitly scoped aarch64 coverage. Artifact registration is not a claim of runtime qualification; consult the support matrix linked above.

Script properties:
- Numbered shell interaction and noninteractive installation arguments
- Version-controlled baseline, reviewed artifact identities and strong checksum pins
- Some security optimization
- Providing a plurality of database versions (MySQL-8.4, MySQL-8.0, MySQL-5.7, MySQL-5.5, MariaDB-11.8, MariaDB-11.4, MariaDB-10.11, MariaDB-5.5, Percona-8.4, Percona-8.0, Percona-5.7, Percona-5.5, PostgreSQL, MongoDB)
- Providing multiple PHP versions (PHP-8.5, PHP-8.4, PHP-8.3, PHP-8.2, PHP-8.1, PHP-8.0, PHP-7.4, PHP-7.3, PHP-7.2, PHP-7.1, PHP-7.0, PHP-5.6, PHP-5.5, PHP-5.4, PHP-5.3)
- Provide Nginx, Tengine, OpenResty, Apache and ngx_lua_waf
- Providing a plurality of Tomcat version (Tomcat-10, Tomcat-9, Tomcat-8, Tomcat-7)
- Providing a plurality of JDK version (OpenJDK-8, OpenJDK-11, OpenJDK-17)
- According to their needs to install PHP Cache Accelerator provides ZendOPcache, apcu, eAccelerator. And php extensions,include ZendGuardLoader,ionCube,SourceGuardian,imagick,gmagick,fileinfo,imap,ldap,calendar,phalcon,yaf,yar,redis,memcached,memcache,mongodb,swoole,xdebug
- Installation Nodejs, Pureftpd, phpMyAdmin according to their needs
- Install memcached, redis according to their needs
- Jemalloc optimize MySQL, Nginx
- Providing add a virtual host script, include Let's Encrypt SSL certificate
- Provide Nginx/Tengine/OpenResty/Apache/Tomcat, MySQL/MariaDB/Percona, PHP, Redis, Memcached, phpMyAdmin upgrade script
- Provide local,remote(rsync between servers),Aliyun OSS,Qcloud COS,UPYUN,QINIU,Amazon S3,Google Drive and Dropbox backup script

## Installation

Install the dependencies for your distro, download the source and run the installation script.

#### CentOS/Redhat

```bash
dnf -y install git screen jq curl ca-certificates util-linux coreutils
```

#### Debian/Ubuntu

```bash
apt-get update
apt-get -y install git screen jq curl ca-certificates util-linux coreutils
```

#### Download Source and Install

```bash
git clone https://github.com/oneinstack-next/oneinstack-next.git
cd oneinstack-next
# Select a full commit that you have reviewed, before executing its scripts.
read -r -p 'Reviewed full commit SHA: ' REVIEWED_COMMIT
[[ $REVIEWED_COMMIT =~ ^[0-9a-f]{40}$ ]] || exit 1
git checkout --detach "$REVIEWED_COMMIT"
git show --stat HEAD
```

If you disconnect during installation, you can execute the command `screen -r lnmp` to reconnect to the install window
```bash
screen -S lnmp
```

If you need to modify the directory (installation, data storage, Nginx logs), modify `options.conf` file before running install.sh
```bash
./install.sh
```

## Source selection and checks

```bash
bash tools/sourcectl.sh --summary
bash tools/sourcectl.sh --check-versions
bash tools/sourcectl.sh --preflight nginx-1.30.6.tar.gz
./install.sh --nginx_option 1 --download_provider mirrorone --mirror_force_redirect true
```

Configure a clean HTTPS `mirror_link` in `options.conf` or pass it as an option.
`false` follows server mode and may still redirect to upstream; it does not force
cache delivery. Explicit official mode uses the same reviewed hashes and cache
checks. `download_fallback=none` is the default. Version suggestions never run as
Shell or silently change the baseline. Preflight plans are saved privately in
`.metadata/last-plan.json`; this records intended selection, not install success.

Use `bash tools/migrate-vhost.sh --audit /usr/local/nginx` for a read-only legacy
host inventory. Existing sites are not automatically rewritten. Automatic script
self-update is disabled until this repository has a verified release channel.

## How to install another PHP version

```bash
~/oneinstack-next/install.sh --mphp_ver 54

```

## How to add Extensions

```bash
~/oneinstack-next/addons.sh

```

## How to add a virtual host

```bash
~/oneinstack-next/vhost.sh
```

## How to delete a virtual host

```bash
~/oneinstack-next/vhost.sh --del
```

## How to add FTP virtual user

```bash
~/oneinstack-next/pureftpd_vhost.sh
```

## How to backup

```bash
~/oneinstack-next/backup_setup.sh    // Backup parameters
~/oneinstack-next/backup.sh    // Perform the backup immediately
crontab -l    // Can be added to scheduled tasks, such as automatic backups every day 1:00
  0 1 * * * cd ~/oneinstack-next/backup.sh  > /dev/null 2>&1 &
```

## How to manage service

Nginx/Tengine/OpenResty:
```bash
systemctl {start|stop|status|restart|reload} nginx
```
MySQL/MariaDB/Percona:
```bash
systemctl {start|stop|restart|reload|status} mysqld
```
PostgreSQL:
```bash
systemctl {start|stop|restart|status} postgresql
```
MongoDB:
```bash
systemctl {start|stop|status|restart|reload} mongod
```
PHP:
```bash
systemctl {start|stop|restart|reload|status} php-fpm
```
Apache:
```bash
systemctl {start|restart|stop} httpd
```
Tomcat:
```bash
systemctl {start|stop|status|restart} tomcat
```
Pure-FTPd:
```bash
systemctl {start|stop|restart|status} pureftpd
```
Redis:
```bash
systemctl {start|stop|status|restart|reload} redis-server
```
Memcached:
```bash
systemctl {start|stop|status|restart|reload} memcached
```

## How to upgrade

```bash
~/oneinstack-next/upgrade.sh
```

## How to uninstall

```bash
~/oneinstack-next/uninstall.sh
```
