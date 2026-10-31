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


def write_lf(path, content):
    # Rocky 9 ships Python 3.9; Path.write_text gained newline only in 3.10.
    with path.open('w', encoding='utf-8', newline='\n') as stream:
        stream.write(content)


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
                except (ConnectionResetError, BrokenPipeError, ssl.SSLError):
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
        write_lf(functions, definitions)
        for writer, rewrite in [('Create_nginx_phpfpm_conf', 'none'),
                                ('Create_nginx_phpfpm_conf', 'magento2'),
                                ('Create_nginx_proxy_conf', 'none'),
                                ('Create_nginx_apache_modphp_conf', 'none'),
                                ('Create_nginx_tomcat_conf', 'none')]:
            result = self.bash('''
              source include/nginx_config.sh; source "$1"
              web_install_dir=$2/render; PATH_SSL=$web_install_dir/conf/ssl
              wwwlogs_dir=$web_install_dir/logs; vhostdir=$web_install_dir/www
              tomcat_install_dir=$web_install_dir/tomcat
              apache_install_dir=$web_install_dir/apache
              mkdir -p "$PATH_SSL" "$wwwlogs_dir" "$vhostdir" "$tomcat_install_dir/conf/vhost" "$web_install_dir/conf/rewrite"
              mkdir -p "$apache_install_dir/bin" "$apache_install_dir/conf/vhost"
              printf '#!/bin/bash\nexit 0\n' > "$apache_install_dir/bin/apachectl"
              chmod +x "$apache_install_dir/bin/apachectl"
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
              Apache_Test_Candidate() { :; }
              xmllint() { :; } # This test covers writer output, not Tomcat parsing.
              [[ $(uname -s) != *NT* ]] || chown() { :; }
              Print_SSL() { :; }
              Nginx_Commit_Candidate() { Nginx_Render "$nginx_candidate" && cp "$nginx_candidate" "$web_install_dir/result.conf"; }
              "$3"
              cat "$web_install_dir/result.conf"
              if [ "$3" = Create_nginx_apache_modphp_conf ]; then
                grep -Fx '<VirtualHost *:88>' "$apache_install_dir/conf/vhost/$domain.conf" || exit 20
              fi
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
        write_lf(fake, '''#!/bin/bash
prefix= config= action=
while [ $# -gt 0 ]; do
  case $1 in -p) prefix=$2; shift 2;; -c) config=$2; shift 2;; -t) action=test; shift;; -s) action=$2; shift 2;; *) shift;; esac
done
echo "$action" >> "$prefix/actions.log"
if [ "$action" = test ]; then ! grep -rq INVALID "$(dirname "$config")"
elif [ "$action" = reload ]; then ! grep -q RELOAD_FAIL "$prefix/conf/vhost/example.test.conf"
else exit 0; fi
''')
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
        cases = [(['actual-1/Makefile'], 'wrong-1', [], False),
                 (['../escape'], 'actual-1', [], False),
                 (['actual-1/Makefile'], 'actual-1', [], True),
                 (['actual-1/Makefile', 'package.xml'], 'actual-1', ['package.xml'], True),
                 (['actual-1/Makefile', 'unreviewed.xml'], 'actual-1', ['package.xml'], False),
                 (['actual-1/Makefile', '../package.xml'], 'actual-1', ['package.xml'], False)]
        for members, top, allowed_roots, success in cases:
            archive = io.BytesIO()
            with tarfile.open(fileobj=archive, mode='w:gz') as tar:
                for member in members:
                    info = tarfile.TarInfo(member)
                    info.size = 2
                    tar.addfile(info, io.BytesIO(b'ok'))
            type(self).archive_bytes = archive.getvalue()
            catalog = self.catalog('/archive', digest=hashlib.sha256(self.archive_bytes).hexdigest(),
                                   size=len(self.archive_bytes), format='tar.gz', top_dir=top,
                                   required_paths=['Makefile'], allowed_root_files=allowed_roots)
            with tempfile.TemporaryDirectory(dir=self.work) as dest:
                self.bash('artifact_catalog=$1; download_provider=official; Download_Artifact fixture.bin "$2"', catalog, dest, ok=success)
                self.assertEqual((Path(dest) / 'fixture.bin').exists(), success)

    def test_16_acme_success_without_deploy_receipt_is_failure(self):
        client = self.work / 'fake-acme'
        write_lf(client, '''#!/bin/bash
