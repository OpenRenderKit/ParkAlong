import unittest

from Scripts.analyze_victoria_catalog_coverage import (
    VICMAP_LOCALITY_EXPECTED_COUNT,
    build_locality_index,
    geometry_contains,
    locality_areas_from_geojson,
    locality_candidates,
    locality_query_params,
    matching_locality,
    matching_locality_bruteforce,
    merge_locality_pages,
    natural_locality_name,
    validate_locality_geojson,
)
from Scripts.generate_victoria_static_catalog import assign_spatial_locality


def _locality_feature(ufi, raw_name, coordinates, *, geometry_type="Polygon"):
    return {
        "type": "Feature",
        "properties": {
            "ufi": ufi,
            "locality_name": raw_name,
            "gazetted_locality_name": raw_name,
        },
        "geometry": {"type": geometry_type, "coordinates": coordinates},
    }


def _small_geojson():
    return {
        "type": "FeatureCollection",
        "features": [
            _locality_feature(
                1,
                "GLEN WAVERLEY",
                [[
                    [145.10, -37.90],
                    [145.18, -37.90],
                    [145.18, -37.84],
                    [145.10, -37.84],
                    [145.10, -37.90],
                ]],
            ),
            _locality_feature(
                2,
                "MOUNT WAVERLEY",
                [[
                    [145.10, -37.98],
                    [145.18, -37.98],
                    [145.18, -37.92],
                    [145.10, -37.92],
                    [145.10, -37.98],
                ]],
            ),
        ],
    }


def _parking_record(identifier, latitude, longitude, *, name="Mapped parking"):
    return {
        "id": identifier,
        "name": name,
        "municipality": "Monash",
        "coordinate": {"latitude": latitude, "longitude": longitude},
        "kind": "off_street",
        "archetype": "general",
        "capacity": 10,
        "accessibleSpaces": 1,
        "schedules": [{"days": [2], "maxStayMinutes": 120}],
        "tariffs": [{"hourlyCents": 0}],
        "source": {"id": "openstreetmap-victoria-parking", "name": "OpenStreetMap contributors"},
        "classification": "static_only",
        "predictionEvidence": None,
    }


class LocalityFetchTests(unittest.TestCase):
    def test_query_params_use_4326_only_needed_fields_and_compact_geometry(self):
        params = locality_query_params(2000, 2000)
        self.assertEqual(params["outSR"], "4326")
        self.assertEqual(params["f"], "geojson")
        self.assertEqual(params["where"], "1=1")
        self.assertEqual(params["returnGeometry"], "true")
        out_fields = {field.strip() for field in params["outFields"].split(",")}
        self.assertEqual(out_fields, {"ufi", "locality_name", "gazetted_locality_name"})
        self.assertEqual(params["geometryPrecision"], "5")
        offset = float(params["maxAllowableOffset"])
        self.assertGreater(offset, 0)
        self.assertLessEqual(offset, 0.0001)
        self.assertEqual(params["orderByFields"], "ufi ASC")
        self.assertEqual(params["resultOffset"], "2000")
        self.assertEqual(params["resultRecordCount"], "2000")

    def test_pagination_merge_combines_pages_in_order(self):
        page_one = {
            "type": "FeatureCollection",
            "features": [
                _locality_feature(1, "A", [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]]),
                _locality_feature(2, "B", [[[2, 2], [3, 2], [3, 3], [2, 3], [2, 2]]]),
            ],
        }
        page_two = {
            "type": "FeatureCollection",
            "features": [
                _locality_feature(3, "C", [[[4, 4], [5, 4], [5, 5], [4, 5], [4, 4]]]),
            ],
        }
        merged = merge_locality_pages([page_one, page_two])
        self.assertEqual(
            [feature["properties"]["ufi"] for feature in merged["features"]], [1, 2, 3]
        )

    def test_full_result_validation_fails_closed_on_partial_page(self):
        tiny = {
            "type": "FeatureCollection",
            "features": [
                _locality_feature(1, "GLEN WAVERLEY", [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]]),
            ],
        }
        with self.assertRaises(RuntimeError):
            validate_locality_geojson(tiny, min_count=2, expected_count=3)
        # Default production threshold must also reject a single page.
        with self.assertRaises(RuntimeError):
            validate_locality_geojson(tiny)
        self.assertGreaterEqual(VICMAP_LOCALITY_EXPECTED_COUNT, 2973)

    def test_full_result_validation_accepts_sane_result(self):
        geojson = {
            "type": "FeatureCollection",
            "features": [
                _locality_feature(1, "GLEN WAVERLEY", [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]]),
                _locality_feature(2, "MOUNT WAVERLEY", [[[2, 2], [3, 2], [3, 3], [2, 3], [2, 2]]]),
                _locality_feature(3, "ST KILDA", [[[4, 4], [5, 4], [5, 5], [4, 5], [4, 4]]]),
            ],
        }
        validate_locality_geojson(geojson, min_count=3, expected_count=3)

    def test_validation_rejects_missing_names_ufi_and_geometry(self):
        base = [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]]
        missing_name = {
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "properties": {"ufi": 1, "locality_name": "   ", "gazetted_locality_name": ""},
                    "geometry": {"type": "Polygon", "coordinates": base},
                }
            ],
        }
        missing_ufi = {
            "type": "FeatureCollection",
            "features": [_locality_feature(None, "GLEN WAVERLEY", base)],
        }
        bad_geometry = {
            "type": "FeatureCollection",
            "features": [_locality_feature(1, "GLEN WAVERLEY", [[0, 0], [1, 1]], geometry_type="Point")],
        }
        for geojson in (missing_name, missing_ufi, bad_geometry):
            with self.assertRaises(RuntimeError):
                validate_locality_geojson(geojson, min_count=1, expected_count=1)


