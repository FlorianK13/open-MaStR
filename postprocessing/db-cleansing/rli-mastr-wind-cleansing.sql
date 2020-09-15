/*
RLI MaStR Wind Cleansing

Create a copy
Create the geom from coordinates
Check if geom is inside Germany
Reset geom if outside of Germany (and not Wind Offshore)
Allocate to centre of PLZ-area

__copyright__   = "© Reiner Lemoine Institut"
__license__ = "Creative Commons Zero v1.0 Universal (CC0-1.0)"
__url__     = "https://creativecommons.org/publicdomain/zero/1.0/"
__author__  = "Ludwig Hülk"
*/


-- Create a copy
DROP TABLE IF EXISTS model_draft.bnetza_mastr_rli_v2_5_5_wind_clean CASCADE;
CREATE TABLE         model_draft.bnetza_mastr_rli_v2_5_5_wind_clean AS
    SELECT  * 
    FROM    model_draft.bnetza_mastr_rli_v2_5_5_wind
    ORDER BY id;

ALTER TABLE model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    ADD PRIMARY KEY (id),
    ADD COLUMN lat double precision,
    ADD COLUMN lon double precision,
    ADD COLUMN geom_wgs geometry(Point,4326),
    ADD COLUMN geom geometry(Point,3035),
    ADD COLUMN tags jsonb,
    ADD COLUMN comment text;

ALTER TABLE model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    ALTER COLUMN "Bruttoleistung" TYPE double precision USING "Bruttoleistung"::double precision,
    ALTER COLUMN "Bruttoleistung_w" TYPE double precision USING "Bruttoleistung_w"::double precision,
    ALTER COLUMN "Nettonennleistung" TYPE double precision USING "Nettonennleistung"::double precision,
    ALTER COLUMN "Nabenhoehe" TYPE double precision USING "Nabenhoehe"::double precision,
    ALTER COLUMN "Rotordurchmesser" TYPE double precision USING "Rotordurchmesser"::double precision,
    ALTER COLUMN "Wassertiefe" TYPE double precision USING "Wassertiefe"::double precision,
    ALTER COLUMN "Kuestenentfernung" TYPE double precision USING "Kuestenentfernung"::double precision
    ;

CREATE INDEX bnetza_mastr_rli_v2_5_5_wind_clean_geom_idx
    ON model_draft.bnetza_mastr_rli_v2_5_5_wind_clean USING gist (geom);

CREATE INDEX bnetza_mastr_rli_v2_5_5_wind_clean_geom_wgs_idx
    ON model_draft.bnetza_mastr_rli_v2_5_5_wind_clean USING gist (geom_wgs);

ALTER TABLE model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    OWNER to oeuser;

-- Tags: Onshore and offshore
UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET tags = '{"processed":true}';


-- Tags: Onshore and offshore
UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET tags = tags || '{"location":"onshore"}'
    WHERE   "Lage" = 'WindAnLand';

UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET tags = tags || '{"location":"offshore"}'
    WHERE   "Lage" = 'WindAufSee';

UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET tags = tags || '{"location":"na"}'
    WHERE   "Lage" IS NULL;


-- Tags: Migrierte Einheiten
UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET tags = tags || '{"einheit":"SME"}'
    WHERE LEFT("EinheitMastrNummer", 3) = 'SME';

UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET tags = tags || '{"einheit":"SEE"}'
    WHERE LEFT("EinheitMastrNummer", 3) = 'SEE';


-- Tags: Gematchte Einheiten
UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET tags = tags || '{"flag":"A"}'
    WHERE "StatisikFlag_w" = 'A';

UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET tags = tags || '{"flag":"B"}'
    WHERE "StatisikFlag_w" = 'B';


-- Tags: Betriebsstatus
UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET tags = tags || '{"status":"operating"}'
    WHERE "EinheitBetriebsstatus" = 'InBetrieb';

UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET tags = tags || '{"status":"planned"}'
    WHERE "EinheitBetriebsstatus" = 'InPlanung';

UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET tags = tags || '{"status":"shutdown"}'
    WHERE   "EinheitBetriebsstatus" = 'DauerhaftStillgelegt' OR 
            "EinheitBetriebsstatus" = 'VoruebergehendStillgelegt';


-- Create the geom from coordinates
UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET lat =      CAST(
                        COALESCE(
                            NULLIF(
                                regexp_replace("Breitengrad", '[^-0-9.]+', '', 'g'), 
                                ''),
                            NULL) 
                       AS numeric),
       lon =      CAST(
                        COALESCE(
                            NULLIF(
                                regexp_replace("Laengengrad", '[^-0-9.]+', '', 'g'), 
                                ''),
                            NULL) 
                       AS numeric)
                       ;

-- Make geom
UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET geom_wgs = ST_TRANSFORM(ST_SetSRID(ST_Point(
                                                lon,
                                                lat)
                                                ,4326),4326),
        tags = tags || '{"geom":true}'
    WHERE   lon IS NOT NULL AND
            lat IS NOT NULL;

-- Tags: geom
UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET tags = tags || '{"geom":false}'
    WHERE   geom_wgs IS NULL;


-- Check if geom is inside Germany (vg250)
UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean AS t1
    SET     comment =  COALESCE(comment, '') || 'onshore_inside; ',
            tags = tags || '{"inside_germany":true}'
    FROM    (
        SELECT  m.id AS id
        FROM    boundaries.bkg_vg250_1_sta_union_mview AS vg,
                model_draft.bnetza_mastr_rli_v2_5_5_wind_clean AS m
        WHERE   tags ->> 'location' = 'onshore' AND
                ST_TRANSFORM(vg.geom, 4326) && m.geom_wgs AND
                ST_CONTAINS(ST_TRANSFORM(vg.geom, 4326),m.geom_wgs)
        ) AS t2
    WHERE   t1.id = t2.id;


-- Tags: geom outside Germany
UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET tags = tags || '{"inside_germany":false}'
    WHERE NOT tags ? 'inside_germany';


-- Remove geom onshore outside
UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET     geom_wgs =  NULL,
            tags = tags || '{"geom":false, "geom_remove":true}'
    WHERE   (tags->>'geom')::boolean IS true AND
    tags ->> 'location' = 'onshore'  AND
    (tags->>'inside_germany')::boolean IS false;

-- Transform geom
UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET     geom =  ST_TRANSFORM(geom_wgs, 3035)
    WHERE   geom_wgs IS NOT NULL;


-- Make geom from PLZ (Centroid)
UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean AS t1
    SET     geom = t2.geom,
            comment =  COALESCE(comment, '') || 'onshore_fix_plz; ',
            tags = tags || '{"geom":true, "inside_germany":true,"geom_guess":"plz"}'
    FROM    (SELECT plz,
            ST_CENTROID(ST_TRANSFORM(geom,3035)) ::geometry(Point,3035) AS geom
            FROM    boundaries.osm_postcode
            WHERE   stellen = 5
            ORDER BY plz
            )AS t2
    WHERE   t1."Postleitzahl" = t2.plz AND
            t1.geom IS NULL AND
            t1.tags ->> 'location' = 'onshore';


-- Make geom from Standort (Extract PLZ)
UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean AS t1
    SET     geom = t2.geom,
            comment =  COALESCE(comment, '') || 'onshore_fix_plz2; ',
            tags = tags || '{"geom":true, "inside_germany":true,"geom_guess":"standort_plz"}'
    FROM    (SELECT plz,
            ST_CENTROID(ST_TRANSFORM(geom,3035)) ::geometry(Point,3035) AS geom
            FROM    boundaries.osm_postcode
            WHERE   stellen = 5
            ORDER BY plz
            ) AS t2,
            (SELECT "Standort", NULLIF(regexp_replace("Standort", '\D','','g'), '')::text AS plz
            FROM model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
            WHERE geom IS NULL
            ) AS t3
    WHERE   length(t3.plz) = 5 AND
            t3.plz = t2.plz AND
            t1.geom IS NULL AND
            t1.tags ->> 'location' = 'onshore';