printf '%s\n' "$@" >> "$HOME/acme.calls"
while [ $# -gt 0 ]; do
  case $1 in --fullchain-file) cp "$TEST_CERT" "$2"; shift 2;; *) shift;; esac
done
# Simulate a client that returns success even though its reload hook failed.
exit 0
''')
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

    def test_18_http_hsts_assertion_rejects_header_leak(self):
        assertion = next(line.strip() for line in (ROOT / 'tests/nginx_live.sh').read_text().splitlines()
                         if 'HSTS leaked to HTTP' in line)
        directory = self.work / 'header-check'
        directory.mkdir()
        headers = directory / 'http.headers'
        script = 'set -e; web_install_dir=$1; ' + assertion + '\necho HEADER_CHECK_PASSED'
        headers.write_text('HTTP/1.1 200 OK\nStrict-Transport-Security: max-age=15552000\n\n')
        result = self.bash(script, directory, ok=False)
        self.assertNotIn('HEADER_CHECK_PASSED', result.stdout)
        headers.write_text('HTTP/1.1 200 OK\nContent-Length: 0\n\n')
        self.assertIn('HEADER_CHECK_PASSED', self.bash(script, directory).stdout)

    def test_19_ubuntu_dependencies_use_host_multiarch_and_preserve_link_failure(self):
        body = (ROOT / 'include/check_sw.sh').read_text()
        function = body[body.index('installDepsUbuntu() {'):body.index('\ninstallDepsBySrc() {')]
        # Keep package/link operations mocked and redirect this legacy scratch
        # file into the fixture; exercise the actual function's status branches.
        function = function.replace('/tmp/security.sources.list', '${sandbox}/security.sources.list')
        path = self.work / 'ubuntu-dependencies.sh'
        write_lf(path, function)
        self.bash('''
          source "$1"; sandbox=$2
          apt-get() { return 0; }
          grep() { return 0; }
          dpkg-architecture() { printf '%s\n' "$triplet"; }
          Ensure_Libaio_Compat_Link() { printf '%s\n' "$1" >> "$sandbox/link.calls"; return "$helper_status"; }
          apache_flag=n; db_option=0
          for Ubuntu_ver in 20 22; do installDepsUbuntu || exit 10; done
          [ ! -e "$sandbox/link.calls" ] || exit 13
          Ubuntu_ver=24; helper_status=0
          for triplet in x86_64-linux-gnu aarch64-linux-gnu; do installDepsUbuntu || exit 11; done
          [ "$(cat "$sandbox/link.calls")" = $'/usr/lib/x86_64-linux-gnu\n/usr/lib/aarch64-linux-gnu' ] || exit 14
          helper_status=1
          if installDepsUbuntu; then exit 12; fi
          helper_status=0; triplet=../../escape
          before=$(cat "$sandbox/link.calls")
          if installDepsUbuntu; then exit 15; fi
          [ "$(cat "$sandbox/link.calls")" = "$before" ] || exit 16
        ''', path, self.work)

    def test_20_reload_waits_for_previous_workers_to_stop_accepting(self):
        self.bash('''
          source include/nginx_config.sh
          set -e
          web_install_dir=$1/worker-readiness; domain=example.test; nginx_ssl_flag=n
          mkdir -p "$web_install_dir"
          counter=$web_install_dir/probes; echo 0 > "$counter"
          curl_counter=$web_install_dir/requests; echo 0 > "$curl_counter"
          nginx_health_master=999; nginx_health_workers=10
          pgrep() {
            local count pattern=${!#}
            count=$(cat "$counter"); echo "$((count+1))" > "$counter"
            if [ "$count" -eq 0 ]; then
              printf '%s\n' '10 nginx: worker process   ' '20 nginx: worker process  '
            else
              printf '%s\n' '10 nginx: worker process is shutting down  ' '20 nginx: worker process  '
            fi | grep -E "$pattern" | cut -d ' ' -f 1
          }
          sleep() { :; }
          curl() {
            [ "$(cat "$counter")" -ge 2 ] || { echo 'Request was made while old workers still accepted connections' >&2; return 1; }
            local url=${!#} count
            count=$(cat "$curl_counter"); echo "$((count+1))" > "$curl_counter"
            [ "$count" -ne 0 ] || return 7
            printf '%s' "${url##*/}"
          }
          # A standalone call preserves errexit in the actual helper. Its
          # bounded polling must tolerate a transient connection failure.
          Nginx_Health
          [ "$(cat "$counter")" -eq 3 ] || exit 11
          [ "$(cat "$curl_counter")" -eq 2 ] || exit 12
        ''', self.work)

    def test_21_database_extraction_failure_preserves_service_and_data(self):
        mysql = self.work / 'mysql-fixture'
        write_lf(mysql, '''#!/bin/bash
if [[ "$*" == *'select version()'* ]]; then echo 'version(): 8.4.10'; fi
exit 0
''')
        self.bash('''
          source include/upgrade_db.sh
          current_dir=$1/db-extraction-failure; db_install_dir=$current_dir/database
          mysql_install_dir=$db_install_dir; mysql_data_dir=$current_dir/data
          mkdir -p "$current_dir/src" "$db_install_dir/bin" "$mysql_data_dir"
          cp "$2" "$db_install_dir/bin/mysql"; chmod +x "$db_install_dir/bin/mysql"
          printf 'existing database' > "$mysql_data_dir/sentinel"
          export TEST_CALLS=$current_dir/unexpected.calls
          printf '#!/bin/bash\necho dump >> "$TEST_CALLS"\necho SQL\n' > "$db_install_dir/bin/mysqldump"
          chmod +x "$db_install_dir/bin/mysqldump"
          Download_Artifact() { printf 'truncated archive' > "$1"; }
          service() { echo service >> "$TEST_CALLS"; }
          mv() { echo move >> "$TEST_CALLS"; return 1; }
          db_flag=y; armplatform=n; NEW_db_ver=8.4.11; dbrootpwd=fixture
          if (Upgrade_DB); then exit 10; fi
          [ ! -e "$TEST_CALLS" ] || exit 11
          [ "$(cat "$mysql_data_dir/sentinel")" = 'existing database' ] || exit 12
          [ -f "$db_install_dir/bin/mysql" ] || exit 13
          [ -f "$current_dir/src/mysql-8.4.11-linux-glibc2.28-x86_64.tar.xz" ] || exit 14
        ''', self.work, mysql)
        # Prove successful extraction accepts both supported compressors and
        # checks the actual executable layout before a database is stopped.
        for compression in ['gz', 'xz']:
            directory = self.work / ('db-valid-' + compression)
            directory.mkdir()
            archive = directory / ('mysql-fixture.tar.' + compression)
            with tarfile.open(archive, 'w:' + compression) as tar:
                for binary in ['mysql', 'mysqld']:
                    info = tarfile.TarInfo('mysql-fixture/bin/' + binary)
                    info.mode = 0o755
                    info.size = 9
                    tar.addfile(info, io.BytesIO(b'#!/bin/sh'))
            self.bash('source include/upgrade_db.sh; cd "$1"; Extract_DB_Upgrade_Artifact "$2" mysql-fixture', directory, archive.name)

    def test_22_php_upgrade_legacy_patch_is_scoped_to_53_through_55(self):
        config = self.work / 'php-config-fixture'
        write_lf(config, '#!/bin/bash\nprintf "%s\\n" "$TEST_PHP_VERSION"\n')
        for version, patch_expected in [('8.5.12', False), ('5.6.40', False), ('5.5.38', True)]:
            result = self.bash('''
              source include/upgrade_php.sh
              current_dir=$1/php-upgrade-$2; php_install_dir=$current_dir/php
              mkdir -p "$current_dir/src" "$php_install_dir/bin"
              cp "$3" "$php_install_dir/bin/php-config"; chmod +x "$php_install_dir/bin/php-config"
              TEST_PHP_VERSION=$2; export TEST_PHP_VERSION
              NEW_php_ver=$2; php_flag=y
              ledger=$current_dir/downloads
              Download_Artifact() { echo "$1" >> "$ledger"; printf fixture > "$1"; }
              # Stop before compilation; this test exercises acquisition order.
              tar() { return 31; }
              if (Upgrade_PHP); then exit 10; fi
              cat "$ledger"
            ''', self.work, version, config)
            downloads = [line for line in result.stdout.splitlines() if line.endswith(('.tar.gz', '.patch'))]
            self.assertIn('php-' + version + '.tar.gz', downloads)
            self.assertEqual('fpm-race-condition.patch' in downloads, patch_expected)

    def test_23_mongodb_preflight_and_installer_select_the_same_artifact(self):
        config = self.work / 'mongodb-php-config-fixture'
        write_lf(config, '#!/bin/bash\nprintf "%s\\n" "$TEST_PHP_VERSION"\n')
        for php_option, mphp, version in [('9', '', '7.4.33'), ('10', '', '8.0.30'),
                                         ('0', '74', '7.4.33'), ('0', '80', '8.0.30')]:
            self.bash('''
              source include/version_data.sh; Read_Versions versions.txt || exit 1
              source include/preflight.sh; source include/check_download.sh; source include/pecl_mongodb.sh
              current_dir=$1/mongodb-$2-$3; php_install_dir=$current_dir/php
              mkdir -p "$current_dir/src" "$php_install_dir/bin"
              cp "$5" "$php_install_dir/bin/php-config"; chmod +x "$php_install_dir/bin/php-config"
              touch "$php_install_dir/bin/phpize"
              TEST_PHP_VERSION=$4; export TEST_PHP_VERSION
              php_option=$2; mphp_ver=$3; pecl_mongodb=1
              ledger=$current_dir/preflight.downloads
              Download_Artifact() { echo "$1" >> "$ledger"; }
              checkDownload || exit 10
              [ "$(grep '^mongo' "$ledger")" = mongodb-1.20.1.tgz ] || exit 11
              ledger=$current_dir/install.downloads
              Download_Artifact() { echo "$1" >> "$ledger"; return 1; }
              if (Install_pecl_mongodb); then exit 12; fi
              [ "$(cat "$ledger")" = mongodb-1.20.1.tgz ] || exit 13
            ''', self.work, php_option, mphp, version, config)

    def test_24_binary_switch_retries_missing_pid_file_under_errexit(self):
        self.bash('''
          source include/nginx_config.sh
          set -e
          prefix=$1/binary-handoff
          mkdir -p "$prefix/sbin" "$prefix/conf" "$prefix/logs"
          TEST_PIDFILE=$prefix/logs/nginx.pid; export TEST_PIDFILE
          printf 123 > "$TEST_PIDFILE"
          cat > "$prefix/sbin/nginx" <<'NGINX'
#!/bin/bash
for arg in "$@"; do
  case $arg in
    -T) printf 'pid %s;\n' "$TEST_PIDFILE"; exit 0 ;;
    -V) echo 'nginx version: controlled fixture'; exit 0 ;;
  esac
