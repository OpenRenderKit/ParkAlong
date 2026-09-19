#!/usr/bin/env python3
"""Spatially audit ParkAlong's static catalogue against every Vicmap LGA area."""

from __future__ import annotations

import argparse
import json
import re
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable


VICMAP_LGA_QUERY_URL = (
    "https://services-ap1.arcgis.com/P744lA0wf4LlBZ84/arcgis/rest/services/"
    "Vicmap_Admin/FeatureServer/9/query"
)

# Authoritative suburb/locality boundaries (Vicmap Admin, layer 11).
# ArcGIS item 51eed453d31243a795850b765a400769 explicitly describes
# locality/suburb boundaries, CC BY 4.0 International. Item resource
# modified time independently observed as 2026-09-12T17:03:47Z.
VICMAP_LOCALITY_SERVICE_URL = (
    "https://services-ap1.arcgis.com/P744lA0wf4LlBZ84/arcgis/rest/services/"
    "Vicmap_Admin/FeatureServer/11"
)
VICMAP_LOCALITY_QUERY_URL = VICMAP_LOCALITY_SERVICE_URL + "/query"
VICMAP_LOCALITY_ITEM_ID = "51eed453d31243a795850b765a400769"
VICMAP_LOCALITY_LICENSE_NAME = "Creative Commons Attribution 4.0 International"
VICMAP_LOCALITY_LICENSE_URL = "https://creativecommons.org/licenses/by/4.0/"
VICMAP_LOCALITY_DATASET_UPDATED_AT = "2026-09-12T17:03:47Z"
VICMAP_LOCALITY_EXPECTED_COUNT = 2973
VICMAP_LOCALITY_MIN_SANE_COUNT = 2900
VICMAP_LOCALITY_PAGE_SIZE = 2000
VICMAP_LOCALITY_OUT_FIELDS = "ufi,locality_name,gazetted_locality_name"
# outSR 4326 degrees: 0.00001 deg is ~1.1 m, a safe small simplification
# that keeps suburb assignment stable while keeping payloads compact.
# geometryPrecision 5 matches (~1.1 m) for the same reason.
VICMAP_LOCALITY_MAX_ALLOWABLE_OFFSET = 0.00001
VICMAP_LOCALITY_GEOMETRY_PRECISION = 5


def fetch_lga_geojson(
    timeout: int = 90,
    *,
    user_agent: str = "ParkAlong-catalog-coverage-audit/1.0",
) -> dict[str, Any]:
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
        headers={"User-Agent": user_agent},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
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


def lga_areas_from_geojson(geojson: dict[str, Any]) -> list[dict[str, Any]]:
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
    return areas


def matching_lga(
    areas: list[dict[str, Any]], point: tuple[float, float]
) -> dict[str, Any] | None:
    for area in areas:
        minimum_x, minimum_y, maximum_x, maximum_y = area["bounds"]
        if not (
            minimum_x <= point[0] <= maximum_x
            and minimum_y <= point[1] <= maximum_y
        ):
            continue
        if geometry_contains(area["geometry"], point):
            return area
    return None


def locality_query_params(result_offset: int, page_size: int) -> dict[str, Any]:
    """Exact ArcGIS query params for one locality page (GeoJSON, 4326)."""
    return {
        "where": "1=1",
        "outFields": VICMAP_LOCALITY_OUT_FIELDS,
        "returnGeometry": "true",
        "outSR": "4326",
        "geometryPrecision": str(VICMAP_LOCALITY_GEOMETRY_PRECISION),
        "maxAllowableOffset": str(VICMAP_LOCALITY_MAX_ALLOWABLE_OFFSET),
        "orderByFields": "ufi ASC",
        "resultOffset": str(result_offset),
        "resultRecordCount": str(page_size),
        "f": "geojson",
    }


def merge_locality_pages(pages: list[dict[str, Any]]) -> dict[str, Any]:
    """Merge paginated GeoJSON pages into a single FeatureCollection."""
    merged: list[dict[str, Any]] = []
    for page in pages:
        merged.extend(page.get("features", []))
    return {"type": "FeatureCollection", "features": merged}


