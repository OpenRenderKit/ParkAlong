#!/usr/bin/env python3
"""Audit parking coverage per authoritative Vicmap suburb/locality.

Compares a before and after static catalogue using the same official
Vicmap Admin Locality Boundaries polygons (layer 11, CC BY 4.0
International, item 51eed453d31243a795850b765a400769). Records are
assigned by polygon containment only, never from a record name and never
via reverse-geocoding, so before/after numbers are directly comparable.

Target list below is exactly the user-requested set, spelled in natural
title case to match authoritative normalization. No invented
neighbourhoods have been added.
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from typing import Any

try:
    from analyze_victoria_catalog_coverage import (
        VICMAP_LOCALITY_QUERY_URL,
        build_locality_index,
        fetch_locality_geojson,
        locality_areas_from_geojson,
        matching_locality,
    )
except ImportError:  # pragma: no cover - unittest discovery from repo root
    from Scripts.analyze_victoria_catalog_coverage import (
        VICMAP_LOCALITY_QUERY_URL,
        build_locality_index,
        fetch_locality_geojson,
        locality_areas_from_geojson,
        matching_locality,
    )


MELBOURNE_TARGET_LOCALITIES = [
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

OSM_SOURCE_ID = "openstreetmap-victoria-parking"


def _record_point(record: dict[str, Any]) -> tuple[float, float] | None:
    coordinate = record.get("coordinate") or {}
    try:
        return (float(coordinate["longitude"]), float(coordinate["latitude"]))
    except (KeyError, TypeError, ValueError):
        return None


def _row_for(name: str, area_records: list[dict[str, Any]], *, polygon_present: bool) -> dict[str, Any]:
    authoritative = [
        record
        for record in area_records
        if (record.get("source") or {}).get("id") != OSM_SOURCE_ID
    ]
    return {
        "name": name,
        "polygonPresent": polygon_present,
        "recordCount": len(area_records),
        "authoritativeRecordCount": len(authoritative),
        "accessibleRecordCount": sum(
            (record.get("accessibleSpaces") or 0) > 0 for record in area_records
        ),
        "capacityRecordCount": sum(
            record.get("capacity") is not None for record in area_records
        ),
        "scheduleRecordCount": sum(bool(record.get("schedules")) for record in area_records),
        "tariffRecordCount": sum(bool(record.get("tariffs")) for record in area_records),
        "authoritativeAccessibleRecordCount": sum(
            (record.get("accessibleSpaces") or 0) > 0 for record in authoritative
        ),
        "authoritativeCapacityRecordCount": sum(
            record.get("capacity") is not None for record in authoritative
        ),
        "authoritativeScheduleRecordCount": sum(
            bool(record.get("schedules")) for record in authoritative
        ),
        "authoritativeTariffRecordCount": sum(
            bool(record.get("tariffs")) for record in authoritative
        ),
        "sourceIds": sorted(
            {(record.get("source") or {}).get("id") for record in area_records if (record.get("source") or {}).get("id")}
        ),
    }


def audit_locality_coverage(
    records: list[dict[str, Any]],
    geojson: dict[str, Any],
    targets: list[str] | None = None,
) -> dict[str, Any]:
    """Assign records to authoritative localities and report target metrics."""
    wanted = list(targets) if targets is not None else list(MELBOURNE_TARGET_LOCALITIES)
    areas = locality_areas_from_geojson(geojson)
    index = build_locality_index(areas)
    by_name: dict[str, list[dict[str, Any]]] = defaultdict(list)
    outside: list[str] = []
    for record in records:
        point = _record_point(record)
        match = matching_locality(index, point) if point is not None else None
        if match is None:
            outside.append(str(record.get("id")))
        else:
            by_name[match["name"]].append(record)
    present = {area["name"] for area in areas}
    rows = [
        _row_for(name, by_name.get(name, []), polygon_present=(name in present))
        for name in wanted
    ]
    return {
        "boundarySource": VICMAP_LOCALITY_QUERY_URL,
        "localityPolygonCount": len(areas),
        "targetCount": len(wanted),
        "catalogRecordCount": len(records),
        "spatiallyAssignedRecordCount": sum(len(values) for values in by_name.values()),
        "outsidePolygonRecordCount": len(outside),
        "outsidePolygonRecordIds": outside,
        "localityFieldLabeledCount": sum(1 for record in records if record.get("locality")),
        "localityFieldUnmatchedCount": sum(1 for record in records if not record.get("locality")),
        "targets": rows,
    }


def compare_locality_coverage(
    before_records: list[dict[str, Any]],
    after_records: list[dict[str, Any]],
    geojson: dict[str, Any],
    targets: list[str] | None = None,
) -> dict[str, Any]:
    """Compare before/after catalogues with the same polygons."""
    wanted = list(targets) if targets is not None else list(MELBOURNE_TARGET_LOCALITIES)
    before = audit_locality_coverage(before_records, geojson, wanted)
    after = audit_locality_coverage(after_records, geojson, wanted)
    before_by_name = {row["name"]: row for row in before["targets"]}
    after_by_name = {row["name"]: row for row in after["targets"]}
    changes: list[dict[str, Any]] = []
    for name in wanted:
        lhs = before_by_name[name]
        rhs = after_by_name[name]
        changes.append(
            {
                "name": name,
                "polygonPresent": rhs["polygonPresent"],
                "beforeRecordCount": lhs["recordCount"],
                "afterRecordCount": rhs["recordCount"],
                "deltaRecordCount": rhs["recordCount"] - lhs["recordCount"],
                "beforeAuthoritativeRecordCount": lhs["authoritativeRecordCount"],
                "afterAuthoritativeRecordCount": rhs["authoritativeRecordCount"],
                "deltaAuthoritativeRecordCount": rhs["authoritativeRecordCount"]
                - lhs["authoritativeRecordCount"],
                "beforeSourceIds": lhs["sourceIds"],
                "afterSourceIds": rhs["sourceIds"],
            }
        )
    return {
        "boundarySource": VICMAP_LOCALITY_QUERY_URL,
        "localityPolygonCount": before["localityPolygonCount"],
        "targetCount": len(wanted),
        "beforeCatalogRecordCount": before["catalogRecordCount"],
        "afterCatalogRecordCount": after["catalogRecordCount"],
        "beforeAssignedRecordCount": before["spatiallyAssignedRecordCount"],
        "afterAssignedRecordCount": after["spatiallyAssignedRecordCount"],
        "beforeOutsideRecordCount": before["outsidePolygonRecordCount"],
        "afterOutsideRecordCount": after["outsidePolygonRecordCount"],
        "beforeFieldLabeledCount": before["localityFieldLabeledCount"],
        "afterFieldLabeledCount": after["localityFieldLabeledCount"],
        "before": before,
        "after": after,
        "changes": changes,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, help="Before catalogue JSON (list of records)")
    parser.add_argument("--after", type=Path, help="After catalogue JSON (list of records)")
    parser.add_argument("--catalog", type=Path, help="Single catalogue JSON for a one-sided audit")
    parser.add_argument("--localities", type=Path, help="Offline locality GeoJSON; otherwise fetch live")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    if args.localities:
        with args.localities.open() as input_file:
            geojson = json.load(input_file)
    else:
        geojson = fetch_locality_geojson()

    if args.before and args.after:
        with args.before.open() as input_file:
            before_records = json.load(input_file)
        with args.after.open() as input_file:
            after_records = json.load(input_file)
        result = compare_locality_coverage(before_records, after_records, geojson)
    elif args.catalog:
        with args.catalog.open() as input_file:
            records = json.load(input_file)
        result = audit_locality_coverage(records, geojson)
    else:
        raise SystemExit("Provide --before and --after, or --catalog")
    rendered = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(rendered)
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
