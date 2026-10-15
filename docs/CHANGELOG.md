# Changelog

Todos los cambios notables de este proyecto se documentan aquí. El formato sigue
[Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Las etiquetas de la imagen son
`<versión-de-GeoServer>-<revisión>`.

## [3.0.1-2] - 2026-10-15

### Agregado

- `geoserver-backup`: respaldo del data_dir a stdout con dueños numéricos, sin los directorios de
  `BACKUP_EXCLUDE` (por defecto `gwc heapdumps`), mientras GeoServer corre.
- `geoserver-restore`: restaura desde stdin en un contenedor de un solo uso, con todo como uid 2000 y
  sin `chown`. Conserva los directorios excluidos, acepta archivos con `data_dir/` al frente, se niega
  junto a un GeoServer vivo y no toca nada si el archivo no trae `global.xml`.
- El smoke test comprueba que `geoserver-backup` produce un archivo con `global.xml`.

## [3.0.1-1] - 2026-10-13

### Agregado

- Imagen de GeoServer 3.0.1 sobre `tomcat:11.0.27-jdk21-temurin-noble` fijada por digest, con el
  WAR oficial y las extensiones control-flow, wps, vectortiles, geopkg-output y libjpeg-turbo,
  verificadas por sha256.
- Usuario `geoserveruser` (uid y gid 2000) desde el build: el arranque no hace `chown`.
- `libturbojpeg` enlazado en `native-jni-lib`, así el encoder JPEG nativo de libjpeg-turbo carga.
- Entrypoint POSIX: contexto por `GEOSERVER_CONTEXT`, memoria por `JAVA_MIN_MEM` y `JAVA_MAX_MEM`,
  opciones extra por `JAVA_EXTRA_OPTS`, proxy del connector por `PROXY_*`.
- Overlay en `/etc/geoserver/overlay` copiado al data_dir en cada arranque, con plantillas `*.tmpl`
  renderizadas por `envsubst`.
- Fuentes desde `/etc/geoserver/fonts` registradas en fontconfig.
- Siembra del admin en un data_dir vacío y comando `geoserver-reset-admin`.
- Workflow que construye, prueba, escanea y publica en `ghcr.io/ghegar/sacbe` al etiquetar `v*`.
- `.trivyignore` con las cuatro CVE CRITICAL que GeoServer 3.0.1 aún arrastra (bouncycastle, freemarker y dos de spring-webmvc), con expiración al 2027-01-13.

### Eliminado

- `gs-web-demo`, `gs-sec-jdbc` y `gs-sec-ldap` con sus páginas web, que vienen en el WAR.
