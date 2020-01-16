# ImpOsm2pgRouting

ImpOsm2pgRouting is set of SQL scripts and a database layout to import [OpenStreetMap](https://wiki.openstreetmap.org/) network and make it available to [pgRouting](https://pgrouting.org/). It takes care of data updates.

ImpOsm2pgRouting imports OSM data using [Imposm](https://imposm.org/docs/imposm3/latest/). Then it segmentizes the ways and computes the vertices. It continuously updates the database from OSM update, using imposm and triggers. The storage of the network and pgRouting call is still up to you.


## Prerequisites: Have a Postgres database

You must provide a Postgres database, enabled the extensions `postgis` and `hstore`. ImpOsm2pgRouting does not require it, but will also need the extension `pgrouting`.

```sql
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgrouting;
CREATE EXTENSION IF NOT EXISTS hstore;
```

Copy `env.template` as `env` and set your Postgres credentials.

## Your graph Network configuration

Use the file `10_network.template.sql` to customise you own `network` table, or just copy it at `10_network.sql`.

Only functions `network_add()` and `network_delete()` are required. There are the callback functions to `insert` or `delete` segments to your `network` table. OpenStreetMap edition are interpreted as deletion plus insertion.

```sql
FUNCTION network_add(
    _osm_id bigint, -- OpenStreetMap way id, not unique as way are splited into segments
    _geometry geometry, -- Segment geometry, Linestring
    _tags hstore, -- OpenStreetMap tags as imported by imposm
    _source_vertex_id int, -- computed vertex id
    _target_vertex_id int -- computed vertex id
) RETURNS boolean
```

```sql
FUNCTION network_delete(
    _osm_id bigint -- OpenStreetMap way id, not unique as way are splited into segments
) RETURNS void
```

* `_osm_id` is not unique, OpenStreetMap ways are segment by junction, have to have yours own segment ids,
* `_tags` are OpenStreetMap tags imported by imposm, you can optionally narrow tags set at this step. Tags could be used to extract attributes, like street name `_tags->'name'` or a the segment cost: eg. when `_tags->'highway' = 'motorway'` then set cost to `ST_Lenght(geometry) / 130`.
* `_source_vertex_id` and `_target_vertex_id`, store as is an pass to pgRouting.

The minimal `network` table is
```sql
CREATE TABLE network (
    id serial PRIMARY KEY,
    osm_id bigint NOT NULL, -- required field, for update
    source_vertex_id int, --required field, for routing
    target_vertex_id int, -- required field, for routing
    geometry geometry NOT NULL -- Advised, for display
);
```
But add any attributes or store its as your like, it is your table. The only requirement are on function `network_add()` and `network_delete()`.


## Setup

You can setup manually by installing imposm your self, or by using Docker (the easy way).

### Manual setup

### Prepare OpenStreetMap data to import

Download an extract eg. from [Geofabrik](http://download.geofabrik.de/) (daily update) or from [OpenStreetMap-France](http://download.openstreetmap.fr/) (minutely update).

From Geofabrik:
```
wget http://download.geofabrik.de/europe/andorra-latest.osm.pbf -P import
echo '{"replication_url": "http://download.geofabrik.de/europe/andorra-updates/", "replication_interval": "24h"}' > import/config-andorra.json
```

From OpenStreetMap-France:
```
wget http://download.openstreetmap.fr/extracts/north-america/bermuda-latest.osm.pbf -p import
echo '{"replication_url": "http://download.openstreetmap.fr/replication/north-america/bermuda/minute/", "replication_interval": "1m"}' > import/config-bermuda.json
```

#### Imposm Import

Import the data from the pbf extract into the table `import.osm_ways`. How to import OpenStreetMap is defined in the mapping file.
```
imposm import -mapping mapping/routing.yaml -read import/bermuda-latest.osm.pbf -overwritecache -diffdir diff -cachedir cache -write -connection 'postgis://user@localhost' -config import/bermuda-latest.osm.pbf.json
```

#### Load ImpOsm2pgRouting SQL scripts

Setup internal tables, functions and triggers into schema `imposm2pgr`.
```
psql < pgRouting/00_init.sql
psql < pgRouting/01_vertices.sql
psql < pgRouting/02_edge.sql
psql < pgRouting/03_update.sql
```

Once function `network_add()` and `network_delete()` and underlying `network` table are defined fill it with:
```sql
SELECT imposm2pgr.initialize_osm_ways_junctions();
SELECT imposm2pgr.initialize_network();
```

You are ready. You can run pgRouting over your `network` table.

#### Update the data

Run imposm to continuously update the `import.osm_ways` table when fresh update are available. The triggers will update the `network` table using `network_add()` and `network_delete()` functions.

```
imposm run -mapping mapping/routing.yaml -diffdir diff -cachedir cache -connection 'postgis://user@localhost' -config import/bermuda-latest.osm.pbf.json
```

### Docker

Before process install Docker and docker-compose.

Build Docker Image
```
docker-compose build
```

Also need a postgres pgRouting data base before starting? Get one with, else skip this step:
```
docker-compose -f docker-compose-pgrouting.yaml up -d pgrouting
# Wait few second for data creation and startup
docker-compose -f docker-compose-pgrouting.yaml exec --user postgres pgrouting psql postgres postgres -c "
    CREATE EXTENSION IF NOT EXISTS postgis;
    CREATE EXTENSION IF NOT EXISTS pgrouting;
    CREATE EXTENSION IF NOT EXISTS hstore;
"
```

Import OpenStreetMap into database:
```
docker-compose run --rm imposm2pgrouting ./import geofabrik europe/monaco
```

You are ready to request your `network` table with pgRouting.

Keep up to date:
```
docker-compose run --rm imposm2pgrouting ./update
```


## Benchmark

Statistics for France OpenStreetMap extract.

| Project | Import | Database Size | Update support |
|-|-:|-:|-:|
| ImpOsm2pgRouting | 1h54 | (SQL) 9.3 GB | ✓ |
| osm2pgrouting | n/a | (SQL) n/a | - |
| OSRM (CH) | 0h59 | (binary) 7.5 GB | - |
| Graphhoper (CH) | 0h35 | (binary) 1.0 GB | - |
| Valhalla | 0h58 | (binary) 2.5 GB | - |

Notes:

* ImpOsm2pgRouting / pgRouting: offer updatable graph network with customizable cost, runtime route request slow
* [OSRM](https://github.com/Project-OSRM/osrm-backend): offer non update one transport mode dedicated graph, runtime route request fast
* [Graphhoper](https://github.com/graphhopper/graphhopper): offer non update one transport mode dedicated graph runtime route request fast (also offer non updatable graph network with customizable cost, runtime route request at moderate speed)
* [Valhalla](https://github.com/valhalla/valhalla): offer non updatable graph network with customizable cost, runtime route request at moderate speed


## Project

[osm2pgrouting](https://github.com/pgRouting/osm2pgrouting) is an alternative to this project.

This project is under BSD 3-Clause License, Copyright (c) 2020, Makina Corpus, All rights reserved.
