import json
import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from generate_victoria_static_catalog import (  # noqa: E402
    build_ballarat_records,
    build_boroondara_records,
    build_casey_records,
    build_maribyrnong_records,
    build_osm_records,
    deduplicate_records,
    geometry_centroid,
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


if __name__ == "__main__":
    unittest.main()
