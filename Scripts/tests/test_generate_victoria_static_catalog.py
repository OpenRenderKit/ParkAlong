import json
import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from generate_victoria_static_catalog import (  # noqa: E402
    assign_spatial_municipality,
    build_ballarat_records,
    build_boroondara_records,
    build_brimbank_carpark_records,
    build_brimbank_disabled_records,
    build_casey_records,
    build_colac_otway_records,
    build_glen_eira_accessible_records,
    build_latrobe_records,
    build_manningham_records,
    build_maribyrnong_records,
    build_mildura_accessible_records,
    build_monash_records,
    build_moorabool_records,
    build_osm_records,
    build_port_phillip_accessible_records,
    build_southern_grampians_records,
    build_swan_hill_accessible_records,
    build_vicmap_parking_records,
    build_wodonga_records,
    curated_official_records,
    deduplicate_records,
    geometry_centroid,
    lga_short_municipality_name,
)


class VictoriaStaticCatalogTests(unittest.TestCase):
    def test_arcgis_polygon_centroid_uses_lon_lat_order(self):
        geometry = {"rings": [[[144.8, -37.8], [145.0, -37.8], [145.0, -38.0], [144.8, -38.0]]]}
        self.assertEqual(geometry_centroid(geometry), {"latitude": -37.9, "longitude": 144.9})

    def test_maribyrnong_clusters_bays_and_counts_accessible_spaces(self):
        regular = [
            {"attributes": {"OBJECTID": 1}, "geometry": {"rings": [[[144.9000, -37.8000], [144.9001, -37.8000], [144.9001, -37.8001]]]}},
            {"attributes": {"OBJECTID": 2}, "geometry": {"rings": [[[144.9002, -37.8001], [144.9003, -37.8001], [144.9003, -37.8002]]]}},
        ]
        accessible = [
            {"attributes": {"OBJECTID": 3}, "geometry": {"rings": [[[144.9001, -37.8000], [144.9002, -37.8000], [144.9002, -37.8001]]]}},
        ]

        records = build_maribyrnong_records(regular, accessible, checked_at="2026-08-23T00:00:00Z")

        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["capacity"], 3)
        self.assertEqual(records[0]["accessibleSpaces"], 1)
        self.assertEqual(records[0]["classification"], "static_only")
        self.assertEqual(records[0]["municipality"], "Maribyrnong")

    def test_ballarat_uses_current_tariff_overlay_not_stale_comment_price(self):
        payload = [{
            "id": 6,
            "zone": "1",
            "road": "Sturt Street",
            "comment": "Zone 1 - First hour free then $3 per hour.",
            "geo_point_2d": {"lat": -37.56, "lon": 143.86},
        }]

        record = build_ballarat_records(payload, checked_at="2026-08-23T00:00:00Z")[0]

        self.assertEqual(record["tariffs"][0]["hourlyCents"], 360)
        self.assertEqual(record["tariffs"][0]["freeMinutes"], 60)
        self.assertNotIn("$3 per hour", json.dumps(record))

    def test_casey_excludes_no_stopping_but_keeps_timed_parking_and_station_capacity(self):
        restrictions = [
            {"street": "Wilona Way", "restrtype": "No Stopping", "timesop1": "8:00am - 9:15am", "daysop1": "School Days", "latitude": -38.04, "longitude": 145.35},
            {"street": "High Street", "restrtype": "2P", "timesop1": "9:00am - 5:00pm", "daysop1": "Mon-Fri", "latitude": -38.03, "longitude": 145.34},
        ]
        stations = [{"gisfid": 3, "station_name": "Narre Warren", "carpark_capacity": 107, "suburb": "Narre Warren", "latitude": -38.02, "longitude": 145.30}]

        records = build_casey_records(restrictions, stations, checked_at="2026-08-23T00:00:00Z")

        self.assertEqual({record["name"] for record in records}, {"High Street · 2P", "Narre Warren Station car park"})
        station = next(record for record in records if "Station" in record["name"])
        self.assertEqual(station["capacity"], 107)
        self.assertEqual(station["archetype"], "station_commuter")

    def test_boroondara_cleans_embedded_coordinates_and_accessible_counts(self):
        public = [{"nid": "10", "title": "Car park - Junction West", "location": "\n 3 Burke Avenue, Hawthorn East\n", "geo_info": "\n -37.8290, 145.0560\n", "description": "Check local signs"}]
        accessible = [{"nid": "20", "title": "Car park - Junction West accessible", "location": "3 Burke Avenue, Hawthorn East", "geo_info": "-37.8291, 145.0561", "description": "4 disabled parking spaces available."}]

        records = build_boroondara_records(public, accessible, checked_at="2026-08-23T00:00:00Z")

        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["coordinate"], {"latitude": -37.829, "longitude": 145.056})
        self.assertEqual(records[0]["accessibleSpaces"], 4)
        self.assertEqual(records[0]["name"], "Junction West")

    def test_deduplication_is_stable_and_discards_invalid_coordinates(self):
        valid = {"id": "source-2", "coordinate": {"latitude": -37.8, "longitude": 145.0}}
        duplicate = {"id": "source-2", "coordinate": {"latitude": -37.9, "longitude": 145.1}}
        invalid = {"id": "source-1", "coordinate": {"latitude": 2.0, "longitude": 300.0}}

        self.assertEqual(deduplicate_records([valid, duplicate, invalid]), [valid])

    def test_osm_supplies_statewide_location_capacity_fee_and_odbl_attribution(self):
        elements = [{
            "type": "way", "id": 42, "center": {"lat": -36.75, "lon": 144.28},
            "tags": {"amenity": "parking", "name": "Regional station parking", "capacity": "80", "capacity:disabled": "3", "fee": "no", "parking": "surface"},
        }]

        record = build_osm_records(elements, checked_at="2026-08-23T00:00:00Z", dataset_updated_at="2026-08-22T23:55:00Z")[0]

        self.assertEqual(record["capacity"], 80)
        self.assertEqual(record["accessibleSpaces"], 3)
        self.assertEqual(record["tariffs"][0]["hourlyCents"], 0)
        self.assertEqual(record["source"]["licenseName"], "Open Database License 1.0")
        self.assertEqual(record["source"]["datasetUpdatedAt"], "2026-08-22T23:55:00Z")

    def test_osm_excludes_explicitly_restricted_parking(self):
        elements = [
            {"type": "node", "id": 1, "lat": -37.8, "lon": 145.0, "tags": {"amenity": "parking", "access": "private"}},
            {"type": "node", "id": 2, "lat": -37.8, "lon": 145.1, "tags": {"amenity": "parking", "access": "customers"}},
            {"type": "node", "id": 3, "lat": -37.8, "lon": 145.2, "tags": {"amenity": "parking", "access": "yes"}},
            {"type": "node", "id": 4, "lat": -37.8, "lon": 145.3, "tags": {"amenity": "parking"}},
        ]

        records = build_osm_records(elements, checked_at="2026-08-23T00:00:00Z", dataset_updated_at=None)

        self.assertEqual([record["id"] for record in records], ["osm-node-3", "osm-node-4"])
        self.assertEqual(records[1]["name"], "Mapped parking")

    def test_wodonga_preserves_capacity_accessibility_and_multiple_rule_windows(self):
        features = [{
            "attributes": {
                "OBJECTID": 7, "public_view": 1, "park_name": "High Street bays", "spaces": 3,
                "disable": "Y", "time_h": 2, "start_time": "09:00", "end_time": "17:30", "days": "Mon-Fri",
                "time_h_2": 4, "start_time_2": "09:00", "end_time_2": "13:00", "days_2": "Sat",
            },
            "geometry": {"rings": [[[146.88, -36.12], [146.89, -36.12], [146.89, -36.13]]]},
        }]

        record = build_wodonga_records(features, checked_at="2026-08-23T00:00:00Z")[0]

        self.assertEqual(record["capacity"], 3)
        self.assertEqual(record["accessibleSpaces"], 3)
        self.assertEqual(record["schedules"][0]["maxStayMinutes"], 120)
        self.assertEqual(record["schedules"][0]["days"], [2, 3, 4, 5, 6])
        self.assertEqual(record["schedules"][1]["maxStayMinutes"], 240)

    def test_official_arcgis_sources_map_stable_identity_and_accessibility(self):
        manningham = build_manningham_records([{
            "attributes": {"ASSET_ID_ASSETIC": "CP-1", "ASSETNAME": "Templestowe Village", "ASSETCLASS": "Car Park"},
            "geometry": {"x": 145.13, "y": -37.76},
        }], checked_at="2026-08-23T00:00:00Z")[0]
        latrobe = build_latrobe_records([{
            "attributes": {"OBJECTID": 2, "Larger_Car": "Accessible bay", "Locality": "Morwell", "Timed": "2P"},
            "geometry": {"x": 146.40, "y": -38.24},
        }], checked_at="2026-08-23T00:00:00Z")[0]
        moorabool = build_moorabool_records([{
            "attributes": {"FID": 3, "AssetId": "M-3", "Name": "Main Street Car Park", "Status": "Active", "Locality": "Bacchus Marsh"},
            "geometry": {"x": 144.44, "y": -37.68},
        }], checked_at="2026-08-23T00:00:00Z")[0]

        self.assertEqual(manningham["id"], "manningham-CP-1")
        self.assertEqual(latrobe["accessibleSpaces"], 1)
        self.assertEqual(latrobe["schedules"][0]["maxStayMinutes"], 120)
        self.assertEqual(moorabool["municipality"], "Moorabool")

    def test_mildura_accessible_bays_keep_scope_rules_freshness_and_open_licence(self):
        features = [{
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [142.1616, -34.1870]},
            "properties": {
                "Mode": "disabled", "Updated": "20230906", "Ref": "49",
                "Days": "Monday; Tuesday; Wednesday; Thursday; Friday; Saturday; Sunday",
                "Minsmax": "120", "Hourlyfee": "0.00", "Type": "street", "Capacity": "1",
                "Address": "122 Ninth ST, MILDURA", "Location": "Mallee Family Care",
            },
        }]

        record = build_mildura_accessible_records(features, checked_at="2026-09-19T00:00:00Z")[0]

        self.assertEqual(record["id"], "mildura-accessible-49")
        self.assertEqual(record["accessibleSpaces"], 1)
        self.assertEqual(record["schedules"][0]["maxStayMinutes"], 120)
        self.assertEqual(record["tariffs"][0]["hourlyCents"], 0)
        self.assertEqual(record["source"]["datasetUpdatedAt"], "2023-09-06T00:00:00Z")
        self.assertEqual(record["source"]["licenseName"], "Creative Commons Attribution 3.0 Australia")
        self.assertEqual(record["classification"], "static_only")

    def test_swan_hill_accessible_bays_are_static_and_attributed(self):
        rows = [{
            "id": "4", "lat": "-35.340608", "lon": "143.560907",
            "name": "McCrae Street between Campbell Street and Curlewis Street, Swan Hill",
        }]

        record = build_swan_hill_accessible_records(rows, checked_at="2026-09-19T00:00:00Z")[0]

        self.assertEqual(record["id"], "swan-hill-accessible-4")
        self.assertEqual(record["municipality"], "Swan Hill")
        self.assertEqual(record["capacity"], 1)
        self.assertEqual(record["accessibleSpaces"], 1)
        self.assertEqual(record["classification"], "static_only")

    def test_vicmap_parking_areas_use_authoritative_cc_by_source_without_live_claim(self):
        features = [{
            "attributes": {
                "OBJECTID": 433, "feature_ufi": 76321071,
                "feature_subtype": "parking area", "name_label": "Royal Womens Hospital",
            },
            "geometry": {"x": 144.95545, "y": -37.79868},
        }]

        record = build_vicmap_parking_records(
            features, checked_at="2026-09-19T00:00:00Z", dataset_updated_at="2026-09-13T00:00:00Z",
        )[0]

        self.assertEqual(record["id"], "vicmap-parking-76321071")
        self.assertEqual(record["municipality"], "Victoria")
        self.assertEqual(record["classification"], "static_only")
        self.assertEqual(record["source"]["licenseName"], "Creative Commons Attribution 4.0")

    def test_approved_contractor_sources_remain_traceable_to_their_actual_publishers(self):
        colac = build_colac_otway_records([{
            "attributes": {"ObjectID": 10, "Carpark_AM_ID": "CO-10", "Street_Name": "Murray Street", "Location": "Colac", "Status": "Active"},
            "geometry": {"x": 143.58, "y": -38.34},
        }], checked_at="2026-08-23T00:00:00Z")[0]
        monash = build_monash_records(
            [{"attributes": {"LocationID": "S-1"}, "geometry": {"x": 145.13, "y": -37.91}}],
            [{"attributes": {"LocationID": "C-2"}, "geometry": {"x": 145.14, "y": -37.92}}],
            checked_at="2026-08-23T00:00:00Z",
        )
        southern = build_southern_grampians_records([{
            "attributes": {"asset_id": "SG-4", "asset_type": "Carpark", "road_name": "Gray Street", "locality": "Hamilton", "asset_description": "Library car park"},
            "geometry": {"x": 142.02, "y": -37.74},
        }], checked_at="2026-08-23T00:00:00Z")[0]

        self.assertIn("Shepherd Services", colac["source"]["name"])
        self.assertEqual([record["kind"] for record in monash], ["on_street", "off_street"])
        self.assertIn("WGA", monash[0]["source"]["name"])
        self.assertEqual(southern["name"], "Library car park")

    def test_osm_conservatively_parses_supported_maxstay_opening_hours_and_charge(self):
        elements = [{
            "type": "way", "id": 99, "center": {"lat": -37.7, "lon": 145.0},
            "tags": {
                "amenity": "parking", "name": "Timed public parking", "fee": "yes",
                "maxstay": "2 hours", "opening_hours": "Mo-Fr 09:00-17:30", "charge": "$2.40/hour",
            },
        }]

        record = build_osm_records(elements, checked_at="2026-08-23T00:00:00Z", dataset_updated_at=None)[0]

        self.assertEqual(record["schedules"][0]["days"], [2, 3, 4, 5, 6])
        self.assertEqual(record["schedules"][0]["startMinutes"], 540)
        self.assertEqual(record["schedules"][0]["endMinutes"], 1050)
        self.assertEqual(record["schedules"][0]["maxStayMinutes"], 120)
        self.assertEqual(record["tariffs"][0]["hourlyCents"], 240)

    def test_osm_retains_unsupported_conditions_instead_of_silently_dropping_them(self):
        elements = [{
            "type": "node", "id": 100, "lat": -37.7, "lon": 145.0,
            "tags": {
                "amenity": "parking", "maxstay:conditional": "2 hours @ (event days)",
                "charge:conditional": "$4/hour @ (event days)",
            },
        }]

        record = build_osm_records(elements, checked_at="2026-08-23T00:00:00Z", dataset_updated_at=None)[0]

        self.assertEqual(record["schedules"][0]["unparsedCondition"], "2 hours @ (event days)")
        self.assertEqual(record["tariffs"][0]["unparsedCondition"], "$4/hour @ (event days)")

    def test_bendigo_hargreaves_uses_exact_current_facility_capacity_hours_and_tariff(self):
        records = curated_official_records("2026-08-23T00:00:00Z")

        record = next(item for item in records if item["id"] == "bendigo-hargreaves-multistorey")

        self.assertEqual(record["municipality"], "Greater Bendigo")
        self.assertEqual(record["coordinate"], {"latitude": -36.7588004, "longitude": 144.2812571})
        self.assertEqual(record["capacity"], 290)
        self.assertEqual(record["accessibleSpaces"], 6)
        self.assertEqual([schedule["endMinutes"] for schedule in record["schedules"]], [1170, 1320, 1320, 1080])
        self.assertEqual(record["tariffs"][0]["hourlyCents"], 240)
        self.assertEqual(record["tariffs"][0]["dailyCapCents"], 1000)
        self.assertEqual(record["tariffs"][1]["hourlyCents"], 0)

    def test_curated_regional_overviews_preserve_current_area_specific_tariffs(self):
        records = {record["id"]: record for record in curated_official_records("2026-08-23T00:00:00Z")}

        self.assertEqual(records["geelong-central-2p"]["tariffs"][0]["hourlyCents"], 0)
        self.assertEqual(records["geelong-central-2p"]["schedules"][0]["maxStayMinutes"], 120)
        self.assertEqual(records["wangaratta-cbd-paid"]["tariffs"][0]["hourlyCents"], 120)
        self.assertEqual(records["horsham-cbd-free-2p"]["tariffs"][0]["hourlyCents"], 0)
        self.assertEqual(records["swan-hill-curlewis-ticketed"]["tariffs"][0]["hourlyCents"], 140)

    def test_lga_short_names_follow_existing_title_case_convention(self):
        self.assertEqual(lga_short_municipality_name("MERRI-BEK"), "Merri-bek")
        self.assertEqual(lga_short_municipality_name("MORNINGTON PENINSULA"), "Mornington Peninsula")
        self.assertEqual(lga_short_municipality_name("COLAC OTWAY"), "Colac Otway")
        self.assertEqual(lga_short_municipality_name("YARRA RANGES"), "Yarra Ranges")
        self.assertEqual(lga_short_municipality_name("GREATER DANDENONG"), "Greater Dandenong")
        self.assertEqual(lga_short_municipality_name("SWAN HILL"), "Swan Hill")
        self.assertEqual(lga_short_municipality_name("MELBOURNE"), "Melbourne")
        self.assertNotEqual(lga_short_municipality_name("MELBOURNE"), "Melbourne City")

    def test_spatial_labels_fill_generic_victoria_but_keep_holes_and_outside_unknown(self):
        geojson = _lga_feature_collection(
            "MERRI-BEK",
            "351",
            [[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]]],
            holes=[[[4, 4], [6, 4], [6, 6], [4, 6], [4, 4]]],
            official_name="MERRI-BEK CITY",
        )
        inside = _labelled_record("osm-inside", "Victoria", latitude=2, longitude=2)
        hole = _labelled_record("osm-hole", "Victoria", latitude=5, longitude=5)
        outside = _labelled_record("osm-outside", "Victoria", latitude=2, longitude=12)
        source = dict(inside["source"])

        assign_spatial_municipality([inside, hole, outside], geojson)

        self.assertEqual(inside["municipality"], "Merri-bek")
        self.assertEqual(hole["municipality"], "Victoria")
        self.assertEqual(outside["municipality"], "Victoria")
        self.assertEqual(inside["source"], source)
        self.assertEqual(inside["classification"], "static_only")

    def test_spatial_labels_do_not_overwrite_explicit_council_municipality(self):
        geojson = _lga_feature_collection(
            "GREATER DANDENONG",
            "226",
            [[[145.0, -38.1], [145.3, -38.1], [145.3, -37.9], [145.0, -37.9], [145.0, -38.1]]],
        )
        casey = _labelled_record("casey-restriction-1", "Casey", latitude=-38.0, longitude=145.1)
        schedules = casey["schedules"]
        tariffs = casey["tariffs"]
        source = casey["source"]

        assign_spatial_municipality([casey], geojson)

        self.assertEqual(casey["municipality"], "Casey")
        self.assertIs(casey["schedules"], schedules)
        self.assertIs(casey["tariffs"], tariffs)
        self.assertIs(casey["source"], source)
        self.assertEqual(casey["id"], "casey-restriction-1")
        self.assertEqual(casey["classification"], "static_only")

    def test_osm_and_vicmap_keep_source_provenance_after_spatial_labelling(self):
        osm = build_osm_records(
            [{
                "type": "way", "id": 42, "center": {"lat": -36.75, "lon": 144.28},
                "tags": {"amenity": "parking", "name": "Regional station parking", "capacity": "80"},
            }],
            checked_at="2026-08-23T00:00:00Z",
            dataset_updated_at="2026-08-22T23:55:00Z",
        )[0]
        vicmap = build_vicmap_parking_records(
            [{
                "attributes": {
                    "OBJECTID": 433, "feature_ufi": 76321071,
                    "feature_subtype": "parking area", "name_label": "Royal Womens Hospital",
                },
                "geometry": {"x": 144.95545, "y": -37.79868},
            }],
            checked_at="2026-09-19T00:00:00Z",
            dataset_updated_at="2026-09-13T00:00:00Z",
        )[0]
        geojson = {
            "type": "FeatureCollection",
            "features": [
                _lga_feature(
                    "GREATER BENDIGO",
                    "273",
                    [[[144.2, -36.9], [144.4, -36.9], [144.4, -36.6], [144.2, -36.6], [144.2, -36.9]]],
                    official_name="GREATER BENDIGO CITY",
                ),
                _lga_feature(
                    "MELBOURNE",
                    "343",
                    [[[144.9, -37.85], [145.0, -37.85], [145.0, -37.78], [144.9, -37.78], [144.9, -37.85]]],
                    official_name="MELBOURNE CITY",
                ),
            ],
        }
        osm_source = dict(osm["source"])
        vicmap_source = dict(vicmap["source"])

        assign_spatial_municipality([osm, vicmap], geojson)

        self.assertEqual(osm["municipality"], "Greater Bendigo")
        self.assertEqual(osm["id"], "osm-way-42")
        self.assertEqual(osm["source"], osm_source)
        self.assertEqual(osm["source"]["id"], "openstreetmap-victoria-parking")
        self.assertEqual(osm["source"]["licenseName"], "Open Database License 1.0")
        self.assertEqual(vicmap["municipality"], "Melbourne")
        self.assertEqual(vicmap["id"], "vicmap-parking-76321071")
        self.assertEqual(vicmap["source"], vicmap_source)
        self.assertEqual(vicmap["source"]["id"], "vicmap-features-of-interest-parking")
        self.assertEqual(vicmap["source"]["licenseName"], "Creative Commons Attribution 4.0")
        self.assertEqual(vicmap["classification"], "static_only")
        self.assertIsNone(vicmap["predictionEvidence"])

    def test_port_phillip_accessible_is_static_unknown_kind_without_bay_counts(self):
        features = [{
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [144.9550, -37.8400]},
            "properties": {"Table_Row_ID": 12},
        }]

        record = build_port_phillip_accessible_records(features, checked_at="2026-09-19T00:00:00Z")[0]

        self.assertEqual(record["id"], "port-phillip-accessible-12")
        self.assertIn("Accessible parking location", record["name"])
        self.assertEqual(record["municipality"], "Port Phillip")
        self.assertEqual(record["coordinate"], {"latitude": -37.84, "longitude": 144.955})
        self.assertEqual(record["kind"], "unknown")
        self.assertIsNone(record["capacity"])
        self.assertIsNone(record["accessibleSpaces"])
        self.assertEqual(record["schedules"], [])
        self.assertEqual(record["tariffs"], [])
        self.assertIsNone(record["predictionEvidence"])
        self.assertEqual(record["classification"], "static_only")
        self.assertEqual(record["source"]["id"], "port-phillip-accessible-parking")
        self.assertEqual(record["source"]["name"], "City of Port Phillip")
        self.assertEqual(
            record["source"]["sourceURL"],
            "https://data.gov.au/data/dataset/city-of-port-phillip-accessible-parking",
        )
        self.assertEqual(record["source"]["licenseName"], "Creative Commons Attribution 2.5 Australia")
        self.assertEqual(record["source"]["licenseURL"], "https://creativecommons.org/licenses/by/2.5/au/")
        self.assertEqual(record["source"]["datasetUpdatedAt"], "2022-08-11T05:43:28Z")
        self.assertEqual(record["source"]["checkedAt"], "2026-09-19T00:00:00Z")

    def test_glen_eira_accessible_preserves_spaces_with_id_fallback(self):
        features = [
            {
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [145.0500, -37.8800]},
                "properties": {"ID": 7, "Spaces": 2},
            },
            {
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [145.0600, -37.8900]},
                "properties": {"ogr_fid": 9, "Spaces": "3"},
            },
        ]

        records = build_glen_eira_accessible_records(features, checked_at="2026-09-19T00:00:00Z")

        self.assertEqual([record["id"] for record in records], ["glen-eira-accessible-7", "glen-eira-accessible-9"])
        self.assertEqual(records[0]["accessibleSpaces"], 2)
        self.assertEqual(records[1]["accessibleSpaces"], 3)
        for record in records:
            self.assertEqual(record["kind"], "unknown")
            self.assertIsNone(record["capacity"])
            self.assertEqual(record["municipality"], "Glen Eira")
            self.assertEqual(record["classification"], "static_only")
            self.assertEqual(record["schedules"], [])
            self.assertEqual(record["tariffs"], [])
            self.assertIsNone(record["predictionEvidence"])
        self.assertEqual(records[0]["source"]["id"], "glen-eira-accessible-parking")
        self.assertEqual(records[0]["source"]["name"], "Glen Eira City Council")
        self.assertEqual(
            records[0]["source"]["sourceURL"], "https://data.gov.au/data/dataset/accessible-parking"
        )
        self.assertEqual(records[0]["source"]["licenseName"], "Creative Commons Attribution 2.5 Australia")
        self.assertEqual(records[0]["source"]["licenseURL"], "https://creativecommons.org/licenses/by/2.5/au/")
        self.assertEqual(records[0]["source"]["datasetUpdatedAt"], "2022-08-01T04:22:41Z")

    def test_glen_eira_accessible_deduplicates_identical_published_rows(self):
        features = [
            {
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [145.03411511, -37.91739061]},
                "properties": {"ID": 119, "Spaces": 1},
            },
            {
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [145.03411511, -37.91739061]},
                "properties": {"ID": 120, "Spaces": 1},
            },
            {
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [145.03411511, -37.91739061]},
                "properties": {"ID": 121, "Spaces": 2},
            },
        ]

        records = build_glen_eira_accessible_records(
            features, checked_at="2026-09-19T00:00:00Z"
        )

        self.assertEqual(
            [record["id"] for record in records],
            ["glen-eira-accessible-119", "glen-eira-accessible-121"],
        )

    def test_port_phillip_and_glen_eira_reject_invalid_rows_without_inventing_values(self):
        port_phillip = build_port_phillip_accessible_records(
            [
                {"type": "Feature", "geometry": {"type": "Point", "coordinates": [144.95, -37.84]}, "properties": {}},
                {"type": "Feature", "geometry": {"type": "Point", "coordinates": [0.0, 0.0]}, "properties": {"Table_Row_ID": 1}},
                {"type": "Feature", "geometry": None, "properties": {"Table_Row_ID": 2}},
                {
                    "type": "Feature",
                    "geometry": {"type": "Point", "coordinates": [144.95, -37.84]},
                    "properties": {"Table_Row_ID": "   "},
                },
            ],
            checked_at="2026-09-19T00:00:00Z",
        )
        glen_eira = build_glen_eira_accessible_records(
            [
                {"type": "Feature", "geometry": {"type": "Point", "coordinates": [145.05, -37.88]}, "properties": {"Spaces": 2}},
                {"type": "Feature", "geometry": {"type": "Point", "coordinates": [145.05, -37.88]}, "properties": {"ID": 11, "Spaces": 0}},
                {"type": "Feature", "geometry": {"type": "Point", "coordinates": [145.05, -37.88]}, "properties": {"ID": 12, "Spaces": -1}},
                {"type": "Feature", "geometry": {"type": "Point", "coordinates": [145.05, -37.88]}, "properties": {"ID": 13}},
                {"type": "Feature", "geometry": {"type": "Point", "coordinates": [0.0, 0.0]}, "properties": {"ID": 14, "Spaces": 1}},
            ],
            checked_at="2026-09-19T00:00:00Z",
        )

        self.assertEqual(port_phillip, [])
        self.assertEqual(glen_eira, [])

    def test_empty_lga_short_name_does_not_overwrite_victoria(self):
        self.assertEqual(lga_short_municipality_name(""), "")
        self.assertEqual(lga_short_municipality_name("   "), "")

        geojson = {
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "properties": {"lga_code": "999", "lga_name": "   ", "lga_official_name": "UNKNOWN"},
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": [[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]]],
                    },
                }
            ],
        }
        record = _labelled_record("osm-empty-lga", "Victoria", latitude=2, longitude=2)

        assign_spatial_municipality([record], geojson)

        self.assertEqual(record["municipality"], "Victoria")

    def test_brimbank_carparks_use_stable_ids_centroid_capacity_and_exclusions(self):
        eligible = {
            "id": "brimbank_carparks.12",
            "type": "Feature",
            "geometry": {
                "type": "MultiPolygon",
                "coordinates": [[[[145.0, -37.78], [145.01, -37.78], [145.01, -37.79], [145.0, -37.79], [145.0, -37.78]]]],
            },
            "properties": {"Type": "Sunshine Car Park", "Num_Of_Bay": "45", "Parking_Re": "", "Lat": "-37.0", "Long": "145.0"},
        }
        null_capacity = {
            "id": "brimbank_carparks.13",
            "type": "Feature",
            "geometry": {"type": "MultiPolygon", "coordinates": [[[[144.99, -37.81], [145.0, -37.81], [145.0, -37.82], [144.99, -37.82], [144.99, -37.81]]]]},
            "properties": {"Type": "St Albans Car Park", "Num_Of_Bay": "0", "Parking_Re": None},
        }
        excluded_texts = [
            "No Stopping", "NO PARKING", "Bus Zone", "Loading Zone", "Taxi Zone",
            "Permit Zone", "Staff Excepted", "Council Vehicles Excepted",
            "Library Staff Excepted", "Drop Off Zone", "Clearway", "Disabled Only",
            "2P disabled only strawberry",
        ]
        excluded = [
            {
                "id": f"brimbank_carparks.{100 + index}",
                "type": "Feature",
                "geometry": {"type": "MultiPolygon", "coordinates": [[[[145.0, -37.78], [145.01, -37.78], [145.01, -37.79], [145.0, -37.79], [145.0, -37.78]]]]},
                "properties": {"Type": f"Excluded {index}", "Num_Of_Bay": "5", "Parking_Re": text},
            }
            for index, text in enumerate(excluded_texts)
        ]
        invalid = [
            {"id": "", "properties": {"Type": "No id", "Num_Of_Bay": "5"},
             "geometry": {"type": "MultiPolygon", "coordinates": [[[[145.0, -37.78], [145.01, -37.78], [145.01, -37.79], [145.0, -37.79], [145.0, -37.78]]]]}},
            {"properties": {"Type": "Missing id", "Num_Of_Bay": "5"},
             "geometry": {"type": "MultiPolygon", "coordinates": [[[[145.0, -37.78], [145.01, -37.78], [145.01, -37.79], [145.0, -37.79], [145.0, -37.78]]]]}},
            {"id": "brimbank_carparks.99", "properties": {"Type": "", "Num_Of_Bay": "5"},
             "geometry": {"type": "MultiPolygon", "coordinates": [[[[145.0, -37.78], [145.01, -37.78], [145.01, -37.79], [145.0, -37.79], [145.0, -37.78]]]]}},
            {"id": "brimbank_carparks.1000", "properties": {"Type": "No geometry", "Num_Of_Bay": "5"}, "geometry": None},
        ]

        records = build_brimbank_carpark_records(
            [eligible, null_capacity, *excluded, *invalid], checked_at="2026-09-19T00:00:00Z",
        )

        # Only the two eligible rows survive: 12 excluded by restriction text,
        # 4 rejected without inventing id/name/coordinate values.
        self.assertEqual(len(records), 2)
        by_id = {record["id"]: record for record in records}
        self.assertEqual(set(by_id), {"brimbank-brimbank_carparks.12", "brimbank-brimbank_carparks.13"})
        first = by_id["brimbank-brimbank_carparks.12"]
        self.assertEqual(first["name"], "Sunshine Car Park")
        self.assertEqual(first["municipality"], "Brimbank")
        self.assertEqual(first["kind"], "unknown")
        self.assertEqual(first["capacity"], 45)
        self.assertEqual(first["schedules"], [])
        self.assertEqual(first["tariffs"], [])
        self.assertEqual(first["classification"], "static_only")
        self.assertIsNone(first["predictionEvidence"])
        self.assertIsNone(first["accessibleSpaces"])
        # Geometry centroid wins over the conflicting Lat/Long strings.
        self.assertEqual(first["coordinate"], {"latitude": -37.784, "longitude": 145.004})
        self.assertIsNone(by_id["brimbank-brimbank_carparks.13"]["capacity"])
        self.assertEqual(first["source"]["id"], "brimbank-carparks")
        self.assertEqual(first["source"]["name"], "Brimbank City Council")
        self.assertEqual(first["source"]["sourceURL"], "https://data.gov.au/data/dataset/brimbank-carparks")
        self.assertEqual(first["source"]["licenseName"], "Creative Commons Attribution 2.5 Australia")
        self.assertEqual(first["source"]["licenseURL"], "https://creativecommons.org/licenses/by/2.5/au/")
        # Underlying resource last_modified; catalog metadata must not be used.
        self.assertEqual(first["source"]["datasetUpdatedAt"], "2019-03-12T00:00:00Z")
        self.assertEqual(first["source"]["checkedAt"], "2026-09-19T00:00:00Z")
        # No on/off-street inference and no restriction/tariff invention.
        dumped = json.dumps(records)
        self.assertNotIn("on_street", dumped)
        self.assertNotIn("off_street", dumped)
        self.assertNotIn("Parking_Re", dumped)

    def test_brimbank_disabled_uses_stable_ids_point_and_accessible_spaces(self):
        features = [
            {
                "id": "brimbank_disabled_car_parks.5",
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [144.99, -37.78]},
                "properties": {"Type": "Outside Library", "Location": "Sunshine", "Num_Of_Bay": 2},
            },
            {
                "id": "brimbank_disabled_car_parks.6",
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [145.0, -37.79]},
                "properties": {"Type": "Station front", "Location": "", "Num_Of_Bay": ""},
            },
        ]

        records = build_brimbank_disabled_records(features, checked_at="2026-09-19T00:00:00Z")

        self.assertEqual(len(records), 2)
        self.assertEqual(records[0]["id"], "brimbank-disabled-brimbank_disabled_car_parks.5")
        self.assertEqual(records[0]["name"], "Outside Library · Sunshine")
        self.assertEqual(records[0]["municipality"], "Brimbank")
        self.assertEqual(records[0]["coordinate"], {"latitude": -37.78, "longitude": 144.99})
        self.assertEqual(records[0]["kind"], "unknown")
        self.assertIsNone(records[0]["capacity"])
        self.assertEqual(records[0]["accessibleSpaces"], 2)
        self.assertEqual(records[0]["schedules"], [])
        self.assertEqual(records[0]["tariffs"], [])
        self.assertEqual(records[0]["classification"], "static_only")
        self.assertIsNone(records[0]["predictionEvidence"])
        self.assertEqual(records[1]["name"], "Station front")
        self.assertIsNone(records[1]["accessibleSpaces"])
        for record in records:
            self.assertEqual(record["source"]["id"], "brimbank-disabled-car-parks")
            self.assertEqual(record["source"]["name"], "Brimbank City Council")
            self.assertEqual(record["source"]["sourceURL"], "https://data.gov.au/data/dataset/brimbank-disabled-car-parks")
            self.assertEqual(record["source"]["licenseName"], "Creative Commons Attribution 2.5 Australia")
            self.assertEqual(record["source"]["licenseURL"], "https://creativecommons.org/licenses/by/2.5/au/")
            self.assertEqual(record["source"]["datasetUpdatedAt"], "2019-03-12T00:00:00Z")

    def test_brimbank_builders_reject_invalid_rows_without_inventing_values(self):
        carparks = build_brimbank_carpark_records(
            [
                {"id": "brimbank_carparks.1", "properties": {"Type": "No geometry", "Num_Of_Bay": "3"}, "geometry": None},
                {"id": "brimbank_carparks.2", "properties": {"Type": "Nowhere", "Num_Of_Bay": "3"},
                 "geometry": {"type": "Point", "coordinates": [0.0, 0.0]}},
            ],
            checked_at="2026-09-19T00:00:00Z",
        )
        disabled = build_brimbank_disabled_records(
            [
                {"properties": {"Type": "Missing id", "Location": "X", "Num_Of_Bay": "1"},
                 "geometry": {"type": "Point", "coordinates": [144.99, -37.78]}},
                {"id": "brimbank_disabled_car_parks.9", "properties": {"Type": "", "Location": "", "Num_Of_Bay": "1"},
                 "geometry": None},
            ],
            checked_at="2026-09-19T00:00:00Z",
        )

        # Second disabled row falls back to the generic accessible label but has
        # no coordinate, so it is still rejected rather than invented.
        self.assertEqual(carparks, [])
        self.assertEqual(disabled, [])

    def test_greater_dandenong_curated_facilities_lock_coordinates_sources_and_semantics(self):
        records = {record["id"]: record for record in curated_official_records("2026-09-19T00:00:00Z")}
        ids = [
            "greater-dandenong-number-8",
            "greater-dandenong-thomas-street",
            "greater-dandenong-walker-street",
            "greater-dandenong-carroll-lane",
        ]
        for identifier in ids:
            self.assertIn(identifier, records)
            record = records[identifier]
            self.assertEqual(record["municipality"], "Greater Dandenong")
            self.assertEqual(record["kind"], "off_street")
            self.assertEqual(record["classification"], "static_only")
            self.assertIsNone(record["predictionEvidence"])
            self.assertIsNone(record["accessibleSpaces"])
            self.assertEqual(record["source"]["licenseName"], "Official council facility page")
            self.assertIsNone(record["source"]["licenseURL"])
            self.assertIsNone(record["source"]["datasetUpdatedAt"])
            self.assertEqual(record["source"]["checkedAt"], "2026-09-19T00:00:00Z")

        number_8 = records["greater-dandenong-number-8"]
        self.assertEqual(number_8["name"], "Number 8 Balmoral Avenue Multi-deck Car Park")
        self.assertEqual(number_8["coordinate"], {"latitude": -37.949639, "longitude": 145.151733})
        self.assertEqual(number_8["source"]["sourceURL"], "https://www.greaterdandenong.vic.gov.au/number-8-car-park")
        # "More than 500" is not an exact capacity, so it remains unknown.
        self.assertIsNone(number_8["capacity"])
        self.assertEqual(number_8["schedules"][0]["days"], [1, 2, 3, 4, 5, 6, 7])
        self.assertEqual((number_8["schedules"][0]["startMinutes"], number_8["schedules"][0]["endMinutes"]), (420, 1380))
        self.assertEqual(number_8["tariffs"], [])

        thomas = records["greater-dandenong-thomas-street"]
        self.assertEqual(thomas["coordinate"], {"latitude": -37.986932, "longitude": 145.212884})
        self.assertEqual(thomas["source"]["sourceURL"], "https://www.greaterdandenong.vic.gov.au/council-car-parks/thomas-street-multi-deck-car-park")
        self.assertIsNone(thomas["capacity"])
        self.assertEqual((thomas["schedules"][0]["startMinutes"], thomas["schedules"][0]["endMinutes"]), (360, 1320))
        self.assertEqual(thomas["schedules"][0]["days"], [2, 3, 4, 5, 6, 7])
        self.assertEqual((thomas["schedules"][1]["startMinutes"], thomas["schedules"][1]["endMinutes"]), (540, 1320))
        self.assertEqual(thomas["tariffs"], [])

        walker = records["greater-dandenong-walker-street"]
        self.assertEqual(walker["coordinate"], {"latitude": -37.987707, "longitude": 145.211924})
        self.assertEqual(walker["source"]["sourceURL"], "https://www.greaterdandenong.vic.gov.au/council-car-parks/walker-street-multi-deck-car-park")
        self.assertIsNone(walker["capacity"])
        # Cross-midnight Mon-Sat uses end > 24h, matching the Whitehorse pattern.
        self.assertEqual((walker["schedules"][0]["startMinutes"], walker["schedules"][0]["endMinutes"]), (360, 1500))
        self.assertEqual((walker["schedules"][1]["startMinutes"], walker["schedules"][1]["endMinutes"]), (540, 1380))
        self.assertEqual(walker["tariffs"], [])

        carroll = records["greater-dandenong-carroll-lane"]
        self.assertEqual(carroll["coordinate"], {"latitude": -37.989876, "longitude": 145.207576})
        self.assertEqual(carroll["source"]["sourceURL"], "https://www.greaterdandenong.vic.gov.au/council-car-parks/carroll-lane-car-park")
        self.assertIsNone(carroll["capacity"])
        self.assertEqual(carroll["schedules"], [{"days": [1, 2, 3, 4, 5, 6, 7], "startMinutes": 0, "endMinutes": 1440,
                                                 "maxStayMinutes": None, "restrictionText": "Open 24 hours",
                                                 "appliesOnPublicHolidays": False, "outsideWindowMeansUnrestricted": False,
                                                 "unparsedCondition": None}])
        # Free applies only to public-transport users, so no unconditional tariff.
        self.assertEqual(carroll["tariffs"], [])


