-- Combinable versions of array_agg to be able run parallelized queries.

CREATE OR REPLACE FUNCTION imposm2pgr.array_agg_append(accu int[], id int) RETURNS int[] AS $$
    SELECT array_append(accu, id);
$$
LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION imposm2pgr.array_agg_combine(accu1 int[], accu2 int[]) RETURNS int[] AS $$
    SELECT accu1 || accu2;
$$
LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE AGGREGATE combinable_array_agg (int) (
    SFUNC = imposm2pgr.array_agg_append,
    COMBINEFUNC = imposm2pgr.array_agg_combine,
    STYPE = int[],
    PARALLEL = SAFE
);


CREATE OR REPLACE FUNCTION imposm2pgr.array_agg_append(accu geometry[], id geometry) RETURNS geometry[] AS $$
    SELECT array_append(accu, id);
$$
LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION imposm2pgr.array_agg_combine(accu1 geometry[], accu2 geometry[]) RETURNS geometry[] AS $$
    SELECT accu1 || accu2;
$$
LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE AGGREGATE combinable_array_agg (geometry) (
    SFUNC = imposm2pgr.array_agg_append,
    COMBINEFUNC = imposm2pgr.array_agg_combine,
    STYPE = geometry[],
    PARALLEL = SAFE
);


CREATE OR REPLACE FUNCTION imposm2pgr.initialize_network() RETURNS boolean AS $$
BEGIN
    RAISE NOTICE '% Split ways as segements', timeofday()::timestamp;
    -- Use an intermediate temps table to allow parallel plan not permited by network_add().
    CREATE TEMP TABLE temp_network AS
    SELECT
        osm_id,
        geometry,
        tags,
        ids[array_position(points, ST_StartPoint(geometry))] AS source_id,
        ids[array_position(points, ST_EndPoint(geometry))] AS target_id
    FROM (
        SELECT
            osm_id,
            combinable_array_agg(osm_ways_junctions.id) AS ids,
            combinable_array_agg(osm_ways_junctions.point) AS points,
            (ST_Dump(
                ST_Split(geometry, ST_Collect(combinable_array_agg(osm_ways_junctions.point)))
            )).geom AS geometry,
            tags
        FROM
            import.osm_ways
            JOIN imposm2pgr.osm_ways_junctions ON
                osm_ways_junctions.point && osm_ways.geometry
        GROUP BY
            osm_id,
            geometry,
            tags
    ) AS t
    ;

    RAISE NOTICE '% Insert segements into network', timeofday()::timestamp;
    PERFORM
        network_add(
            osm_id,
            geometry,
            tags,
            source_id,
            target_id
        )
    FROM
        temp_network
    ;

    DROP TABLE temp_network;

    RAISE NOTICE '% initialize_network done', timeofday()::timestamp;
    RETURN true;
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION imposm2pgr.update_network() RETURNS boolean AS $$
BEGIN
    -- DELETE FROM network WHERE
    PERFORM
        network_delete(old_new_way.osm_id)
    FROM
        old_new_way
    WHERE
        old_new_way.old_geometry IS NOT NULL
    ;

    -- INSERT INTO network
    PERFORM
        network_add(
            osm_id,
            geometry,
            tags,
            ids[array_position(points, ST_StartPoint(geometry))],
            ids[array_position(points, ST_EndPoint(geometry))]
        )
    FROM (
        SELECT
            osm_id,
            array_agg(osm_ways_junctions.id) AS ids,
            array_agg(osm_ways_junctions.point) AS points,
            (ST_Dump(ST_Split(new_geometry, ST_Collect(osm_ways_junctions.point)))).geom AS geometry,
            new_tags AS tags
        FROM
            old_new_way
            JOIN imposm2pgr.osm_ways_junctions ON
                osm_ways_junctions.point && old_new_way.new_geometry
        WHERE
            new_geometry IS NOT NULL
        GROUP BY
            osm_id,
            new_geometry,
            tags
    ) AS t
    ;

    RETURN true;
END
$$ LANGUAGE plpgsql;
