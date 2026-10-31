"""Portable contract tests. Windows lock shim is single-process only;
Linux uses real flock. This does not claim real Nginx-product integration.
"""
import hashlib
import http.server
import io
import json
import os
from pathlib import Path
import shutil
import ssl
import subprocess
import tempfile
import threading
import tarfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get('TEST_BASH') or shutil.which('bash')
OPENSSL = os.environ.get('TEST_OPENSSL') or shutil.which('openssl')


class Contracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix='oneinstack-contracts-')
        cls.work = Path(cls.tmp.name)
        cls.requests = []
        cls.empty_304 = False
        cls.bad_sidecar = False
        cls.payload = b'controlled artifact bytes\n'
        cls.manifest = {
            'schema_name': 'mirrorone-artifacts', 'schema_version': 1,
            'manifest_revision': 'test-revision',
            'generated_at': __import__('datetime').datetime.now(__import__('datetime').timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
            'generator': {'name': 'MirrorOne', 'version': 'test', 'commit': 'fixture', 'instance_id': 'contracts'},
            'mirror': {'base_url': 'https://must-not-override.example'},
            'checksum_policy': {}, 'artifacts': [], 'conflicts': [],
            'version_recommendations': {},
        }
        cls.manifest_bytes = json.dumps(cls.manifest).encode()

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = 'HTTP/1.1'

            def do_GET(self):
                cls.requests.append(self.path)
                if self.path.startswith('/redirect'):
                    self.send_response(302 if '302' in self.path else 301)
                    self.send_header('Location', '/payload')
                    self.send_header('Content-Length', '0')
                    self.end_headers()
                    return
                if self.path == '/missing':
                    self.send_error(404)
                    return
                if self.path == '/unavailable':
                    self.send_error(503)
                    return
                if self.path == '/slow':
                    __import__('time').sleep(0.4)
                if self.path == '/truncated':
                    self.send_response(200)
                    self.send_header('Content-Length', str(len(cls.payload)))
                    self.end_headers()
                    self.wfile.write(cls.payload[:3])
                    self.close_connection = True
                    return
                if self.path == '/loop':
                    self.send_response(302)
                    self.send_header('Location', '/loop')
                    self.send_header('Content-Length', '0')
                    self.end_headers()
                    return
                if self.path == '/downgrade':
                    self.send_response(302)
                    self.send_header('Location', 'http://127.0.0.1/payload')
                    self.send_header('Content-Length', '0')
                    self.end_headers()
                    return
                if self.path.endswith('artifacts.json'):
                    if cls.empty_304:
                        self.send_response(304)
                        self.end_headers()
                        return
                    if self.headers.get('If-None-Match') == '"accepted"':
                        self.send_response(304)
                        self.end_headers()
                        return
                    body = cls.manifest_bytes
                elif self.path.endswith('artifacts.json.sha256'):
                    body = (b'0' * 64 if cls.bad_sidecar else hashlib.sha256(cls.manifest_bytes).hexdigest().encode()) + b'  artifacts.json\n'
                else:
                    body = cls.archive_bytes if self.path == '/archive' else (b'corrupt' if 'bad' in self.path else cls.payload)
                self.send_response(200)
                self.send_header('Content-Length', str(len(body)))
                self.send_header('ETag', '"accepted"')
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

            def handle(self):
                try:
                    super().handle()
                except (ConnectionResetError, BrokenPipeError):
                    pass  # Expected when curl rejects a certificate or redirect.

        cls.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        cert = cls.work / 'cert.pem'
        key = cls.work / 'key.pem'
        subprocess.run([OPENSSL, 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                        '-keyout', str(key), '-out', str(cert), '-subj', '/CN=localhost',
                        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], check=True, capture_output=True)
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(cert, key)
        cls.server.socket = ctx.wrap_socket(cls.server.socket, server_side=True)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = f'https://localhost:{cls.server.server_port}'
        cls.env = os.environ.copy()
        cls.env['CURL_CA_BUNDLE'] = str(cert)
        cls.env['NO_PROXY'] = 'localhost,127.0.0.1'

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.tmp.cleanup()

    def bash(self, script, *args, ok=True):
        shim = '''flock() { :; }; curl() { command curl --cacert "$CURL_CA_BUNDLE" "$@"; };
        jq() { command jq --binary "$@"; };
        converted=(); for arg in "$@"; do
          [[ $arg != [A-Za-z]:* ]] || arg=$(cygpath -u "$arg")
          converted+=("$arg")
        done; set -- "${converted[@]}";
        ''' if os.name == 'nt' else ''
        code = 'current_dir="$PWD"; source include/download.sh; ' + shim + script
        result = subprocess.run([BASH, '-c', code, 'contracts', *map(str, args)],
                                cwd=ROOT, env=self.env, capture_output=True, text=True, timeout=35)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def catalog(self, path='/payload', digest=None, **overrides):
        record = dict(filename='fixture.bin', sha256=digest or hashlib.sha256(self.payload).hexdigest(),
                      size=len(self.payload), source_url=self.url + path, provider='official', reason='test fixture',
                      component='fixture', version='1.0', kind='binary', channel='release', format='raw',
                      platform=dict(os='any', arch='any', libc=None))
        record.update(overrides)
        catalog = self.work / 'catalog.json'
        catalog.write_text(json.dumps({'artifacts': [record]}))
        return catalog

    def test_01_version_data_rejects_code_duplicates_and_unknown_keys(self):
        version = self.work / 'versions.txt'
        for content in ['nginx_ver=$(touch hacked)\n', 'PATH=oops\n', 'nginx_ver=1.0\nnginx_ver=2.0\n', 'nginx_ver=nope\n']:
            version.write_text(content)
            self.bash('source include/version_data.sh; Read_Versions "$1"', version, ok=False)
        version.write_bytes(b'# comment\r\nicu4c_ver=63_1\r\nnginx_ver=1.30.6\r\n')
        self.bash('source include/version_data.sh; Read_Versions "$1" partial && test "$icu4c_ver" = 63_1', version)
        self.assertFalse((ROOT / 'hacked').exists())

    def test_02_redirect_query_cache_and_integrity(self):
        for path in ['/payload?force_redirect=true', '/redirect301?force_redirect=true', '/redirect302?force_redirect=true']:
            catalog = self.catalog(path)
            dest = self.work / 'downloads'
            dest.mkdir(exist_ok=True)
            (dest / 'fixture.bin').write_bytes(b'corrupt cache')
            self.bash('artifact_catalog=$1; download_provider=official; Download_Artifact fixture.bin "$2"', catalog, dest)
            self.assertEqual((dest / 'fixture.bin').read_bytes(), self.payload)
        self.assertIn('/payload', self.requests)
        self.assertNotIn('/payload?force_redirect=true&force_redirect=true', self.requests)
        before = len(self.requests)
        self.bash('artifact_catalog=$1; download_provider=official; Download_Artifact fixture.bin "$2"', catalog, dest)
        self.assertEqual(before, len(self.requests), 'verified cache must not request the artifact')
        self.bash('artifact_catalog=$1; download_provider=official; cd "$2"; src_url=https://example.invalid/fixture.bin?force_redirect=true; Download_src', catalog, dest)

    def test_03_failures_never_publish(self):
        for path in ['/missing', '/unavailable', '/bad', '/truncated', '/loop', '/downgrade']:
            catalog = self.catalog(path)
            with tempfile.TemporaryDirectory(dir=self.work) as tmp:
                self.bash('artifact_catalog=$1; download_provider=official; Download_Artifact fixture.bin "$2"', catalog, tmp, ok=False)
                self.assertEqual(list(Path(tmp).iterdir()), [])
        catalog = self.catalog('/slow')
        with tempfile.TemporaryDirectory(dir=self.work) as tmp:
            # Shorten the production transport budget for this fault injection.
            self.bash('''curl() { command curl --cacert "$CURL_CA_BUNDLE" "$@" --max-time 0.1 --retry 0; }
              artifact_catalog=$1; download_provider=official; Download_Artifact fixture.bin "$2"
            ''', catalog, tmp, ok=False)
            self.assertEqual(list(Path(tmp).iterdir()), [])
        self.env['CURL_CA_BUNDLE'] = str(self.work / 'nonexistent-ca.pem')
        self.bash('Source_HTTP "$1"', self.url + '/payload', ok=False)
        self.env['CURL_CA_BUNDLE'] = str(self.work / 'cert.pem')

    def test_04_missing_digest_platform_ambiguity(self):
        for overrides in [dict(sha256=None), dict(platform=dict(os='linux', arch='impossible', libc=None))]:
            self.bash('artifact_catalog=$1; download_provider=official; Artifact_Resolve fixture.bin', self.catalog(**overrides), ok=False)
        catalog = self.catalog()
        data = json.loads(catalog.read_text())
        data['artifacts'] *= 2
        catalog.write_text(json.dumps(data))
        self.bash('artifact_catalog=$1; download_provider=official; Artifact_Resolve fixture.bin', catalog, ok=False)

    def test_05_manifest_200_304_and_schema_rejection(self):
        # Private fake repository/cache; never writes repository metadata.
        repo = self.work / 'repo'
        repo.mkdir(exist_ok=True)
        self.bash('current_dir=$1; mirror_link=$2; Manifest_Fetch && test -s "$manifest_snapshot"; unset manifest_snapshot; Manifest_Fetch', repo, self.url)
        before = (repo / '.metadata/accepted.json').read_bytes()
        self.manifest_bytes = json.dumps(dict(self.manifest, schema_version=2)).encode()
        # Handler accesses the class to simulate a publication change.
        type(self).manifest_bytes = self.manifest_bytes
        (repo / '.metadata/etag').unlink()
        self.bash('current_dir=$1; mirror_link=$2; Manifest_Fetch', repo, self.url, ok=False)
        self.assertEqual((repo / '.metadata/accepted.json').read_bytes(), before)
        type(self).manifest_bytes = json.dumps(self.manifest).encode()

    def test_06_help_is_read_only_on_non_linux(self):
        for entry in ['install.sh', 'upgrade.sh', 'addons.sh', 'vhost.sh']:
            self.bash('bash "$1" --help', entry)

    def test_07_pipeline_failure_propagates(self):
        catalog = self.catalog('/bad')
        self.bash('artifact_catalog=$1; download_provider=official; src_url=https://example.invalid/fixture.bin; (Download_src; echo MUST_NOT_RUN) | cat; exit "${PIPESTATUS[0]}"', catalog, ok=False)

    def test_08_all_nginx_writers_share_listener_redirect_and_challenge(self):
        body = (ROOT / 'vhost.sh').read_text(encoding='utf-8')
        # Source only definitions, without running entrypoint initialization.
        definitions = body[body.index('Choose_ENV() {'):body.rindex('\nif [ ${ARG_NUM} == 0 ]; then')]
        functions = self.work / 'vhost-functions.sh'
        functions.write_text(definitions, encoding='utf-8', newline='\n')
        for writer, rewrite in [('Create_nginx_phpfpm_conf', 'none'),
                                ('Create_nginx_phpfpm_conf', 'magento2'),
                                ('Create_nginx_proxy_conf', 'none'),
                                ('Create_nginx_tomcat_conf', 'none')]:
            result = self.bash('''
              source include/nginx_config.sh; source "$1"
              web_install_dir=$2/render; PATH_SSL=$web_install_dir/conf/ssl
              wwwlogs_dir=$web_install_dir/logs; vhostdir=$web_install_dir/www
              tomcat_install_dir=$web_install_dir/tomcat
              mkdir -p "$PATH_SSL" "$wwwlogs_dir" "$vhostdir" "$tomcat_install_dir/conf/vhost" "$web_install_dir/conf/rewrite"
              printf '<Server/>\n' > "$tomcat_install_dir/conf/server.xml"
              backend_candidate=$web_install_dir/backend.candidate
              backend_server_candidate=$web_install_dir/server.candidate.xml
              cp "$tomcat_install_dir/conf/server.xml" "$backend_server_candidate"
              domain=example.test; moredomainame=' alias.example.test'; redirect_flag=y
              nginx_ssl_flag=y; https_flag=y; nginx_ipv6=true; nginx_hsts=false
              Nginx_conf='# ONEINSTACK_LISTEN'; Nginx_log='access_log off;'
              rewrite=$4; Proxy_Pass=http://127.0.0.1:18181
              NGX_CONF='location / { return 200 "application"; }'
              Nginx_Probe() { nginx_http2_style=modern; }
              # Override only external backend restart; the renderer is real.
              service() { :; }
              Tomcat_Control() { :; }
              xmllint() { :; } # This test covers writer output, not Tomcat parsing.
              [[ $(uname -s) != *NT* ]] || chown() { :; }
              Print_SSL() { :; }
              Nginx_Commit_Candidate() { Nginx_Render "$nginx_candidate" && cp "$nginx_candidate" "$web_install_dir/result.conf"; }
              "$3"
              cat "$web_install_dir/result.conf"
            ''', functions, self.work, writer, rewrite)
            output = result.stdout
            self.assertIn('http2 on;', output)
            self.assertIn('listen [::]:443 ssl;', output)
            self.assertIn('location / { return 301 https://example.test$request_uri; }', output)
            self.assertIn('location ^~ /.well-known/acme-challenge/', output)
            self.assertNotIn('# ONEINSTACK_LISTEN', output)
            self.assertNotIn('Strict-Transport-Security', output)
            self.assertNotIn('$ssl_protocol =', output)

    def test_09_empty_304_and_manifest_sidecar_publication_race(self):
        cls = type(self)
        cls.empty_304 = True
        repo = self.work / 'empty304'
        repo.mkdir()
        try:
            self.bash('current_dir=$1; mirror_link=$2; Manifest_Fetch', repo, self.url, ok=False)
            self.assertFalse((repo / '.metadata/accepted.json').exists())
        finally:
            cls.empty_304 = False
        cls.bad_sidecar = True
        before = len([p for p in self.requests if p.endswith('artifacts.json')])
        try:
            self.bash('current_dir=$1; mirror_link=$2; Manifest_Fetch', repo, self.url, ok=False)
            after = len([p for p in self.requests if p.endswith('artifacts.json')])
            self.assertEqual(after - before, 3, 'retry the whole manifest/sidecar pair exactly three times')
            self.assertFalse((repo / '.metadata/accepted.json').exists())
        finally:
            cls.bad_sidecar = False

    def test_10_candidate_rejection_and_reload_rollback(self):
        fake = self.work / 'fake-nginx'
        fake.write_text('''#!/bin/bash
prefix= config= action=
while [ $# -gt 0 ]; do
  case $1 in -p) prefix=$2; shift 2;; -c) config=$2; shift 2;; -t) action=test; shift;; -s) action=$2; shift 2;; *) shift;; esac
done
echo "$action" >> "$prefix/actions.log"
if [ "$action" = test ]; then ! grep -rq INVALID "$(dirname "$config")"
elif [ "$action" = reload ]; then ! grep -q RELOAD_FAIL "$prefix/conf/vhost/example.test.conf"
else exit 0; fi
''', encoding='utf-8', newline='\n')
        self.bash('''
          source include/nginx_config.sh
          web_install_dir=$2/transaction; domain=example.test
          mkdir -p "$web_install_dir/sbin" "$web_install_dir/conf/vhost"
          cp "$1" "$web_install_dir/sbin/nginx"; chmod +x "$web_install_dir/sbin/nginx"
          echo 'events {} http {}' > "$web_install_dir/conf/nginx.conf"
          target=$web_install_dir/conf/vhost/example.test.conf
          echo OLD_GOOD > "$target"; chmod 640 "$target"
          Nginx_Capture_Workers() { :; }
          Nginx_Requirements() { :; }
          Nginx_Health() { :; }
          # Windows has no POSIX ownership; Linux CI uses actual chown.
          [[ $(uname -s) != *NT* ]] || chown() { :; }
          echo INVALID > "$web_install_dir/candidate"
          if Nginx_Activate "$web_install_dir/candidate" "$target"; then exit 10; fi
          [ "$(cat "$target")" = OLD_GOOD ] || exit 11
          echo RELOAD_FAIL > "$web_install_dir/candidate"
          if Nginx_Activate "$web_install_dir/candidate" "$target"; then exit 12; fi
          [ "$(cat "$target")" = OLD_GOOD ] || exit 13
          [ "$(grep -c reload "$web_install_dir/actions.log")" -eq 2 ] || exit 14
          echo NEW_GOOD > "$web_install_dir/candidate"
          Nginx_Activate "$web_install_dir/candidate" "$target" || exit 15
          [ "$(cat "$target")" = NEW_GOOD ] || exit 16
        ''', fake, self.work)

    def test_11_config_precedence_and_invalid_values(self):
        self.env['ONEINSTACK_DOWNLOAD_PROVIDER'] = 'mirrorone'
        self.env['ONEINSTACK_MIRROR_LINK'] = 'https://environment.example'
        try:
            result = self.bash('bash tools/sourcectl.sh --summary --download_provider official --mirror_link https://cli.example/ --mirror_force_redirect false')
            self.assertIn('official (https://cli.example)', result.stdout)
            self.assertIn('uncached files may still redirect upstream', result.stdout)
            self.bash('bash tools/sourcectl.sh --summary --mirror_link "https://user:pass@host.example/?token=x"', ok=False)
            self.bash('bash tools/sourcectl.sh --summary --download_fallback anything', ok=False)
        finally:
            self.env.pop('ONEINSTACK_DOWNLOAD_PROVIDER', None)
            self.env.pop('ONEINSTACK_MIRROR_LINK', None)

    def test_12_frontend_backend_rollback_set(self):
        self.bash('''
          source include/nginx_config.sh
          web_install_dir=$1/group; apache_install_dir=$web_install_dir/apache
          domain=example.test; nginx_replace_managed=true
          mkdir -p "$web_install_dir/sbin" "$web_install_dir/conf/vhost" "$apache_install_dir/bin" "$apache_install_dir/conf/vhost"
          printf '#!/bin/bash\nexit 0\n' > "$web_install_dir/sbin/nginx"
          cp "$web_install_dir/sbin/nginx" "$apache_install_dir/bin/apachectl"
          chmod +x "$web_install_dir/sbin/nginx" "$apache_install_dir/bin/apachectl"
          echo FRONT_OLD > "$web_install_dir/conf/vhost/$domain.conf"
          echo BACKEND_OLD > "$apache_install_dir/conf/vhost/$domain.conf"
          chmod 640 "$web_install_dir/conf/vhost/$domain.conf"
          chmod 600 "$apache_install_dir/conf/vhost/$domain.conf"
          Nginx_Requirements() { :; }
          broken_writer() {
            echo FRONT_NEW > "$web_install_dir/conf/vhost/$domain.conf"
            echo BACKEND_NEW > "$apache_install_dir/conf/vhost/$domain.conf"
            return 1
          }
          if Nginx_Group_Run apache broken_writer; then exit 10; fi
          [ "$(cat "$web_install_dir/conf/vhost/$domain.conf")" = FRONT_OLD ] || exit 11
          [ "$(cat "$apache_install_dir/conf/vhost/$domain.conf")" = BACKEND_OLD ] || exit 12
          if [[ $(uname -s) = Linux ]]; then
            [ "$(stat -c %a "$web_install_dir/conf/vhost/$domain.conf")" = 640 ] || exit 13
            [ "$(stat -c %a "$apache_install_dir/conf/vhost/$domain.conf")" = 600 ] || exit 14
          fi
        ''', self.work)

    def test_13_alias_identity_conflict_and_local_mirror_base(self):
        catalog = self.catalog(provider='mirrorone', mirror_filename='canonical.bin')
        record = json.loads(catalog.read_text())['artifacts'][0]
        manifest = json.loads(json.dumps(self.manifest))
        artifact = dict(id='fixture:1.0:binary:any', filename='canonical.bin', aliases=['fixture.bin'],
                        component=record['component'], version=record['version'], channel=record['channel'],
                        kind=record['kind'], platform=record['platform'],
                        source=dict(provider='fixture', url=record['source_url']),
                        mirror=dict(path='/src/canonical.bin', available=True, cache_status='not_cached', integrity_status='not_cached'),
                        checksums=dict(sha256=record['sha256']), checksum_metadata={}, size={'bytes': len(self.payload)})
        manifest['artifacts'] = [artifact]
        path = self.work / 'alias-manifest.json'
        path.write_text(json.dumps(manifest))
        result = self.bash('artifact_catalog=$1; manifest_snapshot=$2; mirror_link=$3; Artifact_Resolve fixture.bin && printf "%s" "$artifact_url"', catalog, path, self.url)
        self.assertEqual(result.stdout, self.url + '/src/canonical.bin?force_redirect=true')
        manifest['conflicts'] = [dict(filename='canonical.bin', reason='test conflict', candidates=[])]
        path.write_text(json.dumps(manifest))
        self.bash('artifact_catalog=$1; manifest_snapshot=$2; mirror_link=$3; Artifact_Resolve fixture.bin', catalog, path, self.url, ok=False)

    @unittest.skipIf(os.name == 'nt', 'POSIX filesystem permissions are validated on Linux CI')
    def test_14_metadata_symlink_is_not_followed(self):
        repo = self.work / 'symlink-repo'
        repo.mkdir()
        target = self.work / 'metadata-target'
        target.mkdir(mode=0o755)
        (repo / '.metadata').symlink_to(target, target_is_directory=True)
        before = target.stat().st_mode
        self.bash('current_dir=$1; Source_Cache_Dir', repo, ok=False)
        self.assertEqual(target.stat().st_mode, before)
        self.assertEqual(list(target.iterdir()), [])

    def test_15_archive_layout_and_traversal_before_publication(self):
        for member, top, success in [('actual-1/Makefile', 'wrong-1', False),
                                      ('../escape', 'actual-1', False),
                                      ('actual-1/Makefile', 'actual-1', True)]:
            archive = io.BytesIO()
            with tarfile.open(fileobj=archive, mode='w:gz') as tar:
                info = tarfile.TarInfo(member)
                info.size = 2
                tar.addfile(info, io.BytesIO(b'ok'))
            type(self).archive_bytes = archive.getvalue()
            catalog = self.catalog('/archive', digest=hashlib.sha256(self.archive_bytes).hexdigest(),
                                   size=len(self.archive_bytes), format='tar.gz', top_dir=top,
                                   required_paths=['Makefile'])
            with tempfile.TemporaryDirectory(dir=self.work) as dest:
                self.bash('artifact_catalog=$1; download_provider=official; Download_Artifact fixture.bin "$2"', catalog, dest, ok=success)
                self.assertEqual((Path(dest) / 'fixture.bin').exists(), success)

    def test_16_acme_success_without_deploy_receipt_is_failure(self):
        client = self.work / 'fake-acme'
        client.write_text('''#!/bin/bash
printf '%s\n' "$@" >> "$HOME/acme.calls"
while [ $# -gt 0 ]; do
  case $1 in --fullchain-file) cp "$TEST_CERT" "$2"; shift 2;; *) shift;; esac
done
# Simulate a client that returns success even though its reload hook failed.
exit 0
''', encoding='utf-8', newline='\n')
        self.bash('''
          source include/nginx_config.sh; source include/acme.sh
          HOME=$2/acme-home; export HOME
          mkdir -p "$HOME/.acme.sh/dnsapi"
          cp "$1" "$HOME/.acme.sh/acme.sh"; chmod +x "$HOME/.acme.sh/acme.sh"
          echo 'AUTO_UPGRADE=0' > "$HOME/.acme.sh/account.conf"
          touch "$HOME/.acme.sh/dnsapi/dns_cf.sh"
          TEST_CERT=$3; export TEST_CERT
          web_install_dir=$2/acme-web; domain=example.test; moredomainame=
          dnsapi_flag=y; DNS_PRO=cf; CERT_KEYLENGTH=ec-256
          if Issue_Nginx_Certificate; then exit 10; fi
          grep -Fx -- --install-cert "$HOME/acme.calls" >/dev/null || exit 11
        ''', client, self.work, self.work / 'cert.pem')

    def test_17_configure_arguments_preserve_quotes_without_execution(self):
        self.bash('''
          source include/nginx_build.sh
          cd "$1" || exit 1
          openssl_ver=3.5.6; pcre_ver=8.45
          args="--prefix=/old --with-openssl=../openssl-1.1.1 --with-pcre=../pcre-8.44 --with-ld-opt='-Wl,-rpath,\\$ORIGIN -ljemalloc'"
          Nginx_Build_Arguments "$args" /new || exit 10
          [ "${nginx_build_args[0]}" = --prefix=/new ] || exit 11
          [ "${nginx_build_args[1]}" = --with-openssl=../openssl-3.5.6 ] || exit 12
          [ "${nginx_build_args[3]}" = '--with-ld-opt=-Wl,-rpath,$ORIGIN -ljemalloc' ] || exit 13
          args='--with-cc-opt="$(touch MUST_NOT_EXIST)"'
          Nginx_Build_Arguments "$args" /new || exit 14
          [ ! -e MUST_NOT_EXIST ] || exit 15
          if Nginx_Build_Arguments '--add-module=/unreviewed' /new; then exit 16; fi
          if Nginx_Build_Arguments "--with-ld-opt='unterminated" /new; then exit 17; fi
        ''', self.work)


if __name__ == '__main__':
    unittest.main(verbosity=2)