-- ToDO: Use regexp_split_to_array to split words and remove single numbers




-- Check Offshore
    UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean AS t1
    SET     comment =  COALESCE(comment, '') || 'offshore_inside; ',
            tags = tags || '{"inside_germany":true}'
    FROM    (
        SELECT  m.id AS id
        FROM    model_draft.rli_boundaries_offshore AS vg,
                model_draft.bnetza_mastr_rli_v2_5_5_wind_clean AS m
        WHERE   m."Lage" = 'WindAufSee' AND
                m.geom && vg.geom AND
                ST_CONTAINS(vg.geom,m.geom)
        ) AS t2
    WHERE   t1.id = t2.id;

-- Remove geom offshore outside
UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET     geom =  NULL,
            tags = tags || '{"geom":false, "geom_remove":true}'
    WHERE   (tags->>'geom')::boolean IS true AND
    tags ->> 'location' = 'offshore'  AND
    (tags->>'inside_germany')::boolean IS false;



-- Manual set geom for NULL
UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET comment =  COALESCE(comment, '') || 'guess_geom; ',
        tags = tags || '{"geom":true, "inside_germany":true,"geom_guess":"somewhere"}',
        geom = ST_TRANSFORM(ST_SetSRID(ST_Point(
                                                8.0,
                                                54.0)
                                                ,4326),3035)
    WHERE   geom IS NULL;


---------------------

-- Check for matching



-- OSM power buffer
DROP TABLE IF EXISTS    model_draft.mastr_osm_deu_point_windpower_buffer CASCADE;
CREATE TABLE            model_draft.mastr_osm_deu_point_windpower_buffer (
    id SERIAL,
    osm_name    text,
    osm_count   double precision,
    osm_sum     double precision,
    mastr_count double precision,
    mastr_sum   double precision,
    geom geometry(Polygon,3035),
    CONSTRAINT osm_deu_point_windpower_buffer_pkey PRIMARY KEY (id));

-- insert buffer
INSERT INTO model_draft.mastr_osm_deu_point_windpower_buffer (geom)
    SELECT  (ST_DUMP(ST_MULTI(ST_UNION(
            ST_BUFFER(geom, 25)
        )))).geom ::geometry(Polygon,3035) AS geom
    FROM    model_draft.mastr_osm_deu_point_windpower;

CREATE INDEX mastr_osm_deu_point_windpower_buffer_geom_idx
    ON model_draft.mastr_osm_deu_point_windpower_buffer USING gist (geom);

ALTER TABLE model_draft.mastr_osm_deu_point_windpower_buffer
    OWNER to oeuser;


-- mastr in OSM buffer
UPDATE model_draft.mastr_osm_deu_point_windpower_buffer AS t1
    SET mastr_sum = t2.mastr_sum,
        mastr_count = t2.mastr_count
    FROM (
        SELECT  a.id AS id,
                SUM(b."Bruttoleistung") AS mastr_sum,
                COUNT(b.geom)::integer AS mastr_count
        FROM    model_draft.mastr_osm_deu_point_windpower_buffer AS a,
                model_draft.bnetza_mastr_rli_v2_5_5_wind_clean AS b
        WHERE   a.geom && b.geom AND
                ST_CONTAINS(a.geom,b.geom)
        GROUP BY a.id
        )AS t2
    WHERE   t1.id = t2.id;


