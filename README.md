# <picture><source media="(prefers-color-scheme: dark)" srcset=".github/assets/icon-dark.svg"><img src=".github/assets/icon-light.svg" width="36" height="36" alt=""></picture> sacbe

[![image](https://img.shields.io/github/v/tag/GHEgar/sacbe?label=ghcr.io)](https://github.com/GHEgar/sacbe/pkgs/container/sacbe)
[![license](https://img.shields.io/github/license/GHEgar/sacbe)](LICENSE)

Minimal GeoServer image: official WAR, chosen plugins, non-root, no chown at startup

sacbe is a minimal Docker image for [GeoServer](https://geoserver.org). It is built from the official
WAR and a short list of extensions. It runs as a non-root user from the first instruction, so startup
never does a recursive `chown`. Site configuration is not baked in: it comes in through environment
variables, a read-only overlay copied into the data directory, and a read-only fonts directory.

## Install

```bash
docker pull ghcr.io/ghegar/sacbe:3.0.2-1
```

Or build it from this repository:

```bash
docker build -t sacbe .
docker build --build-arg GS_PLUGINS="control-flow wps" -t sacbe .
```

| Entry | What it is | Needs |
|---|---|---|
| `8080` | Tomcat HTTP connector, GeoServer at `/<GEOSERVER_CONTEXT>/` | nothing |
| `/opt/geoserver/data_dir` | GeoServer data directory (`GEOSERVER_DATA_DIR`) | writable by uid 2000 |
| `/opt/geoserver/gwc_cache` | GeoWebCache tile cache (`GEOWEBCACHE_CACHE_DIR`) | writable by uid 2000 |
| `/etc/geoserver/overlay` | Files copied into the data directory on every start | read-only is fine |
| `/etc/geoserver/fonts` | `.ttf`, `.otf` and `.ttc` fonts for rendering | read-only is fine |

Build arguments:

| Argument | Default | Effect |
|---|---|---|
| `GS_VERSION` | `3.0.2` | GeoServer release to download |
| `GS_PLUGINS` | `control-flow wps vectortiles geopkg-output libjpeg-turbo sec-oidc` | Extensions unzipped into `WEB-INF/lib` |
| `GS_DROP_JARS` | `gs-sec-jdbc gs-web-sec-jdbc gs-sec-ldap gs-web-sec-ldap` | Jars removed from the WAR |
| `GS_PATCH_JARS` | `org.apache.httpcomponents.core5:httpcore5-h2:5.4.3` and `httpclient5`, `httpclient5-cache` `5.6.3` | Maven `group:artifact:version` that replace the WAR's copy of that artifact, checked against `sha256sums.txt` |
| `MAVEN_MIRROR` | `https://repo1.maven.org/maven2` | Where `GS_PATCH_JARS` are downloaded from |
| `GS_MIRROR` | SourceForge GeoServer project | Download base URL |
| `GS_UID`, `GS_GID` | `2000`, `2000` | Runtime user and group |
| `TOMCAT_IMAGE`, `FETCH_IMAGE` | Tomcat 11.0.27 JDK 21 and Debian trixie-slim, pinned by digest | Final and download stages |
| `REVISION` | `unknown` | `org.opencontainers.image.revision` label |

Every downloaded zip must have a line in `sha256sums.txt`, or the build stops.

## Quick start

```bash
docker run -d --name geoserver -p 8080:8080 \
    -e GEOSERVER_ADMIN_PASSWORD=change-me \
    -v geoserver-data:/opt/geoserver/data_dir \
    ghcr.io/ghegar/sacbe:3.0.2-1
```

Open <http://localhost:8080/geoserver/web/> and log in as `admin` / `change-me`. A named volume takes
its ownership from the image; a bind-mounted data directory must be writable by uid 2000:

```bash
docker run -d -p 8080:8080 \
    -e GEOSERVER_ADMIN_PASSWORD=change-me \
    -v ./data_dir:/opt/geoserver/data_dir \
    ghcr.io/ghegar/sacbe:3.0.2-1
```

## What is inside

| Piece | Version |
|---|---|
| GeoServer | 3.0.2, official WAR with checksums pinned in `sha256sums.txt` |
| Base image | `tomcat:11.0.27-jdk21-temurin-noble`, pinned by digest |
| Extensions | control-flow, wps, vectortiles, geopkg-output, libjpeg-turbo (native library included), sec-oidc |
| Removed from the WAR | sec-jdbc, sec-ldap |
| User | `geoserveruser:geoserverusers`, uid and gid 2000 |

The WPS extension brings `gs-kml` as a dependency of `gs-wps-kml-ppio`, so KML output is available.

Image tags follow `<geoserver-version>-<revision>`: `3.0.1-1` is the first build of GeoServer 3.0.1.
No moving tags are published.

## Configuration

GeoServer reads these straight from the environment. sacbe does not translate them.

| Variable | Default |
|---|---|
| `GEOSERVER_DATA_DIR` | `/opt/geoserver/data_dir` |
| `GEOWEBCACHE_CACHE_DIR` | `/opt/geoserver/gwc_cache` |
| `GEOSERVER_CSRF_WHITELIST`, `GEOSERVER_XSTREAM_WHITELIST`, `ENABLE_JSONP`, `MAX_FILTER_RULES`, `OPTIMIZE_LINE_WIDTH`, `PROXY_BASE_URL`, `GEOSERVER_REQUIRE_FILE` | GeoServer defaults |

The entrypoint handles these:

| Variable | Default | Effect |
|---|---|---|
| `GEOSERVER_CONTEXT` | `geoserver` | Webapp path: `/<context>/` |
| `JAVA_MIN_MEM`, `JAVA_MAX_MEM` | `1G`, `2G` | `-Xms` and `-Xmx` |
| `JAVA_EXTRA_OPTS` | empty | Appended last, so it can override any default flag |
| `TZ` | `UTC` | `-Duser.timezone` |
| `PROXY_HOST`, `PROXY_PORT`, `PROXY_SCHEME`, `PROXY_SECURE` | unset, `443`, `https`, `true` | Connector `proxyName`, `proxyPort`, `scheme`, `secure`. Unset `PROXY_HOST` leaves the connector without proxy attributes |
| `HTTP_MAX_HEADER_SIZE` | `65536` | Connector `maxHttpHeaderSize` |
| `GEOSERVER_CONSOLE_DISABLED` | unset | Passed as a system property, the only form GeoServer accepts |
| `GEOSERVER_ADMIN_USER`, `GEOSERVER_ADMIN_PASSWORD` | `admin`, unset | Seed the admin when the data directory has no `security/`, and feed `geoserver-reset-admin` |

`JAVA_OPTS` is rejected on purpose: Tomcat would pass it to every JVM, including `catalina.sh`
helpers. Use `JAVA_EXTRA_OPTS`.

Default JVM flags: G1, heap dumps to `$GEOSERVER_DATA_DIR/heapdumps`, UTF-8, `forceXY`, JTS overlay NG,
GeoTools date handling for shapefile mosaic indexes, the Marlin renderer, the JDK 21 module opens
recommended by GeoServer, and hardening properties (static web files off, FreeMarker escaping,
`X-Frame-Options`, umask 0027).

## Overlay

Mount a directory at `/etc/geoserver/overlay` (read-only is fine). On every start its tree is copied
into the data directory:

- plain files are copied as they are;
- `*.tmpl` files are rendered with `envsubst`, written without the `.tmpl` suffix, and only variables
  defined in the container environment are replaced. `${X-Forwarded-Proto}` and other names that are
  not valid variables stay literal.

The overlay only adds and overwrites. It never deletes, and it overwrites changes made through the
REST API to the same files.

## Classpath overlay

Mount a directory at `/etc/geoserver/classes` (read-only is fine). On every start its tree is copied
into `WEB-INF/classes`, which takes precedence over the jars. Use it to replace a resource that an
extension ships, such as the icon of the OpenID Connect login button:

```text
classes/org/geoserver/web/security/oauth2/login/openid.png
```

## Fonts

Mount a directory with `.ttf`, `.otf` or `.ttc` files at `/etc/geoserver/fonts` (read-only is fine).
It is linked into the user's fontconfig path and cached at startup.

## Reset the admin password

```bash
docker exec -e GEOSERVER_ADMIN_USER=admin -e GEOSERVER_ADMIN_PASSWORD=new <container> geoserver-reset-admin
docker restart <container>
```

The hash uses the Jasypt digest that GeoServer ships (`digest1:`, SHA-256, 100000 iterations).

## Backup and restore

Back up while GeoServer runs. The archive goes to stdout, keeps numeric owners and skips the
directories in `BACKUP_EXCLUDE` (default `gwc heapdumps`):

```bash
docker exec <container> geoserver-backup > geoserver-data.tar.gz
```

Restore with GeoServer stopped, from a one-off container that mounts the same data directory:

```bash
docker stop <container>
docker run --rm -i --volumes-from <container> --entrypoint geoserver-restore ghcr.io/ghegar/sacbe:3.0.2-1 < geoserver-data.tar.gz
docker start <container>
```

With compose: `docker compose stop <service>` and
`docker compose run --rm -T --no-deps --entrypoint geoserver-restore <service> < geoserver-data.tar.gz`.

| Behaviour | Detail |
|---|---|
| Ownership | Everything is restored as uid 2000, whatever the archive says. No `chown` |
| Excluded directories | Kept as they are in the data directory (the tile cache survives a restore) |
| Archive layout | Paths relative to the data directory; archives with a top-level `data_dir/` are accepted too |
| Safety | Refuses to run next to a live GeoServer, and leaves the data directory untouched if the archive has no `global.xml` |

The GeoWebCache directory outside the data directory (`GEOWEBCACHE_CACHE_DIR`) is not part of the
backup.

## Known limitations

- Only `linux/amd64` is published.
- GDAL is not included. Run `gdalwarp` and friends from a separate `ghcr.io/osgeo/gdal` container.
- The healthcheck requests `/<context>/web/`. With `GEOSERVER_CONSOLE_DISABLED=true`, override it with
  `--health-cmd` or a compose `healthcheck`.
- Admin seeding only happens when the data directory has no `security/` and `GEOSERVER_ADMIN_PASSWORD`
  is set; an existing data directory keeps its users.

## Development

```bash
docker build -t sacbe:dev .
sh smoke.sh sacbe:dev
docker run --rm -p 8080:8080 -e GEOSERVER_ADMIN_PASSWORD=x sacbe:dev
```

`smoke.sh` starts the image on port 18080 (`SMOKE_PORT`) and checks that it runs as uid 2000, answers
WMS, WFS, WCS, WPS and WMTS GetCapabilities, offers GeoPackage and vector tile output, accepts REST
calls with the seeded admin, and never logs a `chown`.

Pushing a `v<geoserver-version>-<revision>` tag runs the CI workflow: build, smoke test, Trivy scan, and
push to `ghcr.io/ghegar/sacbe` with SBOM and provenance. CI blocks the push on any fixable CRITICAL
vulnerability. When a library inside the upstream WAR has a fix that GeoServer has not shipped yet, `GS_PATCH_JARS`
swaps in the fixed release; what cannot be swapped goes to `.trivyignore` with an expiry date.

## Contributing

Issues are welcome. Open one before sending a pull request.

## License

GPL-2.0-or-later © GHEgar

The same terms as GeoServer, which this image redistributes. The upstream source of the bundled
GeoServer build is at <https://github.com/geoserver/geoserver/tree/3.0.2>.