def validate_locality_geojson(
    geojson: dict[str, Any],
    *,
    min_count: int = VICMAP_LOCALITY_MIN_SANE_COUNT,
    expected_count: int = VICMAP_LOCALITY_EXPECTED_COUNT,
) -> None:
    """Fail closed unless the locality result looks like a full fetch.

    A single truncated page (<=2000 features) must never be silently used
    for suburb labeling; callers should treat RuntimeError as fatal.
    """
    features = (geojson or {}).get("features")
    if not isinstance(features, list):
        raise RuntimeError("Locality GeoJSON has no features list")
    if len(features) < min_count:
        raise RuntimeError(
            f"Locality result looks partial: got {len(features)} polygons, "
            f"expected around {expected_count} (minimum sane {min_count}). "
            "Refusing to label suburbs from a partial page."
        )
    for index, feature in enumerate(features):
        properties = (feature or {}).get("properties") or {}
        geometry = (feature or {}).get("geometry") or {}
        if geometry.get("type") not in ("Polygon", "MultiPolygon"):
            raise RuntimeError(
                f"Locality feature {index} has unsupported geometry "
                f"{geometry.get('type')!r}"
            )
        raw_name = (
            properties.get("gazetted_locality_name")
            or properties.get("locality_name")
            or ""
        )
        if not str(raw_name).strip():
            raise RuntimeError(
                f"Locality feature {index} is missing locality_name/"
                "gazetted_locality_name"
            )
        if properties.get("ufi") in (None, ""):
            raise RuntimeError(f"Locality feature {index} is missing ufi")


def fetch_locality_geojson(
    timeout: int = 90,
    *,
    user_agent: str = "ParkAlong-locality-coverage-audit/1.0",
    page_size: int = VICMAP_LOCALITY_PAGE_SIZE,
) -> dict[str, Any]:
    """Fetch all current Vicmap localities as GeoJSON with pagination.

    The layer holds 2973 features and the service caps pages at 2000, so at
    least two requests are required. Only ufi/locality_name/
    gazetted_locality_name are requested, in 4326 with compact precision.
    """
    if page_size <= 0 or page_size > 2000:
        raise ValueError("page_size must be within 1..2000")
    pages: list[dict[str, Any]] = []
    offset = 0
    while True:
        query = urllib.parse.urlencode(locality_query_params(offset, page_size))
        request = urllib.request.Request(
            f"{VICMAP_LOCALITY_QUERY_URL}?{query}",
            headers={"User-Agent": user_agent, "Accept": "application/json"},
        )
        with urllib.request.urlopen(request, timeout=timeout) as response:
            page = json.load(response)
        page_features = page.get("features", [])
        pages.append(page)
        if len(page_features) < page_size:
            break
        offset += len(page_features)
        if offset > 10000:
            raise RuntimeError("Locality pagination did not terminate")
    merged = merge_locality_pages(pages)
    validate_locality_geojson(merged)
    return merged


def _title_token(token: str) -> str:
    if not token:
        return token
    lowered = token.lower()
    # Preserve McXxx as McXxx instead of Mckinnon-style Mckinnon.
    if lowered.startswith("mc") and len(token) > 2 and token[2].isalpha():
        return "Mc" + token[2].upper() + token[3:].lower()
    if len(token) <= 1:
        return token.upper()
    return token[0].upper() + token[1:].lower()


def natural_locality_name(raw: str | None) -> str:
    """Normalize Vicmap UPPER-CASE locality names to natural title case.

    Spaces separate words; hyphens and apostrophes start a new capitalized
    part (Glen Waverley, Mount Waverley, St Kilda, McCrae, O'Brien-style).
    Already-natural names pass through unchanged.
    """
    text = " ".join(str(raw or "").split())
    if not text:
        return ""
    words: list[str] = []
    for word in text.split(" "):
        hyphen_parts: list[str] = []
        for hyphen_part in word.split("-"):
            apost_parts = re.split(r"(['\u2019])", hyphen_part)
            rebuilt = "".join(
                part
                if part in ("'", "\u2019") or part == ""
                else _title_token(part)
                for part in apost_parts
            )
            hyphen_parts.append(rebuilt)
        words.append("-".join(hyphen_parts))
    return " ".join(words)


def locality_areas_from_geojson(geojson: dict[str, Any]) -> list[dict[str, Any]]:
    """Convert locality GeoJSON to areas with normalized display names.

    Prefers gazetted_locality_name when present, falling back to
    locality_name. Reuses the shared hole-aware geometry helpers.
    """
    areas: list[dict[str, Any]] = []
    for feature in geojson.get("features", []):
        properties = feature.get("properties") or {}
        geometry = feature.get("geometry")
        if geometry is None:
            continue
        raw_name = str(
            properties.get("gazetted_locality_name")
            or properties.get("locality_name")
            or ""
        ).strip()
        if not raw_name:
            continue
        areas.append(
            {
                "ufi": properties.get("ufi"),
                "rawName": raw_name,
                "name": natural_locality_name(raw_name),
                "geometry": geometry,
                "bounds": _geometry_bounds(geometry),
            }
        )
    return areas


