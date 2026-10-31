# Source and HTTPS modernization

Implementation is on `modernize-sources-https`, based on
`0a663e78bd3ece6d2a4f05812f129b4d46246d63`. `origin/main` matched that baseline
when fetched on 2026-10-31. This is a reviewable working-tree change, not a
production deployment or a completed Linux installation qualification.

## Configuration and compatibility

The existing installation, upgrade, addon and virtual-host entrypoints, service
numbers, colors and English prompts remain. Source selection adds one small
menu in interactive mode. Supplying existing automation arguments does not add
new source prompts. The supported precedence is CLI, then `ONEINSTACK_*`
environment variables, then `options.conf`, then compatibility defaults.

| Setting | Default | Values / behavior |
| --- | --- | --- |
| `download_provider` | `mirrorone` | `mirrorone`, `official` |
| `mirror_link` | `https://mirror.dal.ao` | Clean HTTPS hostname/IP base, optional port/path; no credentials/query/fragment |
| `mirror_force_redirect` | `true` | `true` / `false`; only artifact requests get the parameter |
| `download_fallback` | `none` | `official` explicitly permits artifact transport fallback to the same reviewed identity |
| `version_source` | `local` | Only the checked-in baseline is used automatically |
| `verification_policy` | `strict` | Reviewed strong pins are required; no global skip-verification switch |
| `nginx_hsts` | `false` | Explicit new-host HSTS, without includeSubDomains/preload |
| `nginx_ipv6` | `false` | Explicit listeners; no inference from link-local addresses |
| `publish_diagnostics` | `false` | Optional legacy probe artifacts still need registry entries; normal installation does not publish phpinfo |

Environment variables are `ONEINSTACK_DOWNLOAD_PROVIDER`,
`ONEINSTACK_MIRROR_LINK`, `ONEINSTACK_MIRROR_FORCE_REDIRECT` and
`ONEINSTACK_DOWNLOAD_FALLBACK`. The corresponding lowercase CLI flags take
precedence. A trailing base slash is normalized. The original shipped mirror
value is recognized and migrated **in memory**. Custom mirror addresses are
preserved and validated; the script does not silently rewrite the configuration
or fall back to the old mirror. Old secrets, installation paths and selections
remain in `options.conf`. `current_dir` is recomputed runtime state.

Turning force redirect off follows server mode; uncached resources may still
redirect. It does not force caching and does not invalidate a verified local
cache. Official mode uses the same artifact registry, digest, platform, format
and cache checks. Fallback never changes the selected version or digest.
Metadata, schema, identity ambiguity, conflicts and integrity errors stop the
operation even when artifact transport fallback is enabled.

`--help` and standalone `--check-versions` dispatch before root/OS/service
initialization. The read-only artifact planning command is:

```bash
bash tools/sourcectl.sh --preflight --download_provider mirrorone nginx-1.30.6.tar.gz
```

Install signed OS packages `jq`, `curl`, `ca-certificates`, `coreutils` and
`util-linux` before running the installer. It does not bootstrap an arbitrary
remote JSON-parser binary. Tomcat frontend changes additionally require
`xmllint` (`libxml2-utils` on Ubuntu, `libxml2` on Rocky). Work from a trusted,
root-owned checkout for privileged installation. Python is a developer/test
dependency, not an installer framework dependency.

## Artifact and metadata interfaces

`config/artifacts.json` is the reviewed identity and trust registry. It records
filename, component, exact version, kind, channel, platform, upstream URL,
archive format/layout, optional size and a fixed SHA-256. `verification` records
whether the pin came from a publisher checksum, direct publisher HTTPS bytes,
or a bundled project file. Directly observed project pins are **not** upstream
signature verification. The mirror's checksum alone is never promoted to the
trust root. Null pins and missing entries are deliberate preflight failures.

`Download_Artifact filename [destination]` resolves that registry, checks the
current platform and glibc minimum, then resolves an exact MirrorOne manifest
record when applicable. `mirror_filename` can express a reviewed alias mapping;
the canonical filename, alias declaration and mirror path must all agree.
Ambiguity or quarantine is an error. The configured base always wins over the
manifest's base URL. All production artifact callers now pass filenames
explicitly. `Download_src` is retained only for external compatibility and tests;
remove it in the next incompatible helper API release.

