#!/usr/bin/env python3
"""Spatially audit ParkAlong's static catalogue against every Vicmap LGA area."""

from __future__ import annotations

import argparse
import json
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable


VICMAP_LGA_QUERY_URL = (
    "https://services-ap1.arcgis.com/P744lA0wf4LlBZ84/arcgis/rest/services/"
    "Vicmap_Admin/FeatureServer/9/query"
)


def fetch_lga_geojson() -> dict[str, Any]:
    query = urllib.parse.urlencode(
        {
            "where": "1=1",
            "outFields": "lga_code,lga_name,lga_official_name",
            "returnGeometry": "true",
            "outSR": "4326",
            "f": "geojson",
        }
    )
    request = urllib.request.Request(
        f"{VICMAP_LGA_QUERY_URL}?{query}",
        headers={"User-Agent": "ParkAlong-catalog-coverage-audit/1.0"},
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        result = json.load(response)
    if len(result.get("features", [])) != 87:
        raise RuntimeError(
            f"Expected 87 Vicmap LGA/unincorporated polygons, got "
            f"{len(result.get('features', []))}"
        )
    return result


def _polygon_parts(geometry: dict[str, Any]) -> Iterable[list[list[list[float]]]]:
    if geometry["type"] == "Polygon":
        yield geometry["coordinates"]
    elif geometry["type"] == "MultiPolygon":
        yield from geometry["coordinates"]
    else:
        raise ValueError(f"Unsupported geometry type: {geometry['type']}")


def _ring_contains(point: tuple[float, float], ring: list[list[float]]) -> bool:
    x, y = point
    inside = False
    previous_x, previous_y = ring[-1][:2]
    for coordinate in ring:
        current_x, current_y = coordinate[:2]
        if (current_y > y) != (previous_y > y):
            crossing_x = (previous_x - current_x) * (y - current_y) / (
                previous_y - current_y
            ) + current_x
            if x < crossing_x:
                inside = not inside
        previous_x, previous_y = current_x, current_y
    return inside


def geometry_contains(geometry: dict[str, Any], point: tuple[float, float]) -> bool:
    for rings in _polygon_parts(geometry):
        if _ring_contains(point, rings[0]) and not any(
            _ring_contains(point, hole) for hole in rings[1:]
        ):
            return True
    return False


def _geometry_bounds(geometry: dict[str, Any]) -> tuple[float, float, float, float]:
    coordinates = [
        coordinate
        for polygon in _polygon_parts(geometry)
        for ring in polygon
        for coordinate in ring
    ]
    longitudes = [coordinate[0] for coordinate in coordinates]
    latitudes = [coordinate[1] for coordinate in coordinates]
    return min(longitudes), min(latitudes), max(longitudes), max(latitudes)


def coverage_band(row: dict[str, Any]) -> str:
    if row["recordCount"] == 0:
        return "zero"
    if row["recordCount"] < 10:
        return "extremely_thin"
    if row["authoritativeRecordCount"] == 0:
        return "discovery_only"
    if row["authoritativeRecordCount"] < 10:
        return "authority_thin"
    return "authority_backed"


def audit(records: list[dict[str, Any]], geojson: dict[str, Any]) -> dict[str, Any]:
    areas = []
    for feature in geojson["features"]:
        properties = feature["properties"]
        geometry = feature["geometry"]
        areas.append(
            {
                "code": properties["lga_code"],
                "name": properties["lga_name"],
                "officialName": properties["lga_official_name"],
                "unincorporated": "UNINC" in properties["lga_name"],
                "geometry": geometry,
                "bounds": _geometry_bounds(geometry),
            }
        )

    assigned: dict[str, list[dict[str, Any]]] = defaultdict(list)
    outside = []
    for record in records:
        coordinate = record["coordinate"]
        point = (coordinate["longitude"], coordinate["latitude"])
        match = None
        for area in areas:
            minimum_x, minimum_y, maximum_x, maximum_y = area["bounds"]
            if not (
                minimum_x <= point[0] <= maximum_x
                and minimum_y <= point[1] <= maximum_y
            ):
                continue
            if geometry_contains(area["geometry"], point):
                match = area
                break
        if match is None:
            outside.append(record["id"])
        else:
            assigned[match["code"]].append(record)

    rows = []
    for area in sorted(areas, key=lambda candidate: candidate["name"]):
        area_records = assigned[area["code"]]
        osm_records = [
            record
            for record in area_records
            if record["source"]["id"] == "openstreetmap-victoria-parking"
        ]
        authoritative_records = [
            record
            for record in area_records
            if record["source"]["id"] != "openstreetmap-victoria-parking"
        ]
        row = {
            "code": area["code"],
            "name": area["name"],
            "officialName": area["officialName"],
            "unincorporated": area["unincorporated"],
            "recordCount": len(area_records),
            "osmRecordCount": len(osm_records),
            "authoritativeRecordCount": len(authoritative_records),
            "sourceCount": len({record["source"]["id"] for record in area_records}),
            "genericMunicipalityLabelCount": sum(
                record["municipality"] == "Victoria" for record in area_records
            ),
            "scheduleRecordCount": sum(bool(record["schedules"]) for record in area_records),
            "authoritativeScheduleRecordCount": sum(
                bool(record["schedules"]) for record in authoritative_records
            ),
            "tariffRecordCount": sum(bool(record["tariffs"]) for record in area_records),
            "authoritativeTariffRecordCount": sum(
                bool(record["tariffs"]) for record in authoritative_records
            ),
            "capacityRecordCount": sum(record["capacity"] is not None for record in area_records),
            "authoritativeCapacityRecordCount": sum(
                record["capacity"] is not None for record in authoritative_records
            ),
            "accessibleRecordCount": sum(
                (record["accessibleSpaces"] or 0) > 0 for record in area_records
            ),
            "authoritativeAccessibleRecordCount": sum(
                (record["accessibleSpaces"] or 0) > 0
                for record in authoritative_records
            ),
            "liveOccupancyRecordCount": sum(
                record["classification"] == "live" for record in area_records
            ),
            "sourceIds": sorted(
                {record["source"]["id"] for record in area_records}
            ),
        }
        row["coverageBand"] = coverage_band(row)
        rows.append(row)

    return {
        "boundarySource": VICMAP_LGA_QUERY_URL,
        "areaCount": len(rows),
        "councilCount": sum(not row["unincorporated"] for row in rows),
        "unincorporatedAreaCount": sum(row["unincorporated"] for row in rows),
        "catalogRecordCount": len(records),
        "spatiallyAssignedRecordCount": sum(row["recordCount"] for row in rows),
        "outsideAreaRecordCount": len(outside),
        "outsideAreaRecordIds": outside,
        "genericMunicipalityLabelRecordCount": sum(
            record["municipality"] == "Victoria" for record in records
        ),
        "coverageBands": {
            band: sum(row["coverageBand"] == band for row in rows)
            for band in (
                "zero",
                "extremely_thin",
                "discovery_only",
                "authority_thin",
                "authority_backed",
            )
        },
        "areas": rows,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--catalog",
        type=Path,
        default=Path("ParkAlong/Resources/Generated/victoria_static_parking.json"),
    )
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    with args.catalog.open() as input_file:
        records = json.load(input_file)
    result = audit(records, fetch_lga_geojson())
    rendered = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(rendered)
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
