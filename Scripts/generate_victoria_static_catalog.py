#!/usr/bin/env python3
"""Build ParkAlong's compact Victorian static parking catalog from public sources.

Only anonymous public endpoints are used. The generated artifact contains locations,
restrictions, capacities, and dated tariffs; it never contains or implies live vacancy.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


USER_AGENT = "ParkAlong-Static-Catalog/1.0 (+https://github.com/OpenRenderKit/ParkAlong)"
BALLARAT_FEES_EFFECTIVE = "2026-08-01T00:00:00+10:00"


def request_json(url: str, query: dict[str, Any] | None = None, timeout: int = 45) -> Any:
    if query:
        url = f"{url}?{urllib.parse.urlencode(query, doseq=True)}"
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def geometry_centroid(geometry: dict[str, Any] | None) -> dict[str, float] | None:
    if not geometry:
        return None
    if "x" in geometry and "y" in geometry:
        return _coordinate(geometry["y"], geometry["x"])
    points: list[tuple[float, float]] = []
    if rings := geometry.get("rings"):
        points = _flatten_points(rings)
    elif paths := geometry.get("paths"):
        points = _flatten_points(paths)
    elif coordinates := geometry.get("coordinates"):
        points = _flatten_points(coordinates)
    if not points:
        return None
    return _coordinate(
        sum(point[1] for point in points) / len(points),
        sum(point[0] for point in points) / len(points),
    )


def _flatten_points(value: Any) -> list[tuple[float, float]]:
    if isinstance(value, list) and len(value) >= 2 and all(isinstance(item, (int, float)) for item in value[:2]):
        return [(float(value[0]), float(value[1]))]
    output: list[tuple[float, float]] = []
    if isinstance(value, list):
        for item in value:
            output.extend(_flatten_points(item))
    return output


def _coordinate(latitude: Any, longitude: Any) -> dict[str, float] | None:
    try:
        lat = float(latitude)
        lon = float(longitude)
    except (TypeError, ValueError):
        return None
    if not (-39.5 <= lat <= -33.5 and 140.5 <= lon <= 150.5):
        return None
    return {"latitude": round(lat, 8), "longitude": round(lon, 8)}


def _source(
    identifier: str,
    name: str,
    url: str,
    checked_at: str,
    *,
    license_name: str = "Official council public data",
    license_url: str | None = None,
    dataset_updated_at: str | None = None,
) -> dict[str, Any]:
    return {
        "id": identifier,
        "name": name,
        "sourceURL": url,
        "licenseName": license_name,
        "licenseURL": license_url,
        "datasetUpdatedAt": dataset_updated_at,
        "checkedAt": checked_at,
    }


def _record(
    identifier: str,
    name: str,
    municipality: str,
    coordinate: dict[str, float],
    source: dict[str, Any],
    *,
    kind: str = "off_street",
    archetype: str = "general",
    capacity: int | None = None,
    accessible_spaces: int | None = None,
    schedules: list[dict[str, Any]] | None = None,
    tariffs: list[dict[str, Any]] | None = None,
    prediction_evidence: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "id": identifier,
        "name": name,
        "municipality": municipality,
        "coordinate": coordinate,
        "kind": kind,
        "archetype": archetype,
        "capacity": capacity,
        "accessibleSpaces": accessible_spaces,
        "schedules": schedules or [],
        "tariffs": tariffs or [],
        "source": source,
        "classification": "static_only",
        "predictionEvidence": prediction_evidence,
    }


def _schedule(
    days: Iterable[int],
    start: int,
    end: int,
    max_stay: int | None,
    text: str,
    *,
    public_holidays: bool = False,
    outside_unrestricted: bool = False,
) -> dict[str, Any]:
    return {
        "days": list(days),
        "startMinutes": start,
        "endMinutes": end,
        "maxStayMinutes": max_stay,
        "restrictionText": text,
        "appliesOnPublicHolidays": public_holidays,
        "outsideWindowMeansUnrestricted": outside_unrestricted,
    }


def _tariff(
    effective_from: str,
    days: Iterable[int],
    start: int,
    end: int,
    *,
    hourly_cents: int | None = None,
    free_minutes: int = 0,
    daily_cap_cents: int | None = None,
    tiers: list[tuple[int, int]] | None = None,
    effective_to: str | None = None,
) -> dict[str, Any]:
    return {
        "effectiveFrom": effective_from,
        "effectiveTo": effective_to,
        "days": list(days),
        "startMinutes": start,
        "endMinutes": end,
        "hourlyCents": hourly_cents,
        "freeMinutes": free_minutes,
        "dailyCapCents": daily_cap_cents,
        "tiers": [{"upToMinutes": minutes, "priceCents": cents} for minutes, cents in (tiers or [])],
    }


def build_maribyrnong_records(
    regular_features: list[dict[str, Any]],
    accessible_features: list[dict[str, Any]],
    *,
    checked_at: str,
) -> list[dict[str, Any]]:
    source = _source(
        "maribyrnong-parking-explorer",
        "City of Maribyrnong Parking Explorer",
        "https://maribyrnong.maps.arcgis.com/apps/instant/sidebar/index.html?appid=88ed6673549e415086b220dc6f321e3e",
        checked_at,
        license_name="City of Maribyrnong public ArcGIS service",
        dataset_updated_at="2026-05-07T02:39:43.747Z",
    )
    clusters: dict[tuple[int, int], dict[str, Any]] = {}
    for is_accessible, features in ((False, regular_features), (True, accessible_features)):
        for feature in features:
            coordinate = geometry_centroid(feature.get("geometry"))
            if not coordinate:
                continue
            key = (round(coordinate["latitude"] * 1000), round(coordinate["longitude"] * 1000))
            cluster = clusters.setdefault(key, {"lat": [], "lon": [], "capacity": 0, "accessible": 0})
            cluster["lat"].append(coordinate["latitude"])
            cluster["lon"].append(coordinate["longitude"])
            cluster["capacity"] += 1
            cluster["accessible"] += int(is_accessible)

    records: list[dict[str, Any]] = []
    for key, value in sorted(clusters.items()):
        coordinate = {
            "latitude": round(sum(value["lat"]) / len(value["lat"]), 8),
            "longitude": round(sum(value["lon"]) / len(value["lon"]), 8),
        }
        records.append(_record(
            f"maribyrnong-grid-{key[0]}-{key[1]}",
            "Public parking area",
            "Maribyrnong",
            coordinate,
            source,
            kind="on_street",
            archetype="general",
            capacity=value["capacity"],
            accessible_spaces=value["accessible"] or None,
        ))
    return records


def build_ballarat_records(rows: list[dict[str, Any]], *, checked_at: str) -> list[dict[str, Any]]:
    source = _source(
        "ballarat-parking-zones",
        "City of Ballarat",
        "https://data.ballarat.vic.gov.au/explore/dataset/realtime0/",
        checked_at,
        license_name="Creative Commons Attribution 4.0",
        license_url="https://creativecommons.org/licenses/by/4.0/",
    )
    records: list[dict[str, Any]] = []
    for row in rows:
        point = row.get("geo_point_2d") or {}
        coordinate = _coordinate(point.get("lat"), point.get("lon"))
        if not coordinate:
            coordinate = geometry_centroid((row.get("json_geometry") or {}).get("geometry"))
        if not coordinate:
            continue
        zone = str(row.get("zone") or "").strip()
        name = str(row.get("road") or f"Ballarat parking zone {zone}").strip()
        tariffs: list[dict[str, Any]] = []
        if zone == "1":
            tariffs = [_tariff(BALLARAT_FEES_EFFECTIVE, [2, 3, 4, 5, 6, 7], 9 * 60, 17 * 60 + 30,
                                hourly_cents=360, free_minutes=60)]
        records.append(_record(
            f"ballarat-zone-{row.get('id')}", name, "Ballarat", coordinate, source,
            kind="on_street", archetype="cbd_retail",
            schedules=[_schedule(range(1, 8), 0, 24 * 60, None, "No signed maximum in dataset")],
            tariffs=tariffs,
        ))
    return records


_ALLOWED_CASEY_RESTRICTIONS = {"1/4P", "1/2P", "1P", "2P", "3P", "4P", "P", "P10 Minute", "P5 Minute", "P2 Minute", "Parking"}


def build_casey_records(
    restriction_rows: list[dict[str, Any]],
    station_rows: list[dict[str, Any]],
    *,
    checked_at: str,
) -> list[dict[str, Any]]:
    restriction_source = _source(
        "casey-parking-zones", "City of Casey",
        "https://data.casey.vic.gov.au/explore/dataset/city-of-casey-parking-zones/", checked_at,
        license_name="Creative Commons Attribution 4.0", license_url="https://creativecommons.org/licenses/by/4.0/",
    )
    station_source = _source(
        "casey-station-carparks-2024", "City of Casey / PTV 2024 snapshot",
        "https://data.casey.vic.gov.au/explore/dataset/railway-station-carparks-ptv/", checked_at,
        license_name="Creative Commons Attribution 4.0", license_url="https://creativecommons.org/licenses/by/4.0/",
        dataset_updated_at="2024-09-13T00:00:00Z",
    )
    records: list[dict[str, Any]] = []
    for index, row in enumerate(restriction_rows):
        restriction = str(row.get("restrtype") or "").strip()
        if restriction not in _ALLOWED_CASEY_RESTRICTIONS:
            continue
        coordinate = _coordinate(row.get("latitude"), row.get("longitude"))
        if not coordinate:
            coordinate = geometry_centroid((row.get("geo_shape") or {}).get("geometry"))
        if not coordinate:
            continue
        schedules = _casey_schedules(row, restriction)
        street = str(row.get("street") or row.get("carpark") or "Public parking").strip()
        records.append(_record(
            f"casey-restriction-{index}-{round(coordinate['latitude'] * 100000)}-{round(coordinate['longitude'] * 100000)}",
            f"{street} · {restriction}", "Casey", coordinate, restriction_source,
            kind="on_street", archetype="general", schedules=schedules,
        ))
    for row in station_rows:
        coordinate = _coordinate(row.get("latitude"), row.get("longitude"))
        if not coordinate:
            continue
        name = str(row.get("station_name") or "Railway station").strip()
        capacity = _positive_int(row.get("carpark_capacity"))
        records.append(_record(
            f"casey-station-{row.get('gisfid')}", f"{name} Station car park", "Casey", coordinate, station_source,
            archetype="station_commuter", capacity=capacity,
        ))
    return records


def _casey_schedules(row: dict[str, Any], restriction: str) -> list[dict[str, Any]]:
    max_stay = _restriction_minutes(restriction)
    output: list[dict[str, Any]] = []
    for suffix in ("1", "2"):
        times = _parse_time_range(str(row.get(f"timesop{suffix}") or ""))
        days = _parse_days(str(row.get(f"daysop{suffix}") or ""))
        if times and days:
            output.append(_schedule(days, times[0], times[1], max_stay, restriction, outside_unrestricted=True))
    return output


def _restriction_minutes(value: str) -> int | None:
    normalized = value.upper().replace(" ", "")
    if normalized in {"P", "PARKING"}:
        return None
    special = {"1/4P": 15, "1/2P": 30, "P2MINUTE": 2, "P5MINUTE": 5, "P10MINUTE": 10}
    if normalized in special:
        return special[normalized]
    match = re.fullmatch(r"(\d+)P", normalized)
    return int(match.group(1)) * 60 if match else None


def _parse_time_range(value: str) -> tuple[int, int] | None:
    match = re.fullmatch(r"\s*(\d{1,2})(?::(\d{2}))?\s*([ap]m)\s*-\s*(\d{1,2})(?::(\d{2}))?\s*([ap]m)\s*", value.lower())
    if not match:
        return None
    values = [int(match.group(1)), int(match.group(2) or 0), match.group(3), int(match.group(4)), int(match.group(5) or 0), match.group(6)]
    def minutes(hour: int, minute: int, meridiem: str) -> int:
        hour = hour % 12 + (12 if meridiem == "pm" else 0)
        return hour * 60 + minute
    return minutes(values[0], values[1], values[2]), minutes(values[3], values[4], values[5])


def _parse_days(value: str) -> list[int] | None:
    normalized = value.strip().lower().replace(" ", "")
    names = {"sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7}
    if normalized in {"daily", "mon-sun", "monday-sunday"}:
        return list(range(1, 8))
    if normalized in {"weekdays", "mon-fri", "monday-friday"}:
        return [2, 3, 4, 5, 6]
    if normalized in {"weekends", "sat-sun", "saturday-sunday"}:
        return [1, 7]
    if "school" in normalized or not normalized:
        return None
    if "-" in normalized:
        start_raw, end_raw = normalized.split("-", 1)
        start, end = names.get(start_raw[:3]), names.get(end_raw[:3])
        if start and end:
            return list(range(start, end + 1)) if start <= end else list(range(start, 8)) + list(range(1, end + 1))
    parts = re.split(r"[,;/]", normalized)
    parsed = [names[item[:3]] for item in parts if item[:3] in names]
    return parsed or None


def build_boroondara_records(
    public_rows: list[dict[str, Any]],
    accessible_rows: list[dict[str, Any]],
    *,
    checked_at: str,
) -> list[dict[str, Any]]:
    source = _source(
        "boroondara-public-carparks", "City of Boroondara",
        "https://www.boroondara.vic.gov.au/services/streets-roads-and-parking/parking-boroondara/find-car-park",
        checked_at, license_name="Official council public JSON",
    )
    accessible: list[tuple[dict[str, float], int]] = []
    for row in accessible_rows:
        coordinate = _boro_coordinate(row.get("geo_info"))
        match = re.search(r"(\d+)\s+(?:disabled|accessible) parking", str(row.get("description") or ""), re.I)
        if coordinate and match:
            accessible.append((coordinate, int(match.group(1))))

    records: list[dict[str, Any]] = []
    for row in public_rows:
        coordinate = _boro_coordinate(row.get("geo_info"))
        if not coordinate:
            continue
        nearby_accessible = sum(count for point, count in accessible if _distance_metres(coordinate, point) <= 120)
        title = re.sub(r"^Car park\s*-\s*", "", str(row.get("title") or "Public car park"), flags=re.I).strip()
        records.append(_record(
            f"boroondara-{row.get('nid')}", title, "Boroondara", coordinate, source,
            archetype="general", accessible_spaces=nearby_accessible or None,
        ))
    return records


def build_osm_records(
    elements: list[dict[str, Any]],
    *,
    checked_at: str,
    dataset_updated_at: str | None,
) -> list[dict[str, Any]]:
    source = _source(
        "openstreetmap-victoria-parking", "OpenStreetMap contributors",
        "https://www.openstreetmap.org/copyright", checked_at,
        license_name="Open Database License 1.0",
        license_url="https://opendatacommons.org/licenses/odbl/1-0/",
        dataset_updated_at=dataset_updated_at,
    )
    records: list[dict[str, Any]] = []
    for element in elements:
        tags = element.get("tags") or {}
        restricted_access = {"private", "no", "customers", "customer", "residents", "resident", "permit", "employees", "employee", "destination"}
        if any(str(tags.get(key) or "").strip().lower() in restricted_access for key in ("access", "vehicle", "motor_vehicle")):
            continue
        center = element.get("center") or element
        coordinate = _coordinate(center.get("lat"), center.get("lon"))
        if not coordinate:
            continue
        name = str(tags.get("name") or tags.get("operator") or "Mapped parking").strip()
        capacity = _positive_int(tags.get("capacity"))
        accessible = _positive_int(tags.get("capacity:disabled"))
        fee = str(tags.get("fee") or "").strip().lower()
        tariffs = [_tariff("2000-01-01T00:00:00Z", range(1, 8), 0, 24 * 60, hourly_cents=0)] if fee in {"no", "free"} else []
        lower_name = name.lower()
        if str(tags.get("park_ride") or "").lower() in {"yes", "train"} or "station" in lower_name:
            archetype = "station_commuter"
        elif any(word in lower_name for word in ("beach", "foreshore", "pier")):
            archetype = "beach_tourism"
        elif any(word in lower_name for word in ("hospital", "university", "campus")):
            archetype = "hospital_university"
        else:
            archetype = "general"
        parking_type = str(tags.get("parking") or "").lower()
        kind = "on_street" if parking_type in {"street_side", "lane", "on_street"} else "off_street"
        records.append(_record(
            f"osm-{element.get('type')}-{element.get('id')}", name, "Victoria", coordinate, source,
            kind=kind, archetype=archetype, capacity=capacity, accessible_spaces=accessible, tariffs=tariffs,
        ))
    return records


def _boro_coordinate(value: Any) -> dict[str, float] | None:
    numbers = re.findall(r"-?\d+(?:\.\d+)?", str(value or ""))
    return _coordinate(numbers[-2], numbers[-1]) if len(numbers) >= 2 else None


def _distance_metres(lhs: dict[str, float], rhs: dict[str, float]) -> float:
    lat = math.radians((lhs["latitude"] + rhs["latitude"]) / 2)
    x = math.radians(rhs["longitude"] - lhs["longitude"]) * math.cos(lat)
    y = math.radians(rhs["latitude"] - lhs["latitude"])
    return math.sqrt(x * x + y * y) * 6_371_000


def curated_official_records(checked_at: str) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []

    stonnington = _source(
        "stonnington-carparks", "City of Stonnington",
        "https://www.stonnington.vic.gov.au/Services/Parking/Car-parks-in-Stonnington", checked_at,
        license_name="Official council parking table",
    )
    stonnington_facilities = [
        ("prahran-square", "Prahran Square", -37.84972, 144.99272, 500, 11, [(30, 420), (60, 630), (120, 1050), (180, 1500)], 2800),
        ("king-street", "8–14 King Street", -37.85137, 144.99204, 356, 4, [(60, 650), (120, 1100), (180, 1500)], 2500),
        ("elizabeth-street", "9 Elizabeth Street", -37.83882, 144.99296, 641, 12, [(30, 420), (60, 630), (120, 1050), (180, 1500)], 2800),
        ("macfarlan-street", "34–38 Macfarlan Street", -37.83820, 144.99372, 136, 2, [(60, 650), (120, 1100), (180, 1500)], 2500),
    ]
    for identifier, name, lat, lon, capacity, accessible_spaces, tiers, cap in stonnington_facilities:
        records.append(_record(
            f"stonnington-{identifier}", name, "Stonnington", _coordinate(lat, lon), stonnington,
            archetype="cbd_retail", capacity=capacity, accessible_spaces=accessible_spaces,
            schedules=[_schedule(range(1, 8), 0, 24 * 60, None, "Facility hours apply")],
            tariffs=[_tariff("2026-07-01T00:00:00+10:00", range(1, 8), 0, 24 * 60, tiers=tiers, daily_cap_cents=cap)],
        ))

    shepparton = _source(
        "shepparton-parking-costs", "Greater Shepparton City Council",
        "https://greatershepparton.com.au/bpi/parking-enforcement/types-of-parking", checked_at,
        license_name="Official council parking table",
    )
    shepparton_parks = [
        ("welsford-wyndham", "Welsford Street / Wyndham Mall", -36.38125, 145.39937, 26, 5, 120),
        ("high-rowe", "High Street / Rowe Street", -36.38305, 145.40136, 124, 5, 180),
        ("stewart", "Stewart Street", -36.37561, 145.40047, 25, 2, 180),
        ("fryers", "Fryers Street", -36.38045, 145.40052, 34, None, 120),
        ("fryers-edward", "Fryers Street / Edward Street", -36.38127, 145.40276, 39, 1, 120),
        ("maude-nixon-edward", "Maude / Nixon / Edward Streets", -36.38197, 145.40200, 68, 2, 180),
        ("90-welsford", "Opposite 90 Welsford Street", -36.37900, 145.39834, 85, 4, 120),
        ("fraser-west-walk", "Fraser Street / West Walk", -36.38138, 145.40002, 28, 2, 120),
    ]
    for identifier, name, lat, lon, capacity, accessible_spaces, limit in shepparton_parks:
        records.append(_record(
            f"shepparton-{identifier}", name, "Greater Shepparton", _coordinate(lat, lon), shepparton,
            archetype="cbd_retail", capacity=capacity, accessible_spaces=accessible_spaces,
            schedules=[_schedule(range(1, 8), 0, 24 * 60, limit, f"{limit // 60}P")],
        ))

    frankston = _source(
        "frankston-waterfront-parking", "Frankston City Council",
        "https://www.frankston.vic.gov.au/Things-To-Do/Frankston-Waterfront-Your-Ultimate-Summer-Destination",
        checked_at, license_name="Official council parking table",
    )
    frankston_parks = [
        ("moon-dog", "Moon Dog car park", -38.14572, 145.12072, 49, None, 180, 7 * 60, 19 * 60),
        ("playne-carpark", "Playne Street car park", -38.14607, 145.12118, 40, 4, 60, 9 * 60, 18 * 60),
        ("playne-street", "Playne Street", -38.14568, 145.12201, 30, 1, 60, 9 * 60, 18 * 60),
        ("davey-carpark", "Davey Street car park", -38.14800, 145.12183, 31, 3, 120, 9 * 60, 18 * 60),
        ("davey-street", "Davey Street", -38.14748, 145.12288, 18, None, 120, 9 * 60, 18 * 60),
    ]
    for identifier, name, lat, lon, capacity, accessible_spaces, limit, start, end in frankston_parks:
        records.append(_record(
            f"frankston-{identifier}", name, "Frankston", _coordinate(lat, lon), frankston,
            archetype="beach_tourism", capacity=capacity, accessible_spaces=accessible_spaces,
            schedules=[_schedule([2, 3, 4, 5, 6, 7], start, end, limit, f"{limit // 60}P", outside_unrestricted=True)],
        ))

    werribee = _source(
        "wyndham-hunter-werribee", "Wyndham City",
        "https://www.wyndham.vic.gov.au/services/roads-parking-transport/hunter-werribee-public-car-park",
        checked_at, license_name="Official council facility page",
    )
    records.append(_record(
        "wyndham-hunter-werribee", "Hunter Werribee Public Car Park", "Wyndham",
        _coordinate(-37.90176, 144.66118), werribee, archetype="cbd_retail", capacity=167, accessible_spaces=8,
        schedules=[_schedule(range(1, 8), 0, 24 * 60, None, "Open 24 hours")],
        tariffs=[_tariff("2026-01-01T00:00:00+11:00", range(1, 8), 0, 24 * 60, free_minutes=180, daily_cap_cents=500)],
    ))

    whitehorse = _source(
        "whitehorse-harrow-street", "Whitehorse City Council",
        "https://whitehorse.vic.gov.au/living-working/parking/where-you-can-park-your-vehicle-whitehorse/harrow-street-car-park",
        checked_at, license_name="Official council facility page",
    )
    records.append(_record(
        "whitehorse-harrow-street", "Harrow Street Car Park", "Whitehorse",
        _coordinate(-37.81965, 145.12275), whitehorse, archetype="station_commuter", capacity=562, accessible_spaces=9,
        schedules=[_schedule([2, 3, 4], 6 * 60, 24 * 60, None, "Open until midnight"),
                   _schedule([6, 7], 6 * 60, 24 * 60 + 60, None, "Open until 1:00 am"),
                   _schedule([1], 8 * 60, 24 * 60, None, "Open until midnight")],
    ))
    return records


def deduplicate_records(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    seen: set[str] = set()
    for record in records:
        identifier = str(record.get("id") or "")
        coordinate = record.get("coordinate") or {}
        if not identifier or identifier in seen or _coordinate(coordinate.get("latitude"), coordinate.get("longitude")) is None:
            continue
        seen.add(identifier)
        output.append(record)
    return output


def _positive_int(value: Any) -> int | None:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return None
    return parsed if parsed > 0 else None


def fetch_arcgis_features(service_url: str, timeout: int) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    offset = 0
    while True:
        payload = request_json(f"{service_url}/query", {
            "where": "1=1", "outFields": "*", "returnGeometry": "true", "outSR": "4326",
            "resultOffset": offset, "resultRecordCount": 2000, "f": "json",
        }, timeout)
        features = payload.get("features", [])
        output.extend(features)
        if len(features) < 2000:
            return output
        offset += len(features)


def fetch_opendatasoft_rows(dataset_url: str, timeout: int) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    offset = 0
    while True:
        payload = request_json(f"{dataset_url}/records", {"limit": 100, "offset": offset}, timeout)
        rows = payload.get("results", [])
        output.extend(rows)
        if len(rows) < 100:
            return output
        offset += len(rows)


def fetch_osm_parking(timeout: int) -> tuple[list[dict[str, Any]], str | None]:
    query = (
        '[out:json][timeout:180];area["boundary"="administrative"]["ISO3166-2"="AU-VIC"]->.a;'
        '(node["amenity"="parking"](area.a);way["amenity"="parking"](area.a);'
        'relation["amenity"="parking"](area.a););out center tags;'
    )
    data = urllib.parse.urlencode({"data": query}).encode("utf-8")
    request = urllib.request.Request(
        "https://overpass-api.de/api/interpreter", data=data,
        headers={"User-Agent": USER_AGENT, "Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=max(timeout, 240)) as response:
        payload = json.load(response)
    return payload.get("elements", []), (payload.get("osm3s") or {}).get("timestamp_osm_base")


def build_catalog(timeout: int = 45, *, include_osm: bool = True) -> tuple[list[dict[str, Any]], dict[str, int]]:
    checked_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    arcgis_root = "https://services2.arcgis.com/PovBcp8J7VQYyDEI/arcgis/rest/services"
    maribyrnong_regular = fetch_arcgis_features(f"{arcgis_root}/Reg_Parking_Bay_GreenZone_Ply/FeatureServer/0", timeout)
    maribyrnong_accessible = fetch_arcgis_features(f"{arcgis_root}/Reg_Parking_Bay_BlueZone_Ply/FeatureServer/0", timeout)
    ballarat = fetch_opendatasoft_rows("https://data.ballarat.vic.gov.au/api/explore/v2.1/catalog/datasets/realtime0", timeout)
    casey_restrictions = fetch_opendatasoft_rows("https://data.casey.vic.gov.au/api/explore/v2.1/catalog/datasets/city-of-casey-parking-zones", timeout)
    casey_stations = fetch_opendatasoft_rows("https://data.casey.vic.gov.au/api/explore/v2.1/catalog/datasets/railway-station-carparks-ptv", timeout)
    boroondara_public = request_json("https://www.boroondara.vic.gov.au/rest/category/locations", {"tid[]": "766"}, timeout)
    boroondara_accessible = request_json("https://www.boroondara.vic.gov.au/rest/category/locations", {"tid[]": "1396"}, timeout)

    groups = {
        "maribyrnong": build_maribyrnong_records(maribyrnong_regular, maribyrnong_accessible, checked_at=checked_at),
        "ballarat": build_ballarat_records(ballarat, checked_at=checked_at),
        "casey": build_casey_records(casey_restrictions, casey_stations, checked_at=checked_at),
        "boroondara": build_boroondara_records(boroondara_public, boroondara_accessible, checked_at=checked_at),
        "curatedOfficial": curated_official_records(checked_at),
    }
    if include_osm:
        osm_elements, osm_updated_at = fetch_osm_parking(timeout)
        groups["openStreetMap"] = build_osm_records(
            osm_elements, checked_at=checked_at, dataset_updated_at=osm_updated_at
        )
    records = deduplicate_records([record for values in groups.values() for record in values])
    return records, {name: len(values) for name, values in groups.items()}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("ParkAlong/Resources/Generated/victoria_static_parking.json"))
    parser.add_argument("--manifest", type=Path, default=Path("ParkAlong/Resources/Generated/victoria_static_manifest.json"))
    parser.add_argument("--timeout", type=int, default=45)
    parser.add_argument("--without-osm", action="store_true", help="Skip the statewide OpenStreetMap layer")
    args = parser.parse_args()

    records, counts = build_catalog(args.timeout, include_osm=not args.without_osm)
    if not records or any(counts[name] == 0 for name in ("maribyrnong", "ballarat", "casey", "boroondara")):
        raise RuntimeError(f"Required public source produced no records: {counts}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(records, separators=(",", ":")))
    manifest = {
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "recordCount": len(records),
        "sourceCounts": counts,
        "outputBytes": args.output.stat().st_size,
    }
    args.manifest.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps(manifest, sort_keys=True))


if __name__ == "__main__":
    main()
