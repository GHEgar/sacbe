ARG TOMCAT_IMAGE=tomcat:11.0.27-jdk21-temurin-noble@sha256:6e0d99d18e38a23a95574a67bd7849d46844b649c9b5238d91a3d0a3bf5f489a
ARG FETCH_IMAGE=debian:trixie-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad

FROM ${FETCH_IMAGE} AS fetch

ARG GS_VERSION=3.0.2
ARG GS_PLUGINS="control-flow wps vectortiles geopkg-output libjpeg-turbo sec-oidc"
ARG GS_MIRROR=https://downloads.sourceforge.net/project/geoserver/GeoServer
ARG GS_DROP_JARS="gs-sec-jdbc gs-web-sec-jdbc gs-sec-ldap gs-web-sec-ldap"
ARG GS_PATCH_JARS="org.apache.httpcomponents.core5:httpcore5-h2:5.4.3 org.apache.httpcomponents.client5:httpclient5:5.6.3 org.apache.httpcomponents.client5:httpclient5-cache:5.6.3"
ARG MAVEN_MIRROR=https://repo1.maven.org/maven2
ARG GS_SOURCE=https://raw.githubusercontent.com/geoserver/geoserver

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl patch unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /fetch
COPY sha256sums.txt .
COPY patches/ patches/

RUN set -eu; \
    get() { \
        grep -q "  $1\$" sha256sums.txt || { echo "sin sha256 para $1" >&2; exit 1; }; \
        curl -fsSL --retry 5 -o "$1" "$2/$1"; \
    }; \
    get "geoserver-${GS_VERSION}-war.zip" "${GS_MIRROR}/${GS_VERSION}"; \
    for p in ${GS_PLUGINS}; do get "geoserver-${GS_VERSION}-${p}-plugin.zip" "${GS_MIRROR}/${GS_VERSION}/extensions"; done; \
    for c in ${GS_PATCH_JARS}; do \
        g=${c%%:*}; r=${c#*:}; a=${r%%:*}; v=${r#*:}; \
        get "${a}-${v}.jar" "${MAVEN_MIRROR}/$(echo "${g}" | tr . /)/${a}/${v}"; \
    done; \
    for f in patches/*.patch; do \
        [ -e "${f}" ] || continue; \
        for src in $(sed -n 's#^+++ b/##p' "${f}"); do \
            grep -q "  src/${src}\$" sha256sums.txt || { echo "sin sha256 para ${src}" >&2; exit 1; }; \
            mkdir -p "src/$(dirname "${src}")"; \
            curl -fsSL --retry 5 -o "src/${src}" "${GS_SOURCE}/${GS_VERSION}/${src}"; \
        done; \
    done; \
    sha256sum -c --ignore-missing --strict sha256sums.txt; \
    mkdir -p src /stage/src; \
    for f in patches/*.patch; do [ -e "${f}" ] && patch -s -d src -p1 < "${f}"; done; \
    find src -name '*.java' -exec cp --parents {} /stage/ \; ; \
    unzip -q "geoserver-${GS_VERSION}-war.zip" geoserver.war; \
    mkdir -p /stage/webapp /stage/lib; \
    unzip -q geoserver.war -d /stage/webapp; \
    for p in ${GS_PLUGINS}; do unzip -qo "geoserver-${GS_VERSION}-${p}-plugin.zip" '*.jar' -d /stage/webapp/WEB-INF/lib; done; \
    for j in ${GS_DROP_JARS}; do rm -f /stage/webapp/WEB-INF/lib/"${j}"-"${GS_VERSION}".jar; done; \
    for c in ${GS_PATCH_JARS}; do \
        r=${c#*:}; a=${r%%:*}; v=${r#*:}; \
        rm -f /stage/webapp/WEB-INF/lib/"${a}"-[0-9]*.jar; \
        cp "${a}-${v}.jar" /stage/webapp/WEB-INF/lib/; \
    done; \
    mv /stage/webapp/WEB-INF/lib/marlin-*.jar /stage/lib/marlin.jar

FROM ${TOMCAT_IMAGE} AS compile

COPY --from=fetch /stage/webapp/WEB-INF/lib /lib
COPY --from=fetch /stage/src /src

RUN set -eu; \
    mkdir -p /classes; \
    files=$(find /src -name '*.java'); \
    [ -z "${files}" ] || javac -proc:none --release 21 -nowarn -encoding UTF-8 -cp '/lib/*' -d /classes ${files}

FROM ${TOMCAT_IMAGE}

ARG GS_VERSION=3.0.2
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
COPY --from=compile /classes /opt/geoserver/webapp/WEB-INF/classes
COPY server.xml.tmpl /opt/geoserver/server.xml.tmpl
COPY entrypoint.sh /usr/local/bin/sacbe-entrypoint
COPY datadir.sh /usr/local/bin/sacbe-datadir

RUN chown -R "${GS_UID}:${GS_GID}" /opt/geoserver/webapp/WEB-INF/classes \
    && chmod 0755 /usr/local/bin/sacbe-entrypoint /usr/local/bin/sacbe-datadir \
    && ln -s sacbe-entrypoint /usr/local/bin/geoserver-reset-admin \
    && ln -s sacbe-datadir /usr/local/bin/geoserver-backup \
    && ln -s sacbe-datadir /usr/local/bin/geoserver-restore

USER ${GS_UID}:${GS_GID}
WORKDIR /opt/geoserver
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=3 \
    CMD curl -fsI "http://localhost:8080/${GEOSERVER_CONTEXT}/web/" >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/sacbe-entrypoint"]
