ARG TOMCAT_IMAGE=tomcat:11.0.27-jdk21-temurin-noble@sha256:05532a690ebbdf637fc3936698b274febc15f7f41d376d41f15999d2f4af1a71
ARG FETCH_IMAGE=debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

FROM ${FETCH_IMAGE} AS fetch

ARG GS_VERSION=3.0.1
ARG GS_PLUGINS="control-flow wps vectortiles geopkg-output libjpeg-turbo sec-oidc"
ARG GS_MIRROR=https://downloads.sourceforge.net/project/geoserver/GeoServer
ARG GS_DROP_JARS="gs-sec-jdbc gs-web-sec-jdbc gs-sec-ldap gs-web-sec-ldap"

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /fetch
COPY sha256sums.txt .

RUN set -eu; \
    get() { \
        grep -q "  $1\$" sha256sums.txt || { echo "sin sha256 para $1" >&2; exit 1; }; \
        curl -fsSL --retry 5 -o "$1" "$2/$1"; \
    }; \
    get "geoserver-${GS_VERSION}-war.zip" "${GS_MIRROR}/${GS_VERSION}"; \
    for p in ${GS_PLUGINS}; do get "geoserver-${GS_VERSION}-${p}-plugin.zip" "${GS_MIRROR}/${GS_VERSION}/extensions"; done; \
    sha256sum -c --ignore-missing --strict sha256sums.txt; \
    unzip -q "geoserver-${GS_VERSION}-war.zip" geoserver.war; \
    mkdir -p /stage/webapp /stage/lib; \
    unzip -q geoserver.war -d /stage/webapp; \
    for p in ${GS_PLUGINS}; do unzip -qo "geoserver-${GS_VERSION}-${p}-plugin.zip" '*.jar' -d /stage/webapp/WEB-INF/lib; done; \
    for j in ${GS_DROP_JARS}; do rm -f /stage/webapp/WEB-INF/lib/"${j}"-"${GS_VERSION}".jar; done; \
    mv /stage/webapp/WEB-INF/lib/marlin-*.jar /stage/lib/marlin.jar

FROM ${TOMCAT_IMAGE}

ARG GS_VERSION=3.0.1
ARG GS_UID=2000
ARG GS_GID=2000
ARG REVISION=unknown

LABEL org.opencontainers.image.title="sacbe" \
      org.opencontainers.image.description="Minimal GeoServer image: official WAR, chosen plugins, non-root, no chown at startup" \
      org.opencontainers.image.source="https://github.com/GHEgar/sacbe" \
      org.opencontainers.image.licenses="GPL-2.0-or-later" \
      org.opencontainers.image.version="${GS_VERSION}" \
      org.opencontainers.image.revision="${REVISION}"

ENV GEOSERVER_HOME=/opt/geoserver \
    GEOSERVER_DATA_DIR=/opt/geoserver/data_dir \
    GEOWEBCACHE_CACHE_DIR=/opt/geoserver/gwc_cache \
    GEOSERVER_CONTEXT=geoserver \
    JAVA_MIN_MEM=1G \
    JAVA_MAX_MEM=2G \
    TZ=UTC

RUN apt-get update \
    && apt-get install -y --no-install-recommends gettext-base libturbojpeg \
    && rm -rf /var/lib/apt/lists/* "${CATALINA_HOME}/webapps.dist" \
    && mkdir -p "${CATALINA_HOME}/native-jni-lib" \
    && ln -s "$(find /usr/lib -name 'libturbojpeg.so.0' | head -n 1)" "${CATALINA_HOME}/native-jni-lib/libturbojpeg.so" \
    && groupadd -g "${GS_GID}" geoserverusers \
    && useradd -u "${GS_UID}" -g "${GS_GID}" -m -d /home/geoserveruser -s /usr/sbin/nologin geoserveruser \
    && find / -xdev -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null; \
    mkdir -p "${GEOSERVER_DATA_DIR}" "${GEOWEBCACHE_CACHE_DIR}" "${CATALINA_HOME}/conf/Catalina/localhost" \
    && chown -R "${GS_UID}:${GS_GID}" "${GEOSERVER_DATA_DIR}" "${GEOWEBCACHE_CACHE_DIR}" \
       "${CATALINA_HOME}/conf" "${CATALINA_HOME}/logs" "${CATALINA_HOME}/temp" \
       "${CATALINA_HOME}/work" "${CATALINA_HOME}/webapps"

COPY --from=fetch /stage/webapp /opt/geoserver/webapp
COPY --from=fetch /stage/lib/marlin.jar ${CATALINA_HOME}/lib/marlin.jar
COPY server.xml.tmpl /opt/geoserver/server.xml.tmpl
COPY entrypoint.sh /usr/local/bin/sacbe-entrypoint
COPY datadir.sh /usr/local/bin/sacbe-datadir

RUN chmod 0755 /usr/local/bin/sacbe-entrypoint /usr/local/bin/sacbe-datadir \
    && ln -s sacbe-entrypoint /usr/local/bin/geoserver-reset-admin \
    && ln -s sacbe-datadir /usr/local/bin/geoserver-backup \
    && ln -s sacbe-datadir /usr/local/bin/geoserver-restore

USER ${GS_UID}:${GS_GID}
WORKDIR /opt/geoserver
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=3 \
    CMD curl -fsI "http://localhost:8080/${GEOSERVER_CONTEXT}/web/" >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/sacbe-entrypoint"]