class LocalityGeometryTests(unittest.TestCase):
    def test_polygon_hole_is_respected(self):
        geometry = {
            "type": "Polygon",
            "coordinates": [
                [[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]],
                [[4, 4], [6, 4], [6, 6], [4, 6], [4, 4]],
            ],
        }
        self.assertTrue(geometry_contains(geometry, (2, 2)))
        self.assertFalse(geometry_contains(geometry, (5, 5)))
        self.assertFalse(geometry_contains(geometry, (12, 2)))

    def test_multipolygon_hole_is_respected(self):
        geometry = {
            "type": "MultiPolygon",
            "coordinates": [
                [
                    [[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]],
                    [[4, 4], [6, 4], [6, 6], [4, 6], [4, 4]],
                ],
                [
                    [[20, 20], [30, 20], [30, 30], [20, 30], [20, 20]],
                ],
            ],
        }
        self.assertTrue(geometry_contains(geometry, (2, 2)))
        self.assertFalse(geometry_contains(geometry, (5, 5)))
        self.assertTrue(geometry_contains(geometry, (25, 25)))
        self.assertFalse(geometry_contains(geometry, (15, 15)))

    def test_grid_candidates_match_bruteforce(self):
        geojson = {
            "type": "FeatureCollection",
            "features": [
                _locality_feature(1, "ALPHA", [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]]),
                _locality_feature(
                    2,
                    "BETA",
                    [
                        [
                            [[10, 10], [11, 10], [11, 11], [10, 11], [10, 10]],
                            [[10.4, 10.4], [10.6, 10.4], [10.6, 10.6], [10.4, 10.6], [10.4, 10.4]],
                        ],
                        [
                            [[20, 20], [21, 20], [21, 21], [20, 21], [20, 20]],
                        ],
                    ],
                    geometry_type="MultiPolygon",
                ),
                _locality_feature(3, "GAMMA", [[[50, 50], [51, 50], [51, 51], [50, 51], [50, 50]]]),
            ],
        }
        areas = locality_areas_from_geojson(geojson)
        index = build_locality_index(areas, cell_size_deg=0.5)
        points = [(0.5, 0.5), (10.5, 10.5), (10.2, 10.2), (20.5, 20.5), (50.5, 50.5), (5, 5), (100, 100)]
        for lon, lat in points:
            expected = matching_locality_bruteforce(areas, (lon, lat))
            actual = matching_locality(index, (lon, lat))
            self.assertEqual(
                (actual or {}).get("name"),
                (expected or {}).get("name"),
                msg=f"point {(lon, lat)}",
            )
        # Grid must narrow candidates well below a full scan for a local point.
        candidates = locality_candidates(index, (0.5, 0.5))
        self.assertLess(len(candidates), len(areas))
        self.assertGreaterEqual(len(candidates), 1)

    def test_boundary_and_outside_behavior_do_not_crash(self):
        geojson = {
            "type": "FeatureCollection",
            "features": [
                _locality_feature(1, "GLEN WAVERLEY", [[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]]]),
            ],
        }
        areas = locality_areas_from_geojson(geojson)
        index = build_locality_index(areas)
        self.assertIsNone(matching_locality(index, (20, 20)))
        self.assertIsNone(matching_locality_bruteforce(areas, (20, 20)))
        # A point exactly on the edge must not raise; either outcome is acceptable.
        try:
            edge_indexed = matching_locality(index, (0, 5))
            edge_brute = matching_locality_bruteforce(areas, (0, 5))
        except Exception as error:  # pragma: no cover
            self.fail(f"boundary point raised {error!r}")
        self.assertEqual(
            (edge_indexed or {}).get("name"), (edge_brute or {}).get("name")
        )


