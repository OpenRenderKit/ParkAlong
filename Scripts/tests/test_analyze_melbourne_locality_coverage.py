import unittest

from Scripts.analyze_melbourne_locality_coverage import (
    MELBOURNE_TARGET_LOCALITIES,
    audit_locality_coverage,
    compare_locality_coverage,
)


def _locality_feature(ufi, raw_name, x0, y0, x1, y1):
    return {
        "type": "Feature",
        "properties": {
            "ufi": ufi,
            "locality_name": raw_name,
            "gazetted_locality_name": raw_name,
        },
        "geometry": {
            "type": "Polygon",
            "coordinates": [[[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]],
        },
    }


def _tiny_boundaries():
    return {
        "type": "FeatureCollection",
        "features": [
            _locality_feature(1, "GLEN WAVERLEY", 145.10, -37.90, 145.18, -37.84),
            _locality_feature(2, "RICHMOND", 144.98, -37.83, 145.02, -37.80),
        ],
    }


def _record(identifier, latitude, longitude, *, source_id="openstreetmap-victoria-parking",
            capacity=None, accessible=None, schedules=None, tariffs=None):
    return {
        "id": identifier,
        "name": "Mapped parking",
        "municipality": "Monash",
        "coordinate": {"latitude": latitude, "longitude": longitude},
        "kind": "off_street",
        "archetype": "general",
        "capacity": capacity,
        "accessibleSpaces": accessible,
        "schedules": schedules or [],
        "tariffs": tariffs or [],
        "source": {"id": source_id, "name": source_id},
        "classification": "static_only",
        "predictionEvidence": None,
    }


EXPECTED_TARGETS = [
    "Burwood",
    "Kew",
    "Hawthorn",
    "Glen Waverley",
    "Tarneit",
    "South Yarra",
    "Elsternwick",
    "Box Hill",
    "Clayton",
    "Springvale",
    "Camberwell",
    "Canterbury",
    "Balwyn",
    "Surrey Hills",
    "Blackburn",
    "Nunawading",
    "Mount Waverley",
    "Oakleigh",
    "Chadstone",
    "Dandenong",
    "Noble Park",
    "Prahran",
    "Windsor",
    "Malvern",
    "Armadale",
    "Toorak",
    "Richmond",
    "Cremorne",
    "Fitzroy",
    "Collingwood",
    "St Kilda",
    "South Melbourne",
    "Caulfield",
    "Carnegie",
    "Bentleigh",
    "Brighton",
    "Moorabbin",
    "Cheltenham",
    "Mordialloc",
    "Brunswick",
    "Coburg",
    "Northcote",
    "Preston",
    "Reservoir",
    "Moonee Ponds",
    "Essendon",
    "Footscray",
    "Yarraville",
    "Williamstown",
    "Werribee",
    "Point Cook",
    "Hoppers Crossing",
    "Sunshine",
    "St Albans",
    "Melton",
    "Craigieburn",
    "Broadmeadows",
    "Epping",
    "Ringwood",
    "Doncaster",
    "Frankston",
    "Cranbourne",
]


class SearchTargetTests(unittest.TestCase):
    def test_target_list_matches_user_spelling_exactly(self):
        self.assertEqual(MELBOURNE_TARGET_LOCALITIES, EXPECTED_TARGETS)
        for spelling in (
            "Glen Waverley",
            "Mount Waverley",
            "South Yarra",
            "Surrey Hills",
            "St Kilda",
            "St Albans",
            "Moonee Ponds",
            "Hoppers Crossing",
            "Point Cook",
        ):
            self.assertIn(spelling, MELBOURNE_TARGET_LOCALITIES)

    def test_targets_use_natural_case_not_uppercase_or_invented_areas(self):
        for name in MELBOURNE_TARGET_LOCALITIES:
            self.assertEqual(name, name.strip())
            self.assertNotEqual(name, name.upper() if len(name) > 4 else "SKIP")
        # No invented neighbourhoods beyond the explicit user set.
        self.assertEqual(len(MELBOURNE_TARGET_LOCALITIES), len(set(MELBOURNE_TARGET_LOCALITIES)))


class AnalyzerMetricsTests(unittest.TestCase):
    def test_before_after_metrics_use_same_polygons(self):
        geojson = _tiny_boundaries()
        before = [
            _record("before-osm-glen", -37.87, 145.14),
        ]
        after = [
            _record("after-osm-glen", -37.87, 145.14),
            _record(
                "after-authority-glen",
                -37.87,
                145.15,
                source_id="city-of-monash",
                capacity=50,
                accessible=2,
                schedules=[{"days": [2]}],
                tariffs=[{"hourlyCents": 100}],
            ),
            _record("after-outside", -38.50, 144.50),
        ]
        result = compare_locality_coverage(
            before, after, geojson, targets=["Glen Waverley", "Richmond"]
        )
        self.assertEqual(result["localityPolygonCount"], 2)
        self.assertEqual(result["beforeCatalogRecordCount"], 1)
        self.assertEqual(result["afterCatalogRecordCount"], 3)
        self.assertEqual(result["beforeAssignedRecordCount"], 1)
        self.assertEqual(result["afterAssignedRecordCount"], 2)
        self.assertEqual(result["afterOutsideRecordCount"], 1)

        changes = {row["name"]: row for row in result["changes"]}
        self.assertEqual(changes["Glen Waverley"]["beforeRecordCount"], 1)
        self.assertEqual(changes["Glen Waverley"]["afterRecordCount"], 2)
        self.assertEqual(changes["Glen Waverley"]["deltaRecordCount"], 1)
        self.assertEqual(changes["Glen Waverley"]["afterAuthoritativeRecordCount"], 1)
        self.assertEqual(changes["Richmond"]["afterRecordCount"], 0)

        after_audit = result["after"]
        glen = next(row for row in after_audit["targets"] if row["name"] == "Glen Waverley")
        self.assertEqual(glen["recordCount"], 2)
        self.assertEqual(glen["authoritativeRecordCount"], 1)
        self.assertEqual(glen["accessibleRecordCount"], 1)
        self.assertEqual(glen["capacityRecordCount"], 1)
        self.assertEqual(glen["scheduleRecordCount"], 1)
        self.assertEqual(glen["tariffRecordCount"], 1)
        self.assertEqual(
            glen["sourceIds"], ["city-of-monash", "openstreetmap-victoria-parking"]
        )
        self.assertTrue(glen["polygonPresent"])

    def test_single_audit_reports_labeled_and_unmatched_totals(self):
        geojson = _tiny_boundaries()
        records = [
            _record("in-glen", -37.87, 145.14, source_id="city-of-monash"),
            _record("outside", -38.50, 144.50),
        ]
        records[0]["locality"] = "Glen Waverley"
        audit = audit_locality_coverage(records, geojson, targets=["Glen Waverley"])
        self.assertEqual(audit["catalogRecordCount"], 2)
        self.assertEqual(audit["spatiallyAssignedRecordCount"], 1)
        self.assertEqual(audit["outsidePolygonRecordCount"], 1)
        self.assertEqual(audit["localityFieldLabeledCount"], 1)
        self.assertEqual(audit["localityFieldUnmatchedCount"], 1)
        self.assertEqual(audit["targets"][0]["recordCount"], 1)
        self.assertEqual(audit["targets"][0]["authoritativeRecordCount"], 1)


if __name__ == "__main__":
    unittest.main()
