import csv
import io
import tempfile
import subprocess
import sys
import unittest
import zipfile
from pathlib import Path

from Scripts.generate_prediction import aggregate_archive, normalize_segment
from Scripts.generate_metadata import build_metadata


class PredictionGeneratorTests(unittest.TestCase):
    def test_metadata_generator_supports_direct_cli_invocation(self):
        result = subprocess.run(
            [sys.executable, "Scripts/generate_metadata.py", "--help"],
            cwd=Path(__file__).parents[2],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_metadata_join_uses_real_field_names_and_sensor_centroid(self):
        sensors = [
            {"zone_number": 7001, "kerbsideid": 11, "location": {"lat": -37.81, "lon": 144.96}},
            {"zone_number": 7001, "kerbsideid": 12, "location": {"lat": -37.83, "lon": 144.98}},
        ]
        streets = [{"parkingzone": 7001, "onstreet": "Collins Street", "streetfrom": "Swanston Street", "streetto": "Russell Street"}]

        metadata = build_metadata(sensors, streets)

        self.assertEqual(metadata[0]["zoneNumber"], 7001)
        self.assertEqual(metadata[0]["sensorIDs"], [11, 12])
        self.assertEqual(metadata[0]["sensorCount"], 2)
        self.assertAlmostEqual(metadata[0]["coordinate"]["latitude"], -37.82)
        self.assertEqual(metadata[0]["segmentKey"], normalize_segment("Collins Street", "Swanston Street", "Russell Street"))

    def test_normalization_is_order_independent_for_cross_streets(self):
        left = normalize_segment("Collins Street", "Swanston Street", "Russell Street")
        right = normalize_segment("COLLINS ST.", "Russell St", "Swanston St")
        self.assertEqual(left, right)

    def test_streams_archive_into_hand_checked_occupancy_and_turnover(self):
        headers = [
            "DeviceId", "ArrivalTime", "DepartureTime", "DurationMinutes", "StreetMarker", "SignPlateID", "Sign", "AreaName",
            "StreetId", "StreetName", "BetweenStreet1ID", "BetweenStreet1", "BetweenStreet2ID", "BetweenStreet2", "SideOfStreet",
            "SideOfStreetCode", "SideName", "BayId", "InViolation", "VehiclePresent"
        ]
        rows = [
            ["1", "08/15/2019 10:00:00 AM", "08/15/2019 10:15:00 AM", "15", "", "", "1P", "CBD", "", "Collins Street", "", "Swanston Street", "", "Russell Street", "North", "N", "North", "101", "0", "false"],
            ["2", "08/15/2019 11:00:00 AM", "08/15/2019 11:00:00 AM", "0", "", "", "1P", "CBD", "", "Collins Street", "", "Swanston Street", "", "Russell Street", "North", "N", "North", "102", "0", "false"]
        ]
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "sample.zip"
            buffer = io.StringIO()
            writer = csv.writer(buffer)
            writer.writerow(headers)
            writer.writerows(rows)
            with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zipped:
                zipped.writestr("events.csv", buffer.getvalue())

            records, stats = aggregate_archive(archive)

        bucket = next(record for record in records if record["interval"] == 40)
        self.assertEqual(bucket["weekday"], 5)
        self.assertEqual(bucket["sampleCount"], 2)
        self.assertAlmostEqual(bucket["occupiedRatio"], 0.5)
        self.assertAlmostEqual(bucket["turnover"], 0.5)
        self.assertEqual(stats["rowsRead"], 2)


if __name__ == "__main__":
    unittest.main()
