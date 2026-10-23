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

reset_case() {
    docker run --rm -i -e GEOSERVER_DATA_DIR=/tmp/dd -e GEOSERVER_ADMIN_USER=jefe \
        -e GEOSERVER_ADMIN_PASSWORD=nueva --entrypoint sh "${IMAGE}" -eu >/dev/null 2>&1
}

check 'reset-admin solo cambia al admin, que no es el primero' reset_case <<'EOF'
u=/tmp/dd/security/usergroup/default
r=/tmp/dd/security/role/default
mkdir -p "$u" "$r"
cat > "$u/users.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<userRegistry version="1.0" xmlns="http://www.geoserver.org/security/users">
    <users>
        <user enabled="true" name="ana" password="plain:a"/>
        <user enabled="true" name="jefe" password="plain:viejo"/>
        <user enabled="true" name="beto" password="plain:b"/>
    </users>
    <groups/>
</userRegistry>
XML
cat > "$r/roles.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<roleRegistry version="1.0" xmlns="http://www.geoserver.org/security/roles">
    <roleList>
        <role id="ADMIN"/>
        <role id="GROUP_ADMIN"/>
    </roleList>
    <userList>
        <userRoles username="ana">
            <roleRef roleID="ADMIN"/>
        </userRoles>
        <userRoles username="jefe">
            <roleRef roleID="ADMIN"/>
        </userRoles>
    </userList>
    <groupList/>
</roleRegistry>
XML
cp "$r/roles.xml" /tmp/roles.orig
sacbe-entrypoint reset-admin
[ "$(grep -c '<user ' "$u/users.xml")" = 3 ]
grep -q '<user enabled="true" name="ana" password="plain:a"/>' "$u/users.xml"
grep -q '<user enabled="true" name="beto" password="plain:b"/>' "$u/users.xml"
grep -q '<user enabled="true" name="jefe" password="digest1:' "$u/users.xml"
cmp -s "$r/roles.xml" /tmp/roles.orig
EOF

check 'reset-admin agrega al admin que falta sin duplicar roles' reset_case <<'EOF'
u=/tmp/dd/security/usergroup/default
r=/tmp/dd/security/role/default
mkdir -p "$u" "$r"
cat > "$u/users.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<userRegistry version="1.0" xmlns="http://www.geoserver.org/security/users">
    <users>
        <user enabled="true" name="ana" password="plain:a"/>
        <user enabled="true" name="beto" password="plain:b"/>
        <user enabled="true" name="carla" password="plain:c"/>
    </users>
    <groups/>
</userRegistry>
XML
cat > "$r/roles.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<roleRegistry version="1.0" xmlns="http://www.geoserver.org/security/roles">
    <roleList>
        <role id="ADMIN"/>
        <role id="GROUP_ADMIN"/>
    </roleList>
    <userList>
        <userRoles username="ana">
            <roleRef roleID="ADMIN"/>
        </userRoles>
    </userList>
    <groupList/>
</roleRegistry>
XML
sacbe-entrypoint reset-admin
sacbe-entrypoint reset-admin
[ "$(grep -c '<user ' "$u/users.xml")" = 4 ]
[ "$(grep -c 'name="jefe" password="digest1:' "$u/users.xml")" = 1 ]
grep -q '<user enabled="true" name="ana" password="plain:a"/>' "$u/users.xml"
[ "$(grep -c '<userRoles ' "$r/roles.xml")" = 2 ]
[ "$(grep -c 'username="ana"' "$r/roles.xml")" = 1 ]
[ "$(grep -c '<role id=' "$r/roles.xml")" = 2 ]
[ "$(grep -c 'roleID="ADMIN"' "$r/roles.xml")" = 2 ]
[ "$(grep -c 'roleID="GROUP_ADMIN"' "$r/roles.xml")" = 1 ]
sed -n '/username="jefe"/,/<\/userRoles>/p' "$r/roles.xml" | grep -q 'roleID="GROUP_ADMIN"'
EOF

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
check 'Layer Preview' sh -c "curl -fsS -o /dev/null --max-time 60 '${BASE}/web/wicket/bookmarkable/org.geoserver.web.demo.MapPreviewPage'"
check 'sin chown en el log' sh -c "! docker logs ${NAME} 2>&1 | grep -qi chown"

exit "${FAILED}"
