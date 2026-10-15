#!/bin/sh
set -eu

IMAGE=${1:?uso: smoke.sh <imagen>}
NAME=sacbe-smoke-$$
PORT=${SMOKE_PORT:-18080}
CTX=geoserver
BASE="http://localhost:${PORT}/${CTX}"
FAILED=0

cleanup() {
    docker rm -f "${NAME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

check() {
    label=$1
    shift
    if "$@"; then
        printf 'ok    %s\n' "${label}"
    else
        printf 'FALLA %s\n' "${label}"
        FAILED=1
    fi
}

body_has() {
    curl -fsS --max-time 60 "$1" 2>/dev/null | grep -q "$2"
}

body_lacks() {
    ! curl -fsS --max-time 60 "$1" 2>/dev/null | grep -q "$2"
}

content_type() {
    curl -fsS --max-time 60 -o /dev/null -w '%{content_type}' "$1" | grep -q "$2"
}

docker run -d --name "${NAME}" -p "${PORT}:8080" \
    -e GEOSERVER_ADMIN_PASSWORD=smoke-test -e GEOSERVER_CONTEXT="${CTX}" "${IMAGE}" >/dev/null

tries=0
until curl -fsI --max-time 5 "${BASE}/web/" >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "${tries}" -ge 60 ]; then
        docker logs --tail 60 "${NAME}"
        echo 'GeoServer no arranco en 300 s'
        exit 1
    fi
    sleep 5
done

check 'corre como uid 2000' sh -c "[ \"\$(docker exec ${NAME} id -u)\" = 2000 ]"
check 'WMS GetCapabilities' body_has "${BASE}/ows?service=WMS&version=1.3.0&request=GetCapabilities" 'WMS_Capabilities'
check 'WFS GetCapabilities' body_has "${BASE}/ows?service=WFS&version=2.0.0&request=GetCapabilities" 'WFS_Capabilities'
check 'WFS ofrece geopackage' body_has "${BASE}/ows?service=WFS&version=2.0.0&request=GetCapabilities" 'geopackage'
check 'WCS GetCapabilities' body_has "${BASE}/ows?service=WCS&version=2.0.1&request=GetCapabilities" 'Capabilities'
check 'WPS GetCapabilities' body_has "${BASE}/ows?service=WPS&version=1.0.0&request=GetCapabilities" 'wps:Capabilities'
check 'WPS tiene gs:Aggregate' body_has "${BASE}/ows?service=WPS&version=1.0.0&request=GetCapabilities" 'gs:Aggregate'
check 'WPS sin gs:Download' body_lacks "${BASE}/ows?service=WPS&version=1.0.0&request=GetCapabilities" 'gs:Download'
check 'WMS ofrece MVT' body_has "${BASE}/ows?service=WMS&version=1.3.0&request=GetCapabilities" 'application/vnd.mapbox-vector-tile'
check 'WMTS GetCapabilities' body_has "${BASE}/gwc/service/wmts?REQUEST=GetCapabilities" 'Capabilities'
check 'REST con admin sembrado' content_type "http://admin:smoke-test@localhost:${PORT}/${CTX}/rest/about/version.json" 'json'
check 'geoserver-backup con global.xml' sh -c "docker exec ${NAME} geoserver-backup 2>/dev/null | tar -tzf - | grep -qx './global.xml'"
check 'sin chown en el log' sh -c "! docker logs ${NAME} 2>&1 | grep -qi chown"

exit "${FAILED}"