done
exit 0
NGINX
          chmod +x "$prefix/sbin/nginx"
          cp -p "$prefix/sbin/nginx" "$prefix/candidate"
          printf '\n# candidate build\n' >> "$prefix/candidate"
          old_digest=$(sha256sum < "$prefix/sbin/nginx")
          new_digest=$(sha256sum < "$prefix/candidate")
          counter=$prefix/pid-reads; printf 0 > "$counter"
          signals=$prefix/signals
          Nginx_Requirements() { :; }
          cat() {
            if [ "$1" = "$TEST_PIDFILE" ]; then
              local count
              count=$(command cat "$counter"); echo "$((count+1))" > "$counter"
              case $count in 0) echo 123 ;; 1) return 1 ;; *) echo 456 ;; esac
            else command cat "$@"; fi
          }
          kill() {
            case "$*" in
              '-0 123'|'-0 456'|'-USR2 123'|'-WINCH 123'|'-QUIT 123') printf '%s\n' "$*" >> "$signals" ;;
              *) echo "Unexpected signal: $*" >&2; return 1 ;;
            esac
          }
          pgrep() { echo 789; }
          curl() { echo health > "$prefix/healthy"; }
          sleep() { :; }
          # Do not wrap this call in if/||: doing so disables errexit inside
          # Bash functions and would conceal the missing-PID handoff defect.
          Nginx_Upgrade_Binary "$prefix/candidate" "$prefix"
          [ "$(command cat "$counter")" -eq 3 ] || exit 10
          [ -f "$prefix/healthy" ] || exit 11
          grep -Fx -- '-QUIT 123' "$signals" >/dev/null || exit 12
          [ "$(sha256sum < "$prefix/sbin/nginx.previous")" = "$old_digest" ] || exit 13
          [ "$(sha256sum < "$prefix/sbin/nginx")" = "$new_digest" ] || exit 14
        ''', self.work)

    def test_25_worker_snapshot_rejects_failed_or_empty_queries_without_pipefail(self):
        self.bash('''
          source include/nginx_config.sh
          set +o pipefail
          web_install_dir=$1/worker-snapshot
          mkdir -p "$web_install_dir/sbin" "$web_install_dir/logs"
          TEST_PIDFILE=$web_install_dir/logs/nginx.pid; export TEST_PIDFILE
          printf 123 > "$TEST_PIDFILE"
          printf '#!/bin/bash\nprintf "pid %%s;\\n" "$TEST_PIDFILE"\n' > "$web_install_dir/sbin/nginx"
          chmod +x "$web_install_dir/sbin/nginx"
          filter_file=$web_install_dir/worker-filter
          kill() { return 0; }
          pgrep() {
            printf '%s' "${!#}" > "$filter_file"
            case $query_mode in
              failed) return "$query_status" ;;
              empty) return 0 ;;
              valid)
                printf '%s\n' '30 nginx: worker process  ' '70 nginx: worker process is shutting down  ' '10 nginx: worker process   ' |
                  grep -E "${!#}" | cut -d ' ' -f 1 ;;
            esac
          }
          query_mode=failed
          for query_status in 1 2 127; do
            nginx_health_workers=STALE
            if Nginx_Capture_Workers; then echo 'Failed worker query was accepted' >&2; exit 10; fi
            [ -z "$nginx_health_workers" ] || exit 16
          done
          query_mode=empty
          if Nginx_Capture_Workers; then echo 'Empty worker snapshot was accepted' >&2; exit 11; fi
          query_mode=valid
          Nginx_Capture_Workers || exit 12
          [ "$nginx_health_master" = 123 ] || exit 13
          [ "$nginx_health_workers" = $'10\n30' ] || exit 14
          pattern=$(cat "$filter_file")
          printf 'nginx: worker process   \n' | grep -Eq "$pattern" || exit 15
          if printf 'nginx: worker process is shutting down  \n' | grep -Eq "$pattern"; then exit 17; fi
        ''', self.work)

    def test_26_libaio_link_is_idempotent_and_preserves_conflicts(self):
        if os.name == 'nt':
            target = self.work / 'symlink-probe-target'
            target.write_bytes(b'probe')
            probe = self.work / 'symlink-probe'
            try:
                probe.symlink_to(target)
            except OSError as error:
                self.skipTest('Native Windows symlinks unavailable: ' + str(error))
            probe.unlink()
            previous_msys = self.env.get('MSYS')
            self.env['MSYS'] = ((previous_msys or '') + ' winsymlinks:nativestrict').strip()
            def restore_msys():
                if previous_msys is None:
                    self.env.pop('MSYS', None)
                else:
                    self.env['MSYS'] = previous_msys
            self.addCleanup(restore_msys)
        self.bash('''
          source include/check_sw.sh
          for kind in fresh relative absolute conflict wrong dangling missing-source failed-create; do
            libdir=$1/libaio-$kind
            mkdir -p "$libdir"
            printf LIBRARY > "$libdir/libaio.so.1t64.0.2"
            if [ "$kind" = fresh ]; then cp "$libdir/libaio.so.1t64.0.2" "$libdir/libaio.so.1t64"
            else ln -s libaio.so.1t64.0.2 "$libdir/libaio.so.1t64"; fi
            link=$libdir/libaio.so.1
            case $kind in
              relative) ln -s libaio.so.1t64 "$link" ;;
              absolute) ln -s "$libdir/libaio.so.1t64" "$link" ;;
              conflict) printf LOCAL_FILE > "$link" ;;
              wrong) printf OTHER_LIBRARY > "$libdir/other.so"; ln -s other.so "$link" ;;
              dangling) ln -s missing.so "$link" ;;
              missing-source) rm "$libdir/libaio.so.1t64" ;;
              failed-create) ln() { return 1; } ;;
            esac
            case $kind in
              fresh|relative|absolute)
                Ensure_Libaio_Compat_Link "$libdir" || exit 10
                [ "$(readlink -e "$link")" = "$(readlink -e "$libdir/libaio.so.1t64")" ] || exit 11
                before=$(readlink "$link")
                Ensure_Libaio_Compat_Link "$libdir" || exit 12
                [ "$(readlink "$link")" = "$before" ] || exit 13 ;;
              *)
                before=$(if [ -L "$link" ]; then readlink "$link"; elif [ -e "$link" ]; then sha256sum "$link"; else printf ABSENT; fi)
                if Ensure_Libaio_Compat_Link "$libdir"; then echo "Conflicting libaio case accepted: $kind" >&2; exit 20; fi
                after=$(if [ -L "$link" ]; then readlink "$link"; elif [ -e "$link" ]; then sha256sum "$link"; else printf ABSENT; fi)
                [ "$after" = "$before" ] || exit 21 ;;
            esac
            [ "$(cat "$libdir/libaio.so.1t64.0.2")" = LIBRARY ] || exit 22
            [ "$kind" != failed-create ] || unset -f ln
          done
        ''', self.work)


if __name__ == '__main__':
    unittest.main(verbosity=2)
