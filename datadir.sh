#!/bin/sh
set -eu

DATA_DIR=${GEOSERVER_DATA_DIR}
EXCLUDE=${BACKUP_EXCLUDE:-gwc heapdumps}
STAGING="${DATA_DIR}/.sacbe-restore"

log() {
    printf 'sacbe: %s\n' "$*" >&2
}

fail() {
    log "$*"
    exit 1
}

geoserver_running() {
    for f in /proc/[0-9]*/cmdline; do
        tr '\0' ' ' < "${f}" 2>/dev/null | grep -q 'org.apache.catalina.startup.Bootstrap' && return 0
    done
    return 1
}

excluded() {
    for e in ${EXCLUDE}; do
        [ "$1" = "${e}" ] && return 0
    done
    return 1
}

backup() {
    [ -t 1 ] && fail 'la salida es la terminal; redirige a un archivo: geoserver-backup > respaldo.tar.gz'
    [ -f "${DATA_DIR}/global.xml" ] || fail "${DATA_DIR} no parece un data_dir de GeoServer (falta global.xml)"
    set -- --numeric-owner --warning=no-file-changed --exclude=./.sacbe-restore
    for e in ${EXCLUDE}; do
        set -- "$@" "--exclude=./${e}"
    done
    rc=0
    tar -C "${DATA_DIR}" -czf - "$@" . || rc=$?
    [ "${rc}" -le 1 ] || fail "tar termino con codigo ${rc}"
    [ "${rc}" -eq 0 ] || log 'algunos archivos cambiaron mientras se leian; el respaldo se escribio igual'
    log "respaldo de ${DATA_DIR} listo (sin: ${EXCLUDE})"
}

restore() {
    [ -t 0 ] && fail 'pasa el respaldo por stdin: geoserver-restore < respaldo.tar.gz'
    geoserver_running && fail 'GeoServer esta corriendo en este contenedor; detenlo y restaura con un contenedor de un solo uso'
    rm -rf "${STAGING}"
    mkdir -p "${STAGING}"
    tar -xzpf - -C "${STAGING}" || { rm -rf "${STAGING}"; fail 'no se pudo leer el respaldo'; }
    src="${STAGING}"
    if [ ! -e "${src}/global.xml" ] && [ -f "${src}/data_dir/global.xml" ]; then
        src="${src}/data_dir"
    fi
    if [ ! -f "${src}/global.xml" ]; then
        rm -rf "${STAGING}"
        fail 'el respaldo no trae global.xml; no se toco el data_dir'
    fi
    for entry in "${DATA_DIR}"/* "${DATA_DIR}"/.[!.]*; do
        [ -e "${entry}" ] || continue
        name=$(basename "${entry}")
        [ "${name}" = '.sacbe-restore' ] && continue
        excluded "${name}" && continue
        rm -rf "${entry}"
    done
    for entry in "${src}"/* "${src}"/.[!.]*; do
        [ -e "${entry}" ] || continue
        name=$(basename "${entry}")
        [ "${name}" = 'data_dir' ] && [ "${src}" = "${STAGING}" ] && continue
        excluded "${name}" && [ -e "${DATA_DIR}/${name}" ] && continue
        mv "${entry}" "${DATA_DIR}/"
    done
    rm -rf "${STAGING}"
    log "data_dir restaurado en ${DATA_DIR} (se conservaron: ${EXCLUDE})"
}

case "$(basename "$0")" in
    geoserver-backup) backup ;;
    geoserver-restore) restore ;;
    *) fail 'uso: geoserver-backup > archivo.tar.gz | geoserver-restore < archivo.tar.gz' ;;
esac
