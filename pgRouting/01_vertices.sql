CREATE SCHEMA IF NOT EXISTS imposm2pgr;


DROP TABLE IF EXISTS imposm2pgr.osm_ways_junctions;
CREATE TABLE imposm2pgr.osm_ways_junctions (
    id serial PRIMARY KEY,
    point geometry UNIQUE NOT NULL
);

CREATE INDEX osm_ways_junctions_idx_point ON imposm2pgr.osm_ways_junctions USING gist(point);


CREATE OR REPLACE FUNCTION imposm2pgr.ends_geom(linestring geometry) RETURNS SETOF geometry AS $$
DECLARE
    tmp geometry;
BEGIN
    tmp = ST_StartPoint(linestring);
    RETURN NEXT tmp;
    tmp = ST_EndPoint(linestring);
    RETURN NEXT tmp;
    RETURN;
END
$$ LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
RETURNS NULL ON NULL INPUT;


-- Returns the points of a linestring as a collection.
CREATE OR REPLACE FUNCTION imposm2pgr.points_collection(linestring geometry) RETURNS geometry AS $$
    SELECT
        ST_Collect(point)
    FROM
        (
            SELECT (ST_DumpPoints(linestring)).geom
            EXCEPT
            SELECT ST_StartPoint(linestring)
            EXCEPT
            SELECT ST_EndPoint(linestring)
        ) AS t(point)
$$
LANGUAGE SQL IMMUTABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION imposm2pgr.initialize_osm_ways_junctions() RETURNS boolean AS $$
BEGIN
    RAISE NOTICE '% Clear osm_ways_junctions', timeofday()::timestamp;
    DELETE FROM imposm2pgr.osm_ways_junctions;

    RAISE NOTICE '% Insert ends of ways into osm_ways_junctions', timeofday()::timestamp;
    INSERT INTO imposm2pgr.osm_ways_junctions(point)
    SELECT
        imposm2pgr.ends_geom(geometry) AS points
    FROM
        import.osm_ways
    ON CONFLICT (point) DO NOTHING
    ;

    -- From all ways get the points, still grouped by way.
    -- Better performance than just dumping all nodes.
    RAISE NOTICE '% Collect ways points', timeofday()::timestamp;
    -- Does not use TEMP TABLE, so we can plan Parallel Seq Scan on it.
    CREATE UNLOGGED TABLE junction_points AS
    SELECT
        osm_id,
        imposm2pgr.points_collection(geometry) AS points
    FROM
        import.osm_ways
    ;

    CREATE INDEX junction_points_idx_points ON junction_points USING gist(points);

    -- Use spatial index to feet in memory, rather than counting duplicate points.
    RAISE NOTICE '% Insert duplicate points into osm_ways_junctions', timeofday()::timestamp;
    INSERT INTO imposm2pgr.osm_ways_junctions(point)
    SELECT
        (ST_Dump(ST_intersection(p1.points, p2.points))).geom
    FROM
        junction_points AS p1
        JOIN junction_points AS p2 ON
            p1.osm_id > p2.osm_id AND
            ST_intersects(p1.points, p2.points)
    ON CONFLICT (point) DO NOTHING
    ;

    DROP TABLE junction_points;

    RAISE NOTICE '% initialize_osm_ways_junctions done', timeofday()::timestamp;
    RETURN true;
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION imposm2pgr.update_osm_ways_junctions() RETURNS boolean AS $$
BEGIN
    INSERT INTO imposm2pgr.osm_ways_junctions(point)
    SELECT
        imposm2pgr.ends_geom(new_geometry) AS points
    FROM
        old_new_way
    WHERE
        new_geometry IS NOT NULL
    ON CONFLICT (point) DO NOTHING
    ;

    -- Get group of points from new ways and existing ways intersecting new ways.
    CREATE TEMP TABLE junction_points AS
    SELECT
        osm_id,
        imposm2pgr.points_collection(new_geometry) AS points
    FROM
        old_new_way
    WHERE
        new_geometry IS NOT NULL

    UNION

    SELECT
        osm_id,
        imposm2pgr.points_collection(geometry) AS points
    FROM
        import.osm_ways
        JOIN old_new_way ON
            new_geometry && geometry
    WHERE
        new_geometry IS NOT NULL
    ;

    CREATE INDEX junction_points_idx_points ON junction_points USING gist(points);

    INSERT INTO imposm2pgr.osm_ways_junctions(point)
    SELECT
        (ST_Dump(ST_intersection(p1.points, p2.points))).geom
    FROM
        junction_points AS p1
        JOIN junction_points AS p2 ON
            p1.osm_id > p2.osm_id AND
            ST_intersects(p1.points, p2.points)
    ON CONFLICT (point) DO NOTHING
    ;

    DROP TABLE junction_points;

    RETURN true;
END
$$ LANGUAGE plpgsql;
