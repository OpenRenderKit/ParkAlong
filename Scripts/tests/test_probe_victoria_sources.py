import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from Scripts.probe_victoria_sources import (
    classify_occupancy_records,
    probe_melbourne,
    summarize_maribyrnong,
)


class OccupancyClassificationTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 8, 22, 5, 0, tzinfo=timezone.utc)

    def test_fresh_rows_are_live_only_when_timestamp_and_state_are_trusted(self):
        result = classify_occupancy_records(
            [
                {"updated": "2026-08-22T04:58:00Z", "state": "Present"},
                {"updated": "2026-08-22T04:57:00Z", "state": "Unoccupied"},
                {"updated": "2026-08-20T04:57:00Z", "state": "Unoccupied"},
                {"updated": "2026-08-22T04:56:00Z", "state": "Unknown"},
            ],
            timestamp_field="updated",
            occupancy_field="state",
            occupied_values={"Present"},
            vacant_values={"Unoccupied"},
            now=self.now,
        )

        self.assertEqual("verified_live_occupancy", result["classification"])
        self.assertEqual(2, result["trustedRows"])
        self.assertEqual(2, result["rejectedRows"])
        self.assertEqual("2026-08-22T04:58:00Z", result["newestTrustedTimestamp"])

    def test_successful_but_old_feed_is_stale_not_live(self):
        result = classify_occupancy_records(
            [{"updated": "2022-08-23T23:15:04.629Z", "state": "5"}],
            timestamp_field="updated",
            occupancy_field="state",
            occupied_values={"5"},
            vacant_values={"0"},
            now=self.now,
        )

        self.assertEqual("stale_or_historical", result["classification"])
        self.assertEqual(0, result["trustedRows"])
        self.assertEqual("2022-08-23T23:15:04.629Z", result["newestObservedTimestamp"])

    def test_future_timestamp_fails_closed_as_ambiguous(self):
        result = classify_occupancy_records(
            [{"updated": "2026-08-22T06:00:00Z", "state": "Unoccupied"}],
            timestamp_field="updated",
            occupancy_field="state",
            occupied_values={"Present"},
            vacant_values={"Unoccupied"},
            now=self.now,
        )

        self.assertEqual("ambiguous_or_unverified", result["classification"])
        self.assertEqual(0, result["trustedRows"])

    def test_unknown_states_do_not_become_live_from_fresh_metadata(self):
        result = classify_occupancy_records(
            [{"updated": "2026-08-22T04:59:00Z", "state": None}],
            timestamp_field="updated",
            occupancy_field="state",
            occupied_values={"Present"},
            vacant_values={"Unoccupied"},
            now=self.now,
        )

        self.assertEqual("ambiguous_or_unverified", result["classification"])
        self.assertEqual(0, result["trustedRows"])


class StaticSourceSummaryTests(unittest.TestCase):
    def test_blocked_historical_map_does_not_hide_current_static_layers(self):
        result = summarize_maribyrnong(
            {"regularBays": 10379, "accessibleBays": 191},
            historical_error="HTTPError: HTTP Error 403: Forbidden",
        )

        self.assertEqual("static_locations_or_restrictions", result["classification"])
        self.assertEqual(10379, result["parkingExplorerCounts"]["regularBays"])
        self.assertEqual("unavailable", result["historicalMap"]["status"])
        self.assertEqual("not exposed by these anonymous endpoints", result["occupancy"])


class MelbourneProbeTests(unittest.TestCase):
    @patch("Scripts.probe_victoria_sources._request_json")
    def test_probe_counts_fresh_bays_across_the_full_municipal_dataset(self, request_json):
        now = datetime.now(timezone.utc)
        newest = (now - timedelta(minutes=2)).isoformat()
        slightly_older = (now - timedelta(minutes=3)).isoformat()

        def response(url, **_):
            if url.endswith("on-street-parking-bay-sensors"):
                return {
                    "metas": {
                        "default": {
                            "records_count": 6,
                            "bbox": {"type": "Feature", "geometry": {"type": "Polygon", "coordinates": []}},
                        }
                    }
                }
            return {
                "results": [
                    {
                        "status_description": "Present",
                        "bay_count": 3,
                        "newest_timestamp": newest,
                    },
                    {
                        "status_description": "Unoccupied",
                        "bay_count": 2,
                        "newest_timestamp": slightly_older,
                    },
                    {
                        "status_description": "Unknown",
                        "bay_count": 1,
                        "newest_timestamp": newest,
                    },
                ]
            }

        request_json.side_effect = response

        result = probe_melbourne(timeout=1)

        self.assertEqual("verified_live_occupancy", result["classification"])
        self.assertEqual("City of Melbourne municipality", result["scope"])
        self.assertEqual(6, result["catalogRows"])
        self.assertEqual(5, result["trustedRows"])
        self.assertEqual(3, result["present"])
        self.assertEqual(2, result["unoccupied"])
        self.assertEqual(1, result["rejectedRows"])


if __name__ == "__main__":
    unittest.main()
