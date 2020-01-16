DROP TABLE IF EXISTS network CASCADE;
CREATE TABLE IF NOT EXISTS network (
    id serial PRIMARY KEY,
    osm_id bigint NOT NULL, -- required field, for update
    source_vertex_id int, --required field, for routing
    target_vertex_id int, -- required field, for routing
    geometry geometry(LineString,3857) NOT NULL, -- Advised, for display
    cost float,
    highway varchar,
    name varchar
);

CREATE INDEX network_idx_geometry ON network USING gist(geometry);
CREATE INDEX network_idx_osm_id ON network(osm_id);

-- How to add a segement to the network
CREATE OR REPLACE FUNCTION network_add(
    _osm_id bigint, -- OpenStreetMap way id, not unique as way are splited into segements
    _geometry geometry, -- Segement geometry, Linestring
    _tags hstore, -- OpenStreetMap tags as imported by imposm
    _source_vertex_id int, -- computed vertex id
    _target_vertex_id int -- computed vertex id
) RETURNS void AS $$
BEGIN
    INSERT INTO network(osm_id, source_vertex_id, target_vertex_id, geometry, cost, highway, name)
    VALUES (
        _osm_id,
        _source_vertex_id,
        _target_vertex_id,
        _geometry,
        cost(_geometry, _tags),
        _tags->'highway',
        _tags->'name'
    );
END
$$ LANGUAGE plpgsql;

-- How to remove a segment from the network
CREATE OR REPLACE FUNCTION network_delete(
    _osm_id bigint -- OpenStreetMap way id, not unique as way are splited into segements
) RETURNS void AS $$
BEGIN
    DELETE FROM network
    WHERE osm_id = _osm_id;
END
$$ LANGUAGE plpgsql;


-- How to compute staticly the segement cost
CREATE OR REPLACE FUNCTION cost(geometry geometry, tags hstore) RETURNS float AS $$
BEGIN
    RETURN ST_Length(geometry);
END
$$ LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
RETURNS NULL ON NULL INPUT;

-- Create the network
TRUNCATE network;
SET max_parallel_workers_per_gather TO 8;
SELECT imposm2pgr.initialize_osm_ways_junctions();
SELECT imposm2pgr.initialize_network();