Downloads use certificate-verified HTTPS, at most five redirects, bounded
timeouts/retries, a private same-filesystem staging directory, digest/size/format
checks and atomic publication. Tar entries are checked for traversal and an
expected top directory where specified. ZIP and PHAR formats have their own
checks. Bundled patches are verified without a network request. A damaged cache
is re-fetched from byte zero; partial bytes are never appended and trusted.
Failure cannot flow into extraction/build, including installation tee pipelines.
Selected archives also require named build inputs before publication. The
Argon2 archive's actual `phc-winner-argon2-20171227` root is used by PHP builds.

Manifest v1 is parsed with jq. The raw response and sidecar are checked as one
pair, retried together at most three times on publication races. The accepted
entity, ETag, origin and local digest are cached. A 304 requires an existing
validated entity. Unknown/malformed schemas never replace accepted data.
Snapshots older than 30 days or implausibly in the future are rejected; there is
no automatic stale/offline metadata fallback. Official mode plus a complete
verified local artifact cache is the offline route.

One operation freezes the local catalog, version baseline and one manifest
snapshot. Preflight saves `.metadata/last-plan.json` and a content-addressed raw
snapshot. The plan is private, contains no installer passwords, and records
**intended selection**, not installation success. Concurrent plans use private
publication files. Version recommendations are displayed with baseline,
available artifacts and reviewed pins. OpenSSL branch, ICU spelling, acme key
and Nginx mainline/stable differences are explicit. Unknown recommendation keys
are ignored; version data is never sourced/evaluated as Shell.

Adopting a recommendation requires a reviewed exact artifact/pin and compatible
branch/platform/layout. Maintain the local baseline/catalog through a normal
reviewed change, or pass an exact supported upgrade version. The installer does
not turn a suggestion into a database/PHP major upgrade. A missing newer entry
is an error rather than a request to install a different release.

The original acquisition inventory, including direct retries, bootstrap paths,
patches and bundled binaries, is in `source-inventory.json`. Package repositories,
ACME/DNS APIs, installed-client API requests and local health checks remain
separate protocols. They are not arbitrary MirrorOne proxy paths.

## HTTPS activation and rollback

New PHP, proxy, Tomcat, Apache-fronted and Magento hosts share listener, TLS,
HTTP redirect and challenge rendering. Magento's application template retains
its `pub` root. ACME uses a dedicated root under `conf/acme`; challenge paths
stay local even for reverse proxies and HTTP redirects. Canonical-host redirects
use dedicated servers, not substitutions anchored to `root` lines.

The target binary's `-V` is recorded and minimal complete configurations probe
modern `http2 on` versus legacy listener syntax. Module and full-tree tests
remain mandatory. Tengine is not classified from its Nginx core version alone.
New TLS hosts use TLS 1.2/1.3 and ECDHE TLS-1.2 ciphers; TLS-1.3 uses the linked
library defaults. No unconditional ssl_conf_command, OCSP, HTTP/3, QUIC, Alt-Svc,
0-RTT or HSTS preload is added. Existing build-time HTTP/3 flags remain distinct
from listener activation; the historical OpenResty install/upgrade flag
difference is not a promise of HTTP/3 support.

Candidates and backups stay outside active include globs. A shared lock
serializes managed configuration, certificate deployment and binary switches.
The complete candidate tree is validated, the baseline's content/permissions are
checked for changes, and managed files are atomically replaced. Existing hosts
are not overwritten by default. Worker replacement, local challenge requests,
TLS listener checks and the selected redirect are checked after reload. Failure
restores the managed file and reloads the previous configuration.

Apache/Tomcat frontend creation holds the same lock across a rollback set.
Apache gets a complete staged configuration context; Tomcat XML is checked
without network entity resolution before publication. Backend failure restores
both frontend/backend files, including Tomcat's main XML. Nginx-to-Apache port 88
uses loopback HTTP; frontend TLS is not incorrectly enabled on that HTTP backend.
Existing global Apache listener/firewall policy still needs its own review.
Tomcat control matches the target `catalina.base` and process user, gracefully
stops that process, and runs its startup script as the configured non-root
runtime user. It preserves the previously running/stopped state on rollback.
For a stopped custom service, provide `JAVA_HOME` when it cannot be identified
from the existing service's simple literal configuration.

New Nginx ACME issuance temporarily serves only challenges and 404 responses,
not application source. DNS credentials must be exported before starting that
flow. acme.sh acquisition is pinned; automatic client self-upgrade is disabled.
Renewal writes a private certificate inbox, validates the hostname/key pair and
a complete candidate tree, then deploys/reloads with rollback of both files.
An exit code from acme.sh alone is insufficient: issuance requires a fresh
deployment receipt matching the installed certificate digest and chosen key
size. New self-signed Nginx certificates use SANs and the same deployment path.
The standalone historical Apache-only certificate flow is retained; it is not
covered by the new Nginx deployment hook and is listed for follow-up validation.