class LocalityNamingTests(unittest.TestCase):
    def test_natural_names_cover_melbourne_cases(self):
        self.assertEqual(natural_locality_name("GLEN WAVERLEY"), "Glen Waverley")
        self.assertEqual(natural_locality_name("MOUNT WAVERLEY"), "Mount Waverley")
        self.assertEqual(natural_locality_name("SOUTH YARRA"), "South Yarra")
        self.assertEqual(natural_locality_name("ST KILDA"), "St Kilda")
        self.assertEqual(natural_locality_name("ST ALBANS"), "St Albans")
        self.assertEqual(natural_locality_name("SURREY HILLS"), "Surrey Hills")
        self.assertEqual(natural_locality_name("MOONEE PONDS"), "Moonee Ponds")
        self.assertEqual(natural_locality_name("HOPPERS CROSSING"), "Hoppers Crossing")
        self.assertEqual(natural_locality_name("MCCRAE"), "McCrae")
        self.assertEqual(natural_locality_name("MCKINNON"), "McKinnon")
        self.assertEqual(natural_locality_name("FOO-BAR"), "Foo-Bar")
        self.assertEqual(natural_locality_name("O'BRIEN"), "O'Brien")
        self.assertEqual(natural_locality_name("  SOUTH   YARRA  "), "South Yarra")
        self.assertEqual(natural_locality_name("Glen Waverley"), "Glen Waverley")
        self.assertEqual(natural_locality_name(""), "")
        self.assertEqual(natural_locality_name("   "), "")

    def test_prefers_gazetted_name_and_normalizes(self):
        geojson = {
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "properties": {
                        "ufi": 9,
                        "locality_name": "OLD NAME",
                        "gazetted_locality_name": "GLEN WAVERLEY",
                    },
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]],
                    },
                }
            ],
        }
        areas = locality_areas_from_geojson(geojson)
        self.assertEqual(areas[0]["name"], "Glen Waverley")
        self.assertEqual(areas[0]["rawName"], "GLEN WAVERLEY")
        self.assertEqual(areas[0]["ufi"], 9)


class LocalityAssignmentTests(unittest.TestCase):
    def test_assign_adds_locality_only_from_containment(self):
        geojson = _small_geojson()
        inside = _parking_record("inside", -37.87, 145.14)
        outside = _parking_record(
            "outside", -37.70, 145.00, name="Glen Waverley Car Park"
        )
        municipality_before = inside["municipality"]
        source_before = dict(inside["source"])
        schedules_before = inside["schedules"]
        tariffs_before = inside["tariffs"]

        assign_spatial_locality([inside, outside], geojson, min_count=1)

        self.assertEqual(inside["locality"], "Glen Waverley")
        self.assertEqual(inside["municipality"], municipality_before)
        self.assertEqual(inside["source"], source_before)
        self.assertIs(inside["schedules"], schedules_before)
        self.assertIs(inside["tariffs"], tariffs_before)
        self.assertEqual(inside["id"], "inside")
        self.assertEqual(inside["classification"], "static_only")
        # Name mentions Glen Waverley but the point is outside every polygon:
        # it must not be guessed, it stays null.
        self.assertIsNone(outside["locality"])

    def test_holes_and_outside_leave_locality_null(self):
        geojson = {
            "type": "FeatureCollection",
            "features": [
                _locality_feature(
                    1,
                    "BRUNSWICK",
                    [
                        [[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]],
                        [[4, 4], [6, 4], [6, 6], [4, 6], [4, 4]],
                    ],
                ),
            ],
        }
        inside = _parking_record("hole-inside", 2, 2)
        hole = _parking_record("hole-hole", 5, 5)
        outside = _parking_record("hole-outside", 12, 2)
        assign_spatial_locality([inside, hole, outside], geojson, min_count=1)
        self.assertEqual(inside["locality"], "Brunswick")
        self.assertIsNone(hole["locality"])
        self.assertIsNone(outside["locality"])

    def test_non_overwrite_and_provenance_preservation(self):
        geojson = _small_geojson()
        existing = _parking_record("existing", -37.87, 145.14)
        existing["locality"] = "Existing Suburb"
        schedules = existing["schedules"]
        tariffs = existing["tariffs"]
        source = existing["source"]
        assign_spatial_locality([existing], geojson, min_count=1)
        self.assertEqual(existing["locality"], "Existing Suburb")
        self.assertIs(existing["schedules"], schedules)
        self.assertIs(existing["tariffs"], tariffs)
        self.assertIs(existing["source"], source)
        self.assertEqual(existing["municipality"], "Monash")
        self.assertEqual(existing["kind"], "off_street")

    def test_partial_geojson_fails_closed(self):
        partial = {
            "type": "FeatureCollection",
            "features": [
                _locality_feature(1, "GLEN WAVERLEY", [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]]),
            ],
        }
        record = _parking_record("any", 0.5, 0.5)
        with self.assertRaises(RuntimeError):
            assign_spatial_locality([record], partial)
        # Failed-closed run must not have invented a label.
        self.assertNotIn("locality", record)


if __name__ == "__main__":
    unittest.main()