-- OSM in OSM
UPDATE model_draft.mastr_osm_deu_point_windpower_buffer AS t1
    SET osm_count = t2.osm_count
    FROM (
        SELECT  a.id AS id,
                COUNT(b.geom)::integer AS osm_count
        FROM    model_draft.mastr_osm_deu_point_windpower_buffer AS a,
                model_draft.mastr_osm_deu_point_windpower AS b
        WHERE   a.geom && b.geom AND
                ST_CONTAINS(a.geom,b.geom)
        GROUP BY a.id
        )AS t2
    WHERE   t1.id = t2.id;


-- OSM_id -> mastr 
ALTER TABLE model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    ADD COLUMN osm_id integer,
    ADD COLUMN osm_name text;

UPDATE model_draft.bnetza_mastr_rli_v2_5_5_wind_clean AS t1
    SET     osm_id = t2.osm_id,
            osm_name = t2.osm_name,
            tags = tags || '{"in_osm":true}'
    FROM (
        SELECT  b.id AS id,
                a.id as osm_id,
                a.osm_name as osm_name
        FROM    model_draft.mastr_osm_deu_point_windpower_buffer AS a,
                model_draft.bnetza_mastr_rli_v2_5_5_wind_clean AS b
        WHERE   a.geom && b.geom AND
                ST_CONTAINS(a.geom,b.geom)
        GROUP BY b.id, a.id
        )AS t2
    WHERE   t1.id = t2.id;



-- MaStR buffer
DROP TABLE IF EXISTS    model_draft.bnetza_mastr_rli_v2_5_5_wind_clean_buffer CASCADE;
CREATE TABLE            model_draft.bnetza_mastr_rli_v2_5_5_wind_clean_buffer (
    id SERIAL,
    osm_name    text,
    osm_count   double precision,
    osm_sum     double precision,
    mastr_count double precision,
    mastr_sum   double precision,
    geom geometry(Polygon,3035),
    CONSTRAINT bnetza_mastr_rli_v2_5_5_wind_clean_buffer_pkey PRIMARY KEY (id));

-- insert buffer
INSERT INTO model_draft.bnetza_mastr_rli_v2_5_5_wind_clean_buffer (geom)
    SELECT  (ST_DUMP(ST_MULTI(ST_UNION(
            ST_BUFFER(geom, 25)
        )))).geom ::geometry(Polygon,3035) AS geom
    FROM    model_draft.bnetza_mastr_rli_v2_5_5_wind_clean;

CREATE INDEX bnetza_mastr_rli_v2_5_5_wind_clean_buffer_geom_idx
    ON model_draft.bnetza_mastr_rli_v2_5_5_wind_clean_buffer USING gist (geom);

ALTER TABLE model_draft.bnetza_mastr_rli_v2_5_5_wind_clean_buffer
    OWNER to oeuser;


-- mastr in mastr buffer
UPDATE model_draft.bnetza_mastr_rli_v2_5_5_wind_clean_buffer AS t1
    SET mastr_sum = t2.mastr_sum,
        mastr_count = t2.mastr_count
    FROM (
        SELECT  a.id AS id,
                SUM(b."Bruttoleistung") AS mastr_sum,
                COUNT(b.geom)::integer AS mastr_count
        FROM    model_draft.bnetza_mastr_rli_v2_5_5_wind_clean_buffer AS a,
                model_draft.bnetza_mastr_rli_v2_5_5_wind_clean AS b
        WHERE   a.geom && b.geom AND
                ST_CONTAINS(a.geom,b.geom)
        GROUP BY a.id
        )AS t2
    WHERE   t1.id = t2.id;

-- OSM in mastr buffer
UPDATE model_draft.bnetza_mastr_rli_v2_5_5_wind_clean_buffer AS t1
    SET osm_count = t2.osm_count
    FROM (
        SELECT  a.id AS id,
                COUNT(b.geom)::integer AS osm_count
        FROM    model_draft.bnetza_mastr_rli_v2_5_5_wind_clean_buffer AS a,
                model_draft.mastr_osm_deu_point_windpower AS b
        WHERE   a.geom && b.geom AND
                ST_CONTAINS(a.geom,b.geom)
        GROUP BY a.id
        )AS t2
    WHERE   t1.id = t2.id;



