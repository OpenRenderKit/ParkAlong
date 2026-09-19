import unittest

from Scripts.analyze_victoria_catalog_coverage import coverage_band, geometry_contains


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
