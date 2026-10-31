# Artifact coverage and support boundary

Observed on 2026-10-31. The authoritative mapping is [config/artifacts.json](../config/artifacts.json); the baseline call graph is [source-inventory.json](source-inventory.json).

Registered identities: **78**; strong pins: **75**; bundled patches: **15**. A registered/pinned artifact is not an assertion that its component compiles or runs on every historical menu combination.

## Planned matrix

| Combination | Acquisition evidence | Runtime status |
| --- | --- | --- |
| Ubuntu 24.04 / Rocky 9 x86_64; Nginx 1.30.6 + OpenSSL 3.5.6 + PHP 8.5.12 + MySQL 8.4.11 | Exact identities, publisher/project pins; MySQL archive fetched from Oracle and its layout inspected; glibc >= 2.28 enforced | Full Linux install not run |
| Tengine 3.1.0 / OpenResty 1.31.1.1 frontend | Source archives independently fetched and inspected; capability probes implemented | Initial real-binary CI failed; amended-head checks required |
| aarch64 Nginx/PHP source-only stack | Architecture-neutral source records; no x86_64 DB binary substitution | Initial ARM frontend run passed once; amended-head checks required |
| Node.js 20.17.0 x86_64 / aarch64 glibc | Publisher SHASUMS256; fixed archive contract and glibc minimum | Runtime not run |

A default-core metadata selection was also checked with a **simulated** Linux x86_64/glibc 2.39 target in Git Bash. This exercises selection and real manifest matching, not OS or binary execution compatibility.

## Explicitly blocked / unqualified paths

- MySQL 5.5/5.7 candidate binaries and historical eAccelerator have no reviewed strong pin in this change; registry entries are present but blocked.
- MySQL 8.0, MySQL source/ARM, MariaDB, Percona, PostgreSQL and MongoDB Server need exact identity/layout/platform/checksum entries before acquisition. No automatic change of database family/version/install method supplies a substitute.
- Tomcat distributions/JARs, legacy PHP patches not bundled here, historical loaders, unpinned CA bundles, probes, WAF/Lua auxiliary bundles and webgrind remain blocked when no exact entry exists. WAF checks its entire auxiliary set before rebuilding a server.
- Cloud backup helper acquisition is blocked until fixed OSS/COS/UPYUN/Qiniu/AWS/Dropbox client identities are registered. Selection preflight happens before backup settings are written; already installed clients are not silently replaced.
- Old PHP releases may have publisher checksum records while their patch/CA/dependency/ABI combination remains unqualified. Presence of a PHP tarball is not permission to skip its required dependencies.
- JDK acquisition through signed OS package repositories remains a separate package-manager path, not a fictitious MirrorOne source mapping. Repository/key policy still needs the separate security review.
- Bundled `include/ois.x86_64` and `include/ois.aarch64` retain unresolved publisher/build provenance. Geolocation no longer participates in acquisition; existing local-IP/connectivity uses remain. Inventory hashes identify the exact blobs, not an independently authenticated publisher.
- IPv6 listeners are generated only when explicitly configured. Public IPv6 and ACME staging were not exercised here. Existing default TLS servers and custom third-party includes require deployment-specific review.

Apache preflight now includes the reviewed nghttp2 1.59.0 publisher release;
its SHA-256 was matched to the publisher checksum file and its `configure`
layout inspected. PHP 7.4/8.0 preflight and installation share the pinned
MongoDB 1.20.1 selection. These acquisition checks do not qualify those full
software stacks at runtime.

## Exact registry

