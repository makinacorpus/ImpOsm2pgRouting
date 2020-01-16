#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

PROVIDER=$1
AREA=$2

case $PROVIDER in
  geofabrik)
    EXTRACT="http://download.geofabrik.de/${AREA}-latest.osm.pbf"
    EXTRACT_UPDATE="http://download.geofabrik.de/${AREA}-updates/"
    DELAY=24h
  ;;
  osmfr)
    EXTRACT="http://download.openstreetmap.fr/extracts/${AREA}-latest.osm.pbf"
    EXTRACT_UPDATE="http://download.openstreetmap.fr/replication/${AREA}/minute/"
    DELAY=1m
  ;;
  *)
    echo "Valid providers are 'geofabrik' and 'osmfr'"; exit 1
esac


BASE=$(basename "${EXTRACT##*/}")
>&2 echo "Download ${EXTRACT}"
wget -N "${EXTRACT}" -P /import
>&2 echo "Write config /import/${BASE}.json"
echo "{\"replication_url\": \"${EXTRACT_UPDATE}\", \"replication_interval\": \"${DELAY}\"}" > "/import/${BASE}.json"

echo "${BASE}"
