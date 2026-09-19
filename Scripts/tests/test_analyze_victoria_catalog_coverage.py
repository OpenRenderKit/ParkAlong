import unittest

from Scripts.analyze_victoria_catalog_coverage import (
    coverage_band,
    geometry_contains,
    lga_areas_from_geojson,
    matching_lga,
)


def _square_with_hole():
    return {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "properties": {
                    "lga_code": "351",
                    "lga_name": "MERRI-BEK",
                    "lga_official_name": "MERRI-BEK CITY",
                },
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [
                        [[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]],
                        [[4, 4], [6, 4], [6, 6], [4, 6], [4, 4]],
                    ],
                },
            }
        ],
    }


def _multipolygon_with_hole():
    return {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "properties": {
                    "lga_code": "999",
                    "lga_name": "TEST",
                    "lga_official_name": "TEST CITY",
                },
                "geometry": {
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
                },
            }
        ],
    }


class VictoriaCatalogCoverageTests(unittest.TestCase):
    def test_polygon_hole_is_not_counted_as_inside(self):
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

    def test_matching_lga_treats_holes_and_outside_points_as_unmatched(self):
        areas = lga_areas_from_geojson(_square_with_hole())

        self.assertEqual("MERRI-BEK", matching_lga(areas, (2, 2))["name"])
        self.assertIsNone(matching_lga(areas, (5, 5)))
        self.assertIsNone(matching_lga(areas, (12, 2)))
        self.assertEqual("351", areas[0]["code"])
        self.assertEqual("MERRI-BEK CITY", areas[0]["officialName"])

    def test_multipolygon_with_hole_matches_each_part_and_respects_holes(self):
        areas = lga_areas_from_geojson(_multipolygon_with_hole())
        geometry = areas[0]["geometry"]

        self.assertTrue(geometry_contains(geometry, (2, 2)))
        self.assertFalse(geometry_contains(geometry, (5, 5)))
        self.assertTrue(geometry_contains(geometry, (25, 25)))
        self.assertFalse(geometry_contains(geometry, (15, 15)))
        self.assertEqual("TEST", matching_lga(areas, (2, 2))["name"])
        self.assertIsNone(matching_lga(areas, (5, 5)))
        self.assertEqual("TEST", matching_lga(areas, (25, 25))["name"])
        self.assertIsNone(matching_lga(areas, (15, 15)))

    def test_coverage_band_does_not_treat_osm_volume_as_authority_coverage(self):
        self.assertEqual("zero", coverage_band({"recordCount": 0, "authoritativeRecordCount": 0}))
        self.assertEqual(
            "extremely_thin",
            coverage_band({"recordCount": 9, "authoritativeRecordCount": 9}),
        )
        self.assertEqual(
            "discovery_only",
            coverage_band({"recordCount": 500, "authoritativeRecordCount": 0}),
        )
        self.assertEqual(
            "authority_thin",
            coverage_band({"recordCount": 500, "authoritativeRecordCount": 9}),
        )
        self.assertEqual(
            "authority_backed",
            coverage_band({"recordCount": 10, "authoritativeRecordCount": 10}),
        )


if __name__ == "__main__":
    unittest.main()
