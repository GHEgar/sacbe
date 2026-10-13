#!/bin/sh
set -eu

WEBAPP=/opt/geoserver/webapp
OVERLAY_DIR=${OVERLAY_DIR:-/etc/geoserver/overlay}
FONTS_DIR=${FONTS_DIR:-/etc/geoserver/fonts}
DATA_DIR=${GEOSERVER_DATA_DIR}

log() {
    printf 'sacbe: %s\n' "$*" >&2
}

defined_vars() {
    env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/${\1}/p' | tr '\n' ' '
}

sed_escape() {
    printf '%s' "$1" | sed 's/[|&\\]/\\&/g'
}

password_hash() {
    jar=$(find "${WEBAPP}/WEB-INF/lib" -maxdepth 1 -name 'jasypt-[0-9]*.jar' | head -n 1)
    [ -n "${jar}" ] || { log 'no se encontro jasypt en WEB-INF/lib'; return 1; }
    digest=$(java -cp "${jar}" org.jasypt.intf.cli.JasyptStringDigestCLI digest.sh \
        algorithm=SHA-256 saltSizeBytes=16 iterations=100000 input="$1" verbose=0 2>/dev/null \
        | grep -E '^[A-Za-z0-9+/=]+$' | head -n 1)
    [ "${#digest}" -gt 12 ] || { log 'el hash salio vacio'; return 1; }
    printf 'digest1:%s' "${digest}"
}

reset_admin() {
    : "${GEOSERVER_ADMIN_USER:?falta GEOSERVER_ADMIN_USER}"
    : "${GEOSERVER_ADMIN_PASSWORD:?falta GEOSERVER_ADMIN_PASSWORD}"
    users="${DATA_DIR}/security/usergroup/default/users.xml"
    roles="${DATA_DIR}/security/role/default/roles.xml"
    [ -f "${users}" ] || { log "no existe ${users}"; return 1; }
    hash=$(password_hash "${GEOSERVER_ADMIN_PASSWORD}")
    user=$(sed_escape "${GEOSERVER_ADMIN_USER}")
    hash=$(sed_escape "${hash}")
    sed -i "0,/<user /{s|name=\"[^\"]*\"|name=\"${user}\"|; s|password=\"[^\"]*\"|password=\"${hash}\"|}" "${users}"
    if [ -f "${roles}" ]; then
        sed -i "s|username=\"[^\"]*\"|username=\"${user}\"|g" "${roles}"
    fi
    log "admin actualizado: ${GEOSERVER_ADMIN_USER}"
}

seed_security() {
    [ -d "${DATA_DIR}/security" ] && return 0
    [ -n "${GEOSERVER_ADMIN_PASSWORD:-}" ] || return 0
    log 'data_dir sin security/: se siembra el admin'
    cp -R "${WEBAPP}/data/security" "${DATA_DIR}/security"
    GEOSERVER_ADMIN_USER=${GEOSERVER_ADMIN_USER:-admin} reset_admin
}

apply_overlay() {
    [ -d "${OVERLAY_DIR}" ] || return 0
    vars=$(defined_vars)
    count=0
    for src in $(cd "${OVERLAY_DIR}" && find . -type f | sort); do
        rel=${src#./}
        case "${rel}" in
            *.tmpl) dest="${DATA_DIR}/${rel%.tmpl}" ;;
            *) dest="${DATA_DIR}/${rel}" ;;
        esac
        mkdir -p "$(dirname "${dest}")"
        case "${rel}" in
            *.tmpl) envsubst "${vars}" < "${OVERLAY_DIR}/${rel}" > "${dest}" ;;
            *) cp -f "${OVERLAY_DIR}/${rel}" "${dest}" ;;
        esac
        count=$((count + 1))
    done
    log "overlay: ${count} archivo(s) al data_dir"
}

link_fonts() {
    [ -d "${FONTS_DIR}" ] || return 0
    mkdir -p "${HOME}/.local/share"
    ln -sfn "${FONTS_DIR}" "${HOME}/.local/share/fonts"
    fc-cache -f >/dev/null 2>&1 || log 'fc-cache fallo; las fuentes pueden no registrarse'
    log "fuentes: $(find "${FONTS_DIR}" -type f \( -name '*.ttf' -o -name '*.otf' -o -name '*.ttc' \) | wc -l) archivo(s)"
}

