#!/usr/bin/env python3
"""Independent network smoke check for the City parking-sensor contract."""

from __future__ import annotations

import json
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone


URL = "https://data.melbourne.vic.gov.au/api/explore/v2.1/catalog/datasets/on-street-parking-bay-sensors/records"


def request(query: dict[str, str | int]) -> dict:
    url = f"{URL}?{urllib.parse.urlencode(query)}"
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "ParkAlong-Smoke/1.0"}), timeout=15) as response:
        return json.load(response)


def main() -> None:
    started = time.monotonic()
    point = "within_distance(location, geom'POINT(144.9631 -37.8136)', 700m)"
    all_rows = request({"select": "count(*) as count", "where": point, "limit": 1})["results"][0]["count"]
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=24)).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    trusted_where = f"{point} AND status_timestamp >= date'{cutoff}' AND zone_number is not null"
    status = request({
        "select": "status_description,count(*) as count,max(status_timestamp) as newest",
        "where": trusted_where,
        "group_by": "status_description",
        "limit": 20,
    })["results"]
    zones = request({
        "select": "zone_number,status_description,count(*) as bay_count,max(status_timestamp) as newest_timestamp",
        "where": trusted_where,
        "group_by": "zone_number,status_description",
        "limit": 100,
    })["results"]
    by_status = {row["status_description"]: row["count"] for row in status}
    output = {
        "allSpatialRows": all_rows,
        "trustedRows": sum(by_status.values()),
        "present": by_status.get("Present", 0),
        "unoccupied": by_status.get("Unoccupied", 0),
        "zoneGroupsFirstPage": len(zones),
        "newest": max((row["newest"] for row in status), default=None),
        "elapsedSeconds": round(time.monotonic() - started, 3),
    }
    print(json.dumps(output, sort_keys=True))


if __name__ == "__main__":
    main()