Web binary upgrades test the new binary against current configuration/dynamic
modules before replacement. They confirm a new master/workers and an actual
health request before terminating the old master. Failure restores the old
binary/master. Configure `nginx_upgrade_health_url` when the default localhost
site is unsuitable. The old binary is retained as `sbin/nginx.previous`.
During rollback the previous master's workers must resume before the new
master is asked to quit. The PID-file handoff is checked separately; incomplete
recovery reports that manual inspection is required. This ordering follows
Nginx's [master lifecycle](https://raw.githubusercontent.com/nginx/nginx/release-1.30.6/src/os/unix/ngx_process_cycle.c).
Nginx/Tengine configure arguments are parsed as quoted data into a Bash array,
never evaluated. External module source flags stop an automatic rebuild until
their source and compatibility have a reviewed upgrade plan.

For existing sites use `tools/migrate-vhost.sh --audit WEB_PREFIX`. Unknown or
custom configurations are reported for manual review. `--preview` compares an
explicit candidate, including legacy/custom hosts with a manual-review notice.
`--apply` requires matching managed-host identity markers and is an explicit
validated activation with rollback. It never rewrites an entire directory or
site data. Existing default TLS servers/SNI policy and inherited headers require
review before claiming that an entire deployment has retired legacy TLS/HSTS.

## Project updates and manual migration

Automatic `upgrade.sh --script` is disabled until **this** repository has a
verified release channel. It never fetches historical lnmp tarballs, uses shared
`/tmp/options.conf`, or changes unrelated PHP settings/service sandboxes.

For manual updates, create a separate checkout of a reviewed full commit from
`oneinstack-next/oneinstack-next`. Save the old `options.conf` in a private
`mktemp -d` directory under the administrator's home, compare new defaults, and
carry over paths/secrets/settings without printing them. Keep the old checkout
until validation is complete. Roll back by returning to that checkout and its
saved configuration; do not overwrite site data, databases or certificate
accounts. No manual-update command is embedded that blindly copies a new script
tree over an existing one.

## Validation status and remaining acceptance

The 2026-10-31 local run executed 17 contract tests: 16 passed and the POSIX-only
metadata symlink/permission test was skipped. Targeted ShellCheck passed; syntax
results are recorded in `validation.json`.

Windows Git Bash contract tests use a single-process flock shim and cannot prove
Linux locking/ownership or product compatibility. Local tests cover data-code
separation, redirects/query handling, damaged caches, TLS/HTTP failures, schema
and sidecar races, missing pins/platform ambiguity, pipeline failures, CLI
precedence, writer output and managed-file rollback. Real public network probes
are recorded in `network-smoke.json`; a curl-based Nginx download passed the new
contract with its independent project pin. Generic urllib probes received 403;
the production curl client observed 301/302 as expected. The deployed manifest
reports generator 2.1.0 and commit `unknown`; an exact deployment commit was not
independently established.

CI definitions build real Nginx, Tengine and OpenResty, exercise actual HTTP/TLS
requests, certificate deployment and HSTS, and include Ubuntu 24.04 x86_64,
Ubuntu aarch64 and Rocky 9 coverage. These definitions have **not been run** in
this Windows environment. Neither full stack compilation/database operation nor
ACME staging issuance has been performed. The current environment has no usable
WSL or Docker daemon. Thus P7 and the plan's full Definition of Done remain open;
do not label this change production-qualified or the entire task complete.

The real-binary harness also exercises invalid-configuration rejection, IPv6
loopback requests when available, and the USR2/WINCH/QUIT switch plus an injected
health-check failure and rollback. It reuses the compiled binary's bytes to
isolate the switch protocol; it does not qualify arbitrary cross-version or
external-module ABI upgrades. These added integration scenarios are also
unexecuted until the Linux jobs run.
Its PHP, proxy and Magento cases load the actual writer definitions and serve
static route fixtures; PHP-FPM execution and a full Magento application are
separate full-stack acceptance work.

The remaining external acceptance work is to run/fix those Linux jobs, perform
one supported full core installation per agreed matrix, verify IPv6 where
available, run ACME staging (including failure cleanup), and validate backend
Apache/Tomcat service behavior. Unsupported artifact families remain explicit in
`source-coverage.md`. Security-finding revalidation is handed off separately in
`security-handoff.md`; these changes do not close all 90 imported findings.
