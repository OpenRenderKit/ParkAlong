#!/usr/bin/env python3
"""Download stable City zone metadata and active sign records for bundling."""

from __future__ import annotations

import argparse
import json
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path

if __package__:
    from .generate_prediction import normalize_segment
else:
    from generate_prediction import normalize_segment


API_ROOT = "https://data.melbourne.vic.gov.au/api/explore/v2.1/catalog/datasets"
SENSORS = "on-street-parking-bay-sensors"
SIGNS = "sign-plates-located-in-each-parking-zone"
STREETS = "parking-zones-linked-to-street-segments"


def fetch_all(dataset: str, select: str | None = None) -> list[dict]:
    output: list[dict] = []
    offset = 0
    page_size = 100
    while True:
        query = {"limit": page_size, "offset": offset}
        if select:
            query["select"] = select
        url = f"{API_ROOT}/{dataset}/records?{urllib.parse.urlencode(query)}"
        request = urllib.request.Request(url, headers={"User-Agent": "ParkAlong-Metadata/1.0"})
        with urllib.request.urlopen(request, timeout=30) as response:
            rows = json.load(response)["results"]
        output.extend(rows)
        if len(rows) < page_size:
            return output
        offset += page_size


def build_metadata(sensors: list[dict], streets: list[dict]) -> list[dict]:
    coordinates: dict[int, list[tuple[float, float]]] = defaultdict(list)
    sensor_ids: dict[int, set[int]] = defaultdict(set)
    for sensor in sensors:
        zone = sensor.get("zone_number")
        location = sensor.get("location") or {}
        sensor_id = sensor.get("kerbsideid")
        if zone is None or location.get("lat") is None or location.get("lon") is None or sensor_id is None:
            continue
        zone = int(zone)
        coordinates[zone].append((float(location["lat"]), float(location["lon"])))
        sensor_ids[zone].add(int(sensor_id))

    street_by_zone = {int(row["parkingzone"]): row for row in streets if row.get("parkingzone") is not None and row.get("onstreet")}
    records: list[dict] = []
    for zone in sorted(coordinates):
        street = street_by_zone.get(zone)
        if not street:
            continue
        points = coordinates[zone]
        street_name = street["onstreet"]
        from_street = street.get("streetfrom")
        to_street = street.get("streetto")
        records.append({
            "zoneNumber": zone,
            "streetName": street_name,
            "fromStreet": from_street,
            "toStreet": to_street,
            "coordinate": {
                "latitude": sum(point[0] for point in points) / len(points),
                "longitude": sum(point[1] for point in points) / len(points),
            },
            "sensorCount": len(sensor_ids[zone]),
            "sensorIDs": sorted(sensor_ids[zone]),
            "segmentKey": normalize_segment(street_name, from_street or "", to_street or ""),
        })
    return records


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-directory", type=Path, default=Path("ParkAlong/Resources/Generated"))
    args = parser.parse_args()

    sensors = fetch_all(SENSORS, "zone_number,kerbsideid,location")
    streets = fetch_all(STREETS, "parkingzone,onstreet,streetfrom,streetto,segment_id")
    restrictions = fetch_all(SIGNS, "parkingzone,restriction_days,time_restrictions_start,time_restrictions_finish,restriction_display")
    metadata = build_metadata(sensors, streets)

    args.output_directory.mkdir(parents=True, exist_ok=True)
    metadata_path = args.output_directory / "zone_metadata.json"
    restrictions_path = args.output_directory / "restrictions.json"
    metadata_path.write_text(json.dumps(metadata, separators=(",", ":")))
    restrictions_path.write_text(json.dumps(restrictions, separators=(",", ":")))
    print(json.dumps({
        "zones": len(metadata),
        "restrictions": len(restrictions),
        "metadataBytes": metadata_path.stat().st_size,
        "restrictionBytes": restrictions_path.stat().st_size,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