def _lga_feature_collection(name, code, rings, *, holes=None, official_name=None):
    return {
        "type": "FeatureCollection",
        "features": [_lga_feature(name, code, rings, holes=holes, official_name=official_name)],
    }


def _lga_feature(name, code, rings, *, holes=None, official_name=None):
    coordinates = list(rings)
    if holes:
        coordinates.extend(holes)
    return {
        "type": "Feature",
        "properties": {
            "lga_code": code,
            "lga_name": name,
            "lga_official_name": official_name or f"{name} CITY",
        },
        "geometry": {"type": "Polygon", "coordinates": coordinates},
    }


def _labelled_record(identifier, municipality, *, latitude, longitude):
    return {
        "id": identifier,
        "name": "Mapped parking",
        "municipality": municipality,
        "coordinate": {"latitude": latitude, "longitude": longitude},
        "kind": "off_street",
        "archetype": "general",
        "capacity": 4,
        "accessibleSpaces": None,
        "schedules": [{"days": [2], "maxStayMinutes": 120}],
        "tariffs": [{"hourlyCents": 0}],
        "source": {
            "id": "openstreetmap-victoria-parking",
            "name": "OpenStreetMap contributors",
            "licenseName": "Open Database License 1.0",
        },
        "classification": "static_only",
        "predictionEvidence": None,
    }


if __name__ == "__main__":
    unittest.main()
