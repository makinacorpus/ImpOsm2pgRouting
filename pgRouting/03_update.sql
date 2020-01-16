-- Track changes on "osm_ways"

DROP TABLE IF EXISTS imposm2pgr.osm_ways_diff;
CREATE TABLE IF NOT EXISTS imposm2pgr.osm_ways_diff(
    id serial primary key,
    osm_id bigint,
    old_geometry geometry(Geometry,3857),
    new_geometry geometry(Geometry,3857),
    new_tags hstore
);

CREATE OR REPLACE FUNCTION imposm2pgr.proc_osm_ways_changes_store() RETURNS trigger AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        INSERT INTO imposm2pgr.osm_ways_diff(osm_id, old_geometry, new_geometry, new_tags)
            VALUES (OLD.osm_id, OLD.geometry, NULL::geometry, NULL::hstore);
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO imposm2pgr.osm_ways_diff(osm_id, old_geometry, new_geometry, new_tags)
            VALUES (NEW.osm_id, OLD.geometry, NEW.geometry, NEW.tags);
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO imposm2pgr.osm_ways_diff(osm_id, old_geometry, new_geometry, new_tags)
            VALUES (NEW.osm_id, NULL::geometry, NEW.geometry, NEW.tags);
    END IF;
    RETURN NULL;
END;
$$ language plpgsql;

CREATE TRIGGER trigger_osm_ways_changes
    AFTER INSERT OR UPDATE OR DELETE ON import.osm_ways
    FOR EACH ROW
    EXECUTE PROCEDURE imposm2pgr.proc_osm_ways_changes_store();


-- Flag changes

DROP TABLE IF EXISTS imposm2pgr.updates;
CREATE TABLE IF NOT EXISTS imposm2pgr.updates(id serial primary key, t text, unique (t));

CREATE OR REPLACE FUNCTION imposm2pgr.proc_flag_update() RETURNS trigger AS $$
BEGIN
    INSERT INTO imposm2pgr.updates(t) VALUES ('y') ON CONFLICT(t) DO NOTHING;
    RETURN null;
END;
$$ language plpgsql;

CREATE TRIGGER trigger_flag
    AFTER INSERT ON imposm2pgr.osm_ways_diff
    FOR EACH STATEMENT
    EXECUTE PROCEDURE imposm2pgr.proc_flag_update();


-- Apply changes to "network"

CREATE OR REPLACE FUNCTION imposm2pgr.refresh() RETURNS void AS $$
BEGIN
    -- Compact the change history to keep only the first and last version
    CREATE TEMP TABLE old_new_way AS
    SELECT DISTINCT ON (osm_id)
        osm_id,
        old_geometry,
        new_geometry,
        new_tags
    FROM (
        SELECT
            osm_id,
            first_value(old_geometry) OVER (PARTITION BY osm_id ORDER BY id) AS old_geometry,
            last_value(new_geometry) OVER (PARTITION BY osm_id ORDER BY id) AS new_geometry,
            last_value(new_tags) OVER (PARTITION BY osm_id ORDER BY id) AS new_tags
        FROM
            imposm2pgr.osm_ways_diff
    ) AS t
    ;

    PERFORM imposm2pgr.update_osm_ways_junctions();
    PERFORM imposm2pgr.update_network();

    DELETE FROM imposm2pgr.osm_ways_diff;
    DELETE FROM imposm2pgr.updates;
    DROP TABLE old_new_way CASCADE;
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION imposm2pgr.proc_refresh() RETURNS trigger AS
  $BODY$
  BEGIN
    RAISE NOTICE '% Update pgRouting network', timeofday()::timestamp;
    PERFORM imposm2pgr.refresh();
    RETURN null;
  END;
  $BODY$
language plpgsql;

CREATE CONSTRAINT TRIGGER trigger_refresh
    AFTER INSERT ON imposm2pgr.updates
    INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE PROCEDURE imposm2pgr.proc_refresh();
