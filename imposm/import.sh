#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset

: "${DIFF_MODE:=true}"

pbf_file="$1"
config_json="$2"
diff_flag=""
if [ "$DIFF_MODE" = true ]; then
    diff_flag="-diff"
    echo "Importing in diff mode"
else
    echo "Importing in normal mode"
fi

/opt/imposm/imposm import \
    -connection "postgis://$PGCON" \
    -mapping "$MAPPING_YAML" \
    -overwritecache \
    -diffdir "$DIFF_DIR" \
    -cachedir "$IMPOSM_CACHE_DIR" \
    -read "$pbf_file" \
    -write \
    $diff_flag \
    -config "$config_json"