| Filename | Component / version | Kind / platform | Policy | Verification |
| --- | --- | --- | --- | --- |
| `apcu-5.1.28.tgz` | apcu / 5.1.28 | extension / any/any/any | mirrorone | project-pin-from-publisher-https |
| `apr-util-1.6.3.tar.gz` | apr / 1.6.3 | source / any/any/any | mirrorone | project-pin-from-publisher-https |
| `apr-1.7.5.tar.gz` | apr / 1.7.5 | source / any/any/any | mirrorone | project-pin-from-publisher-https |
| `argon2-20171227.tar.gz` | argon2 / 20171227 | source / any/any/any | mirrorone | project-pin-from-publisher-https |
| `curl-8.17.0.tar.gz` | curl / 8.17.0 | source / any/any/any | mirrorone | project-pin-from-publisher-https |
| `eaccelerator-0.9.6.1.tar.bz2` | eaccelerator / 0.9.6.1 | source / any/any/any | mirrorone | BLOCKED: no reviewed SHA-256 |
| `freetype-2.10.1.tar.gz` | freetype / 2.10.1 | source / any/any/any | mirrorone | project-pin-from-publisher-https |
| `gmagick-2.0.6RC1.tgz` | gmagick / 2.0.6RC1 | extension / any/any/any | mirrorone | project-pin-from-publisher-https |
| `httpd-2.4.69.tar.gz` | httpd / 2.4.69 | source / any/any/any | mirrorone | project-pin-from-publisher-https |
| `imagick-3.8.1.tgz` | imagick / 3.8.1 | extension / any/any/any | mirrorone | project-pin-from-publisher-https |
| `jemalloc-5.3.0.tar.bz2` | jemalloc / 5.3.0 | source / any/any/any | mirrorone | project-pin-from-publisher-https |
| `libiconv-1.16.tar.gz` | libiconv / 1.16 | source / any/any/any | mirrorone | project-pin-from-publisher-https |
| `libmcrypt-2.5.8.tar.gz` | libmcrypt / 2.5.8 | source / any/any/any | official | project-pin-from-publisher-https |
| `libmemcached-1.0.18.tar.gz` | libmemcached / 1.0.18 | source / any/any/any | mirrorone | project-pin-from-publisher-https |
| `mcrypt-2.6.8.tar.gz` | mcrypt / 2.6.8 | source / any/any/any | official | project-pin-from-publisher-https |
| `memcache-8.2.tgz` | memcache / 8.2 | extension / any/any/any | mirrorone | project-pin-from-publisher-https |
| `memcached-3.4.0.tgz` | memcached / 3.4.0 | extension / any/any/any | mirrorone | project-pin-from-publisher-https |
| `mongodb-2.1.4.tgz` | mongodb / 2.1.4 | extension / any/any/any | mirrorone | project-pin-from-publisher-https |
| `mysql-5.5.62-linux-glibc2.12-x86_64.tar.gz` | mysql / 5.5.62 | binary / linux/x86_64/glibc2.12 | mirrorone | BLOCKED: no reviewed SHA-256 |
| `mysql-5.7.44-linux-glibc2.12-x86_64.tar.gz` | mysql / 5.7.44 | binary / linux/x86_64/glibc2.12 | mirrorone | BLOCKED: no reviewed SHA-256 |
| `mysql-8.4.11-linux-glibc2.28-x86_64.tar.xz` | mysql / 8.4.11 | binary / linux/x86_64/glibc2.28 | official | project-pin-from-publisher-https |
| `nginx-1.30.6.tar.gz` | nginx / 1.30.6 | source / any/any/any | mirrorone | project-pin-from-publisher-https |
| `openssl-3.5.6.tar.gz` | openssl / 3.5.6 | source / any/any/any | mirrorone | publisher-checksum |
| `pcre-8.45.tar.gz` | pcre / 8.45 | source / any/any/any | official | project-pin-from-publisher-https |
| `php-5.3.29.tar.gz` | php / 5.3.29 | source / any/any/any | mirrorone | publisher-checksum |
| `php-5.4.45.tar.gz` | php / 5.4.45 | source / any/any/any | mirrorone | publisher-checksum |
| `php-5.5.38.tar.gz` | php / 5.5.38 | source / any/any/any | mirrorone | publisher-checksum |
| `php-5.6.40.tar.gz` | php / 5.6.40 | source / any/any/any | mirrorone | publisher-checksum |
| `php-7.0.33.tar.gz` | php / 7.0.33 | source / any/any/any | mirrorone | publisher-checksum |
| `php-7.1.33.tar.gz` | php / 7.1.33 | source / any/any/any | mirrorone | publisher-checksum |
| `php-7.2.34.tar.gz` | php / 7.2.34 | source / any/any/any | mirrorone | publisher-checksum |
| `php-7.3.33.tar.gz` | php / 7.3.33 | source / any/any/any | mirrorone | publisher-checksum |
| `php-7.4.33.tar.gz` | php / 7.4.33 | source / any/any/any | mirrorone | publisher-checksum |
| `php-8.0.30.tar.gz` | php / 8.0.30 | source / any/any/any | mirrorone | publisher-checksum |
| `php-8.1.34.tar.gz` | php / 8.1.34 | source / any/any/any | mirrorone | publisher-checksum |
| `pure-ftpd-1.0.52.tar.gz` | pure-ftpd / 1.0.52 | source / any/any/any | mirrorone | project-pin-from-publisher-https |
| `redis-6.3.0.tgz` | redis / 6.3.0 | extension / any/any/any | mirrorone | project-pin-from-publisher-https |
| `swoole-6.2.0.tgz` | swoole / 6.2.0 | extension / any/any/any | mirrorone | project-pin-from-publisher-https |
| `tengine-3.1.0.tar.gz` | tengine / 3.1.0 | source / any/any/any | mirrorone | project-pin-from-publisher-https |
| `xdebug-3.1.2.tgz` | xdebug / 3.1.2 | extension / any/any/any | mirrorone | project-pin-from-publisher-https |
| `yaf-3.3.7.tgz` | yaf / 3.3.7 | extension / any/any/any | mirrorone | project-pin-from-publisher-https |
| `yar-2.3.4.tgz` | yar / 2.3.4 | extension / any/any/any | mirrorone | project-pin-from-publisher-https |
| `zendopcache-7.0.5.tgz` | zendopcache / 7.0.5 | extension / any/any/any | mirrorone | project-pin-from-publisher-https |
| `php-8.2.35.tar.gz` | php / 8.2.35 | source / any/any/any | official | publisher-checksum |
| `php-8.3.36.tar.gz` | php / 8.3.36 | source / any/any/any | official | publisher-checksum |
| `php-8.4.27.tar.gz` | php / 8.4.27 | source / any/any/any | official | publisher-checksum |
| `php-8.5.12.tar.gz` | php / 8.5.12 | source / any/any/any | official | publisher-checksum |
| `icu4c-63_1-src.tgz` | icu / release-63-1 | source / any/any/any | mirrorone | project-pin-from-publisher-https |
| `openresty-1.31.1.1.tar.gz` | openresty / 1.31.1.1 | source / any/any/any | official | project-pin-from-publisher-https |
| `acme.sh-3.1.3.tar.gz` | acme.sh / 3.1.3 | source / any/any/any | official | project-pin-from-publisher-https |
| `mhash-0.9.9.9.tar.gz` | mhash / 0.9.9.9 | source / any/any/any | official | project-pin-from-publisher-https |
| `libsodium-1.0.20.tar.gz` | libsodium / 1.0.20 | source / any/any/any | official | project-pin-from-publisher-https |
| `libzip-1.2.0.tar.gz` | libzip / 1.2.0 | source / any/any/any | official | project-pin-from-publisher-https |
| `binutils-2.42.tar.gz` | binutils / 2.42 | source / any/any/any | official | project-pin-from-publisher-https |
| `memcached-1.6.45.tar.gz` | memcached / 1.6.45 | source / any/any/any | official | project-pin-from-publisher-https |
| `redis-7.4.9.tar.gz` | redis / 7.4.9 | source / any/any/any | official | project-pin-from-publisher-https |
| `phpMyAdmin-5.2.3-all-languages.tar.gz` | phpmyadmin / 5.2.3 | source / any/any/any | official | project-pin-from-publisher-https |
| `composer.phar` | composer / 2.8.12 | script / any/any/any | official | project-pin-from-publisher-https |
| `ImageMagick-7.1.2-32.tar.gz` | imagemagick / 7.1.2-32 | source / any/any/any | official | project-pin-from-publisher-https |
| `5.3-CVE-2026-109618-109619.patch` | bundled-patches / 0a663e78bd3ece6d2a4f05812f129b4d46246d63 | patch / any/any/any | bundled | project-bundled-pin |
| `5.4-CVE-2026-109618-109619.patch` | bundled-patches / 0a663e78bd3ece6d2a4f05812f129b4d46246d63 | patch / any/any/any | bundled | project-bundled-pin |
| `5.5-CVE-2026-109618-109619.patch` | bundled-patches / 0a663e78bd3ece6d2a4f05812f129b4d46246d63 | patch / any/any/any | bundled | project-bundled-pin |
| `5.6-CVE-2026-109618-109619.patch` | bundled-patches / 0a663e78bd3ece6d2a4f05812f129b4d46246d63 | patch / any/any/any | bundled | project-bundled-pin |
| `7.0-CVE-2026-109618-109619.patch` | bundled-patches / 0a663e78bd3ece6d2a4f05812f129b4d46246d63 | patch / any/any/any | bundled | project-bundled-pin |
| `7.1-CVE-2026-109618-109619.patch` | bundled-patches / 0a663e78bd3ece6d2a4f05812f129b4d46246d63 | patch / any/any/any | bundled | project-bundled-pin |
| `7.2-CVE-2026-109618-109619.patch` | bundled-patches / 0a663e78bd3ece6d2a4f05812f129b4d46246d63 | patch / any/any/any | bundled | project-bundled-pin |
| `7.3-CVE-2026-109618-109619.patch` | bundled-patches / 0a663e78bd3ece6d2a4f05812f129b4d46246d63 | patch / any/any/any | bundled | project-bundled-pin |
| `7.4-CVE-2026-109618-109619.patch` | bundled-patches / 0a663e78bd3ece6d2a4f05812f129b4d46246d63 | patch / any/any/any | bundled | project-bundled-pin |
| `8.0-CVE-2026-109618-109619.patch` | bundled-patches / 0a663e78bd3ece6d2a4f05812f129b4d46246d63 | patch / any/any/any | bundled | project-bundled-pin |
| `8.1-CVE-2026-109618-109619.patch` | bundled-patches / 0a663e78bd3ece6d2a4f05812f129b4d46246d63 | patch / any/any/any | bundled | project-bundled-pin |
| `libiconv-glibc-2.16.patch` | bundled-patches / 0a663e78bd3ece6d2a4f05812f129b4d46246d63 | patch / any/any/any | bundled | project-bundled-pin |
| `libmemcached-build.patch` | bundled-patches / 0a663e78bd3ece6d2a4f05812f129b4d46246d63 | patch / any/any/any | bundled | project-bundled-pin |
| `php5.3-fileinfo.patch` | bundled-patches / 0a663e78bd3ece6d2a4f05812f129b4d46246d63 | patch / any/any/any | bundled | project-bundled-pin |
| `php5.3patch` | bundled-patches / 0a663e78bd3ece6d2a4f05812f129b4d46246d63 | patch / any/any/any | bundled | project-bundled-pin |
| `node-v20.17.0-linux-x64.tar.gz` | nodejs / 20.17.0 | binary / linux/x86_64/glibc2.28 | official | publisher-checksum |
| `node-v20.17.0-linux-arm64.tar.gz` | nodejs / 20.17.0 | binary / linux/aarch64/glibc2.28 | official | publisher-checksum |
| `nghttp2-1.59.0.tar.gz` | nghttp2 / 1.59.0 | source / any/any/any | official | publisher-checksum |
| `mongodb-1.20.1.tgz` | mongodb / 1.20.1 | extension / any/any/any | mirrorone | project-pin-from-publisher-https |

Official exceptions and their reasons, upstream URLs, sizes, archive roots and full digests are recorded per entry in the JSON. Runtime transport failures never turn an unregistered or weakly verified item into a supported component.