-- MaStR-Buffer -> mastr 
ALTER TABLE model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    ADD COLUMN mastr_buffer_cnt integer;

UPDATE model_draft.bnetza_mastr_rli_v2_5_5_wind_clean AS t1
    SET     mastr_buffer_cnt = t2.mastr_buffer_cnt
    FROM (
        SELECT  b.id AS id,
                a.mastr_count as mastr_buffer_cnt
        FROM    model_draft.bnetza_mastr_rli_v2_5_5_wind_clean_buffer AS a,
                model_draft.bnetza_mastr_rli_v2_5_5_wind_clean AS b
        WHERE   a.geom && b.geom AND
                ST_CONTAINS(a.geom,b.geom)
        GROUP BY b.id, a.id
        )AS t2
    WHERE   t1.id = t2.id;





-- Tags: duplicates
UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    SET comment =  COALESCE(comment, '') || 'match_osm; ',
        tags = tags || '{"match_osm":true}'
    WHERE   (tags->>'in_osm')::boolean IS true;










-------------------- checks

--UPDATE  model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
--    SET tags = tags || '{"geom": true, "inside_germany":false}'

-- Select JSONB
SELECT tags, count(tags) AS count
FROM model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
GROUP BY tags
ORDER BY count DESC;

-- Count locations
SELECT tags ->> 'location' AS locations, count(tags ->> 'location') AS count
FROM model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
GROUP BY locations
ORDER BY count DESC;

SELECT count(*)
FROM model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
WHERE tags ->> 'location' = 'offshore';

SELECT (tags->>'geom')::boolean as geom_type, count(*)
FROM model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
WHERE (tags->>'geom')::boolean
GROUP BY geom_type

SELECT (tags->>'geom')::boolean as geom_type, count(*)
FROM model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
WHERE (tags->>'geom')::boolean IS false
GROUP BY geom_type

-- Check geom
SELECT *
FROM model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
WHERE geom IS NULL;

-- Analyze Wind
SELECT  "Technologie", COUNT(*) AS cnt
FROM model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
GROUP BY "Technologie";

-- Analyze Wind
SELECT  "HerstellerID", "HerstellerName", COUNT(*) AS cnt
FROM model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
GROUP BY "HerstellerID","HerstellerName"
ORDER BY COUNT(*) DESC;

-- Analyze Wind
SELECT  "HerstellerID", "HerstellerName", "Typenbezeichnung", COUNT(*) AS cnt
FROM model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
GROUP BY "HerstellerID","HerstellerName", "Typenbezeichnung"
ORDER BY COUNT(*) DESC;

/*
-- Analyze Wind
SELECT  'ALL' AS "Typenbezeichnung", COUNT(*) AS cnt
FROM model_draft.bnetza_mastr_rli_v2_5_5_wind_clean_50hertz
WHERE is_50hertz = TRUE
UNION ALL
SELECT  "Typenbezeichnung", COUNT(*) AS cnt
FROM model_draft.bnetza_mastr_rli_v2_5_5_wind_clean_50hertz
WHERE is_50hertz = TRUE
GROUP BY "Typenbezeichnung"
*/


/*
-- TEST
SELECT ST_SetSRID(ST_Point("Laengengrad", "Breitengrad"),4326) As wgs84long_lat
FROM model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
LIMIT 10;

SELECT  COUNT(*) AS all,
        COUNT("Laengengrad") AS lon,
        COUNT("Breitengrad") AS lat,
        COUNT(geom) AS geom
FROM model_draft.bnetza_mastr_rli_v2_5_5_wind_clean;

SELECT  comment, COUNT(comment) AS cnt
FROM model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
GROUP BY comment;
*/