def build_locality_index(
    areas: list[dict[str, Any]], *, cell_size_deg: float = 0.2
) -> dict[str, Any]:
    """Build a uniform grid/bounds candidate index over locality polygons.

    Without an index, assigning ~35,500 points across ~2,973 polygons is an
    O(records x polygons) brute-force pass. The grid narrows each point to
    the handful of polygons whose bounds overlap its cell, before the exact
    hole-aware geometry_contains check runs.
    """
    if cell_size_deg <= 0:
        raise ValueError("cell_size_deg must be positive")
    if not areas:
        return {
            "areas": [],
            "bounds": None,
            "cellSize": cell_size_deg,
            "lonCells": 0,
            "latCells": 0,
            "grid": {},
        }
    min_x = min(area["bounds"][0] for area in areas)
    min_y = min(area["bounds"][1] for area in areas)
    max_x = max(area["bounds"][2] for area in areas)
    max_y = max(area["bounds"][3] for area in areas)
    lon_cells = max(1, int((max_x - min_x) / cell_size_deg) + 1)
    lat_cells = max(1, int((max_y - min_y) / cell_size_deg) + 1)
    # Clamp absurd grids from degenerate bounds.
    lon_cells = min(lon_cells, 512)
    lat_cells = min(lat_cells, 512)
    grid: dict[tuple[int, int], list[dict[str, Any]]] = defaultdict(list)
    for area in areas:
        x0, y0, x1, y1 = area["bounds"]
        ix0 = max(0, min(lon_cells - 1, int((x0 - min_x) / cell_size_deg)))
        ix1 = max(0, min(lon_cells - 1, int((x1 - min_x) / cell_size_deg)))
        iy0 = max(0, min(lat_cells - 1, int((y0 - min_y) / cell_size_deg)))
        iy1 = max(0, min(lat_cells - 1, int((y1 - min_y) / cell_size_deg)))
        for ix in range(ix0, ix1 + 1):
            for iy in range(iy0, iy1 + 1):
                grid[(ix, iy)].append(area)
    return {
        "areas": areas,
        "bounds": (min_x, min_y, max_x, max_y),
        "cellSize": cell_size_deg,
        "lonCells": lon_cells,
        "latCells": lat_cells,
        "grid": dict(grid),
    }


def locality_candidates(
    index: dict[str, Any], point: tuple[float, float]
) -> list[dict[str, Any]]:
    """Return the small candidate set for a point via its grid cell."""
    bounds = index.get("bounds")
    if not bounds:
        return []
    min_x, min_y, max_x, max_y = bounds
    lon, lat = point
    if not (min_x <= lon <= max_x and min_y <= lat <= max_y):
        return []
    cell_size = index["cellSize"]
    ix = max(0, min(index["lonCells"] - 1, int((lon - min_x) / cell_size)))
    iy = max(0, min(index["latCells"] - 1, int((lat - min_y) / cell_size)))
    return index["grid"].get((ix, iy), [])


def matching_locality_bruteforce(
    areas: list[dict[str, Any]], point: tuple[float, float]
) -> dict[str, Any] | None:
    """Exact brute-force locality match (used to verify the grid index)."""
    for area in areas:
        minimum_x, minimum_y, maximum_x, maximum_y = area["bounds"]
        if not (
            minimum_x <= point[0] <= maximum_x
            and minimum_y <= point[1] <= maximum_y
        ):
            continue
        if geometry_contains(area["geometry"], point):
            return area
    return None


def matching_locality(
    index: dict[str, Any], point: tuple[float, float]
) -> dict[str, Any] | None:
    """Exact locality match using the grid/bounds candidate index."""
    for area in locality_candidates(index, point):
        minimum_x, minimum_y, maximum_x, maximum_y = area["bounds"]
        if not (
            minimum_x <= point[0] <= maximum_x
            and minimum_y <= point[1] <= maximum_y
        ):
            continue
        if geometry_contains(area["geometry"], point):
            return area
    return None


def audit(records: list[dict[str, Any]], geojson: dict[str, Any]) -> dict[str, Any]:
    areas = lga_areas_from_geojson(geojson)
    assigned: dict[str, list[dict[str, Any]]] = defaultdict(list)
    outside = []
    for record in records:
        coordinate = record["coordinate"]
        point = (coordinate["longitude"], coordinate["latitude"])
        match = matching_lga(areas, point)
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
