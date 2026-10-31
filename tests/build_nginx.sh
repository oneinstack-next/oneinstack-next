#!/bin/bash
set -eo pipefail
current_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
product=$1
prefix=$2
. "$current_dir/options.conf"
. "$current_dir/include/version_data.sh"
Read_Versions "$current_dir/versions.txt"
. "$current_dir/include/download.sh"
download_provider=official
Source_Start_Run
case $product in nginx|tengine|openresty) key=${product}_ver; version=${!key} ;; *) exit 2 ;; esac
mkdir -p "$prefix/source"
Download_Artifact "$product-$version.tar.gz" "$prefix/source"
Download_Artifact "pcre-$pcre_ver.tar.gz" "$prefix/source"
Download_Artifact "openssl-$openssl_ver.tar.gz" "$prefix/source"
cd "$prefix/source"
tar xzf "$product-$version.tar.gz"
tar xzf "pcre-$pcre_ver.tar.gz"
tar xzf "openssl-$openssl_ver.tar.gz"
cd "$product-$version"
./configure --prefix="$prefix/install" --with-http_ssl_module --with-http_v2_module --with-pcre="../pcre-$pcre_ver" --with-openssl="../openssl-$openssl_ver"
make -j2
make install
if [ "$product" = openresty ]; then prefix=$prefix/install/nginx; else prefix=$prefix/install; fi
bash "$current_dir/tests/nginx_live.sh" "$prefix"