-------------------------------------------------------
-- Create a reduced version
DROP TABLE IF EXISTS model_draft.bnetza_mastr_rli_v2_5_5_wind_clean_reduced CASCADE;
CREATE TABLE         model_draft.bnetza_mastr_rli_v2_5_5_wind_clean_reduced AS
    SELECT  "id",
            "EinheitMastrNummer",
            "Bruttoleistung",
            "EinheitBetriebsstatus",
            "Anlagenbetreiber",
            "EegMastrNummer",
            "KwkMastrNummer",
            "GenMastrNummer",
            "version",
            "timestamp",
            "Ergebniscode",
            "DatumLetzteAktualisierung",
            "LokationMastrNummer",
            "NetzbetreiberpruefungStatus",
            "NetzbetreiberpruefungDatum",
            "AnlagenbetreiberMastrNummer",
            "Land",
            "Bundesland",
            "Landkreis",
            "Gemeinde",
            "Gemeindeschluessel",
            "Postleitzahl",
            "Gemarkung",
            "FlurFlurstuecknummern",
            "Strasse",
            "StrasseNichtGefunden",
            "Hausnummer",
            "HausnummerNichtGefunden",
            "Adresszusatz",
            "Ort",
            "Laengengrad",
            "Breitengrad",
            "Meldedatum",
            "Inbetriebnahmedatum",
            "DatumEndgueltigeStilllegung",
            "DatumBeginnVoruebergehendeStilllegung",
            "DatumWiederaufnahmeBetrieb",
            "EinheitBetriebsstatus_w",
            "AltAnlagenbetreiberMastrNummer",
            "DatumDesBetreiberwechsels",
            "DatumRegistrierungDesBetreiberwechsels",
            "StatisikFlag_w",
            "NameStromerzeugungseinheit",
            "WeicDisplayName",
            "Bruttoleistung_w",
            "Nettonennleistung",
            "AnschlussAnHoechstOderHochSpannung",
            "FernsteuerbarkeitNb",
            "FernsteuerbarkeitDv",
            "FernsteuerbarkeitDr",
            "Einspeisungsart",
            "GenMastrNummer_w",
            "NameWindpark",
            "Lage",
            "Seelage",
            "ClusterOstsee",
            "ClusterNordsee",
            "Technologie",
            "Typenbezeichnung",
            "Nabenhoehe",
            "Rotordurchmesser",
            "AuflageAbschaltungLeistungsbegrenzung",
            "Wassertiefe",
            "Kuestenentfernung",
            "EegMastrNummer_w",
            "HerstellerID",
            "HerstellerName",
            "timestamp_w",
            "Ergebniscode_e",
            "Meldedatum_e",
            "DatumLetzteAktualisierung_e",
            "EegInbetriebnahmedatum",
            "AnlagenkennzifferAnlagenregister",
            "AnlagenschluesselEeg",
            "InstallierteLeistung",
            "VerhaeltnisErtragsschaetzungReferenzertrag",
            "AnlageBetriebsstatus",
            "VerknuepfteEinheit",
            "MaStRNummer",
            "Datum",
            "Art",
            "Behoerde",
            "Aktenzeichen",
            "Frist",
            "Meldedatum_p",
            "lat",
            "lon",
            "geom",
            "comment"
    FROM    model_draft.bnetza_mastr_rli_v2_5_5_wind_clean
    WHERE geom IS NOT NULL
    ORDER BY id;

ALTER TABLE model_draft.bnetza_mastr_rli_v2_5_5_wind_clean_reduced
    ADD PRIMARY KEY (id);

CREATE INDEX bnetza_mastr_rli_v2_5_5_wind_clean_reduced_geom_idx
    ON model_draft.bnetza_mastr_rli_v2_5_5_wind_clean_reduced USING gist (geom);

ALTER TABLE model_draft.bnetza_mastr_rli_v2_5_5_wind_clean_reduced
    OWNER to oeuser;