render_server_xml() {
    PROXY_ATTRS=''
    if [ -n "${PROXY_HOST:-}" ]; then
        PROXY_ATTRS=" scheme=\"${PROXY_SCHEME:-https}\" secure=\"${PROXY_SECURE:-true}\" proxyName=\"${PROXY_HOST}\" proxyPort=\"${PROXY_PORT:-443}\""
    fi
    HTTP_MAX_HEADER_SIZE=${HTTP_MAX_HEADER_SIZE:-65536}
    export PROXY_ATTRS HTTP_MAX_HEADER_SIZE
    envsubst '${PROXY_ATTRS} ${HTTP_MAX_HEADER_SIZE}' < /opt/geoserver/server.xml.tmpl > "${CATALINA_HOME}/conf/server.xml"
}

deploy_context() {
    rm -f "${CATALINA_HOME}"/conf/Catalina/localhost/*.xml
    printf '<Context docBase="%s"/>\n' "${WEBAPP}" > "${CATALINA_HOME}/conf/Catalina/localhost/${GEOSERVER_CONTEXT}.xml"
}

java_opts() {
    opts="-Xms${JAVA_MIN_MEM} -Xmx${JAVA_MAX_MEM}"
    opts="${opts} -XX:+UseG1GC -XX:SoftRefLRUPolicyMSPerMB=36000"
    opts="${opts} -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=${DATA_DIR}/heapdumps"
    opts="${opts} -Djava.awt.headless=true -Dfile.encoding=UTF-8 -Duser.timezone=${TZ}"
    opts="${opts} -Djavax.servlet.request.encoding=UTF-8 -Djavax.servlet.response.encoding=UTF-8"
    opts="${opts} -Dorg.geotools.referencing.forceXY=true -Djts.overlay=ng"
    opts="${opts} -Dorg.geotools.shapefile.datetime=true -Dorg.geotools.localDateTimeHandling=true"
    opts="${opts} --patch-module java.desktop=${CATALINA_HOME}/lib/marlin.jar"
    opts="${opts} -Dsun.java2d.renderer=org.marlin.pisces.PiscesRenderingEngine"
    opts="${opts} -Dsun.java2d.renderer.useThreadLocal=false -Dsun.java2d.renderer.pixelsize=8192"
    opts="${opts} -DUSE_GLOBAL_RENDERING_POOL=true"
    opts="${opts} -DGEOSERVER_DISABLE_STATIC_WEB_FILES=true -DGEOSERVER_FEATUREINFO_HTML_SCRIPT=SELF"
    opts="${opts} -DGEOSERVER_FORCE_FREEMARKER_ESCAPING=true -DGEOSERVER_FREEMARKER_API_EXPOSED=false"
    opts="${opts} -Dgeoserver.xframe.shouldSetPolicy=true -Djdk.tls.ephemeralDHKeySize=2048"
    opts="${opts} -Dorg.apache.catalina.security.SecurityListener.UMASK=0027"
    opts="${opts} -Dows10.exception.xml.responsetype=application/xml"
    opts="${opts} -Dows11.exception.xml.responsetype=application/xml"
    opts="${opts} --add-exports=java.desktop/sun.awt.image=ALL-UNNAMED"
    for m in java.base/java.lang java.base/java.util java.base/java.lang.reflect java.base/java.text \
        java.desktop/java.awt.font java.desktop/sun.awt.image java.naming/com.sun.jndi.ldap \
        java.desktop/sun.java2d.pipe; do
        opts="${opts} --add-opens=${m}=ALL-UNNAMED"
    done
    if [ -n "${GEOSERVER_CONSOLE_DISABLED:-}" ]; then
        opts="${opts} -DGEOSERVER_CONSOLE_DISABLED=${GEOSERVER_CONSOLE_DISABLED}"
    fi
    printf '%s %s' "${opts}" "${JAVA_EXTRA_OPTS:-}"
}

case "$(basename "$0")" in
    geoserver-reset-admin)
        reset_admin
        exit 0
        ;;
esac

if [ "${1:-}" = 'reset-admin' ]; then
    reset_admin
    exit 0
fi

if [ -n "${JAVA_OPTS:-}" ]; then
    log 'JAVA_OPTS no se usa; pon las opciones extra en JAVA_EXTRA_OPTS'
    exit 1
fi

mkdir -p "${DATA_DIR}/heapdumps"
seed_security
apply_overlay
link_fonts
render_server_xml
deploy_context

CATALINA_OPTS="$(java_opts) ${CATALINA_OPTS:-}"
export CATALINA_OPTS

log "GeoServer en /${GEOSERVER_CONTEXT}, data_dir ${DATA_DIR}, uid $(id -u)"
exec catalina.sh run
