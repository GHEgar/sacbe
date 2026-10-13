# sacbe

Minimal Docker image for [GeoServer](https://geoserver.org). It is built from the official WAR and a
short list of extensions. It runs as a non-root user from the first instruction, so startup never
does a recursive `chown`. Site configuration is not baked in: it comes in through environment
variables, a read-only overlay copied into the data directory, and a read-only fonts directory.

```bash
docker run -d -p 8080:8080 \
    -e GEOSERVER_ADMIN_PASSWORD=change-me \
    -v ./data_dir:/opt/geoserver/data_dir \
    ghcr.io/ghegar/sacbe:3.0.0-1
```

The bind-mounted data directory must be writable by uid 2000.

## What is inside

| Piece | Version |
|---|---|
| GeoServer | 3.0.0, official WAR with checksums pinned in `sha256sums.txt` |
| Base image | `tomcat:11.0.24-jdk21-temurin-noble`, pinned by digest |
| Extensions | control-flow, wps, vectortiles, geopkg-output, libjpeg-turbo (native library included) |
| Removed from the WAR | web-demo, sec-jdbc, sec-ldap |
| User | `geoserveruser:geoserverusers`, uid and gid 2000 |

The WPS extension brings `gs-kml` as a dependency of `gs-wps-kml-ppio`, so KML output is available.

Image tags follow `<geoserver-version>-<revision>`: `3.0.0-1` is the first build of GeoServer 3.0.0.
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

## Fonts

Mount a directory with `.ttf`, `.otf` or `.ttc` files at `/etc/geoserver/fonts` (read-only is fine).
It is linked into the user's fontconfig path and cached at startup.

## Reset the admin password

```bash
docker exec -e GEOSERVER_ADMIN_USER=admin -e GEOSERVER_ADMIN_PASSWORD=new <container> geoserver-reset-admin
docker restart <container>
```

The hash uses the Jasypt digest that GeoServer ships (`digest1:`, SHA-256, 100000 iterations).

## Build

```bash
docker build -t sacbe .
docker build --build-arg GS_PLUGINS="control-flow wps" -t sacbe .
```

Every downloaded zip must have a line in `sha256sums.txt`, or the build stops.

## License

GPL-2.0-or-later, the same terms as GeoServer, which this image redistributes. The upstream source of
the bundled GeoServer build is at <https://github.com/geoserver/geoserver/tree/3.0.0>.
