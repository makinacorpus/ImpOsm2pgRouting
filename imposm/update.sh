#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

config_json="$1"

/opt/imposm/imposm run \
    -connection "postgis://$PGCON" \
    -mapping "$MAPPING_YAML" \
    -cachedir "$IMPOSM_CACHE_DIR" \
    -diffdir "$DIFF_DIR" \
    -dbschema-production "import" \
    -config "$config_json"
