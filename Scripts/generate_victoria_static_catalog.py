#!/usr/bin/env python3
"""Build ParkAlong's compact Victorian static parking catalog from public sources.

Only anonymous public endpoints are used. The generated artifact contains locations,
restrictions, capacities, and dated tariffs; it never contains or implies live vacancy.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
import re
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

try:
    from analyze_victoria_catalog_coverage import (
        VICMAP_LOCALITY_DATASET_UPDATED_AT,
        VICMAP_LOCALITY_ITEM_ID,
        VICMAP_LOCALITY_LICENSE_NAME,
        VICMAP_LOCALITY_LICENSE_URL,
        VICMAP_LOCALITY_MIN_SANE_COUNT,
        VICMAP_LOCALITY_QUERY_URL,
        VICMAP_LOCALITY_SERVICE_URL,
        build_locality_index,
        fetch_lga_geojson,
        fetch_locality_geojson,
        lga_areas_from_geojson,
        locality_areas_from_geojson,
        matching_lga,
        matching_locality,
        natural_locality_name,
        validate_locality_geojson,
    )
except ImportError:  # pragma: no cover - unittest discovery from the repository root
    from Scripts.analyze_victoria_catalog_coverage import (
        VICMAP_LOCALITY_DATASET_UPDATED_AT,
        VICMAP_LOCALITY_ITEM_ID,
        VICMAP_LOCALITY_LICENSE_NAME,
        VICMAP_LOCALITY_LICENSE_URL,
        VICMAP_LOCALITY_MIN_SANE_COUNT,
        VICMAP_LOCALITY_QUERY_URL,
        VICMAP_LOCALITY_SERVICE_URL,
        build_locality_index,
        fetch_lga_geojson,
        fetch_locality_geojson,
        lga_areas_from_geojson,
        locality_areas_from_geojson,
        matching_lga,
        matching_locality,
        natural_locality_name,
        validate_locality_geojson,
    )


USER_AGENT = "ParkAlong-Static-Catalog/1.0 (+https://github.com/OpenRenderKit/ParkAlong)"
BALLARAT_FEES_EFFECTIVE = "2026-08-01T00:00:00+10:00"
MILDURA_ACCESSIBLE_URL = (
    "https://data.gov.au/data/dataset/6951b015-3f53-4e23-9e11-e863861c9a53/"
    "resource/f736ca9b-e82e-45df-97f6-ea1cbfddf139/download/disabled-parking-points.json"
)
SWAN_HILL_ACCESSIBLE_URL = (
    "https://data.gov.au/data/dataset/52c7294f-dfdc-410e-ba83-539b0bf83931/"
    "resource/1e8b32d0-7038-44b8-8f1c-a70504eda408/download/shrccdisabledparking.csv"
)
PORT_PHILLIP_ACCESSIBLE_URL = (
    "https://data.gov.au/data/dataset/874498ce-a720-43c3-b7d5-0a750653ffa2/"
    "resource/2ae71d07-8def-469d-976c-24193b968288/download/city-of-port-phillip-accessible-parking.geojson"
)
GLEN_EIRA_ACCESSIBLE_URL = (
    "https://data.gov.au/data/dataset/66f2f149-f822-4077-b8a9-15fa0990bf58/"
    "resource/81fbc12d-2d0d-41b4-af04-e62fd1b5a482/download/accessibleparking.json"
)
BRIMBANK_CARPARK_WFS_URL = (
    "https://data.gov.au/geoserver/brimbank-carparks/wfs?request=GetFeature"
    "&typeName=ckan_43c21764_3114_4e2b_8718_a2ded31e14d2&outputFormat=json"
)
BRIMBANK_DISABLED_WFS_URL = (
    "https://data.gov.au/geoserver/brimbank-disabled-car-parks/wfs?request=GetFeature"
    "&typeName=ckan_3ecdd93d_0d55_49a3_a11a_294e4640f9e1&outputFormat=json"
)
VICMAP_FOI_URL = (
    "https://services-ap1.arcgis.com/P744lA0wf4LlBZ84/arcgis/rest/services/"
    "Vicmap_Features_of_Interest/FeatureServer/4"
)
OVERPASS_ENDPOINTS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
)


def request_json(url: str, query: dict[str, Any] | None = None, timeout: int = 45) -> Any:
    if query:
        url = f"{url}?{urllib.parse.urlencode(query, doseq=True)}"
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def request_text(url: str, timeout: int = 45) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "text/csv,text/plain,*/*"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8-sig")


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
    unparsed_condition: str | None = None,
) -> dict[str, Any]:
    return {
        "days": list(days),
        "startMinutes": start,
        "endMinutes": end,
        "maxStayMinutes": max_stay,
        "restrictionText": text,
        "appliesOnPublicHolidays": public_holidays,
        "outsideWindowMeansUnrestricted": outside_unrestricted,
        "unparsedCondition": unparsed_condition,
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
    unparsed_condition: str | None = None,
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
        "unparsedCondition": unparsed_condition,
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


def _parse_24_hour_range(value: str) -> tuple[int, int] | None:
    match = re.fullmatch(r"\s*(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})\s*", value)
    if not match:
        return None
    start = int(match.group(1)) * 60 + int(match.group(2))
    end = int(match.group(3)) * 60 + int(match.group(4))
    if start > 24 * 60 or end > 24 * 60 or int(match.group(2)) > 59 or int(match.group(4)) > 59:
        return None
    return start, end


def _parse_duration_minutes(value: Any) -> int | None:
    if isinstance(value, (int, float)) and value > 0:
        return round(float(value) * 60)
    normalized = str(value or "").strip().lower()
    if not normalized:
        return None
    if match := re.fullmatch(r"(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours)", normalized):
        return round(float(match.group(1)) * 60)
    if match := re.fullmatch(r"(\d+)\s*(?:m|min|mins|minute|minutes)", normalized):
        return int(match.group(1))
    if match := re.fullmatch(r"(\d{1,2}):(\d{2})", normalized):
        return int(match.group(1)) * 60 + int(match.group(2))
    return _restriction_minutes(normalized)


def _safe_component(value: Any, fallback: Any) -> str:
    component = re.sub(r"[^A-Za-z0-9._-]+", "-", str(value or fallback).strip()).strip("-")
    return component or str(fallback)


def _feature_coordinate(feature: dict[str, Any]) -> dict[str, float] | None:
    attributes = feature.get("attributes") or {}
    return geometry_centroid(feature.get("geometry")) or _coordinate(attributes.get("latitude"), attributes.get("longitude"))


def _wodonga_schedules(attributes: dict[str, Any]) -> list[dict[str, Any]]:
    schedules: list[dict[str, Any]] = []
    for index in range(1, 4):
        suffixes = [""] if index == 1 else [str(index), f"_{index}"]
        def value(prefix: str) -> Any:
            return next((attributes.get(f"{prefix}{suffix}") for suffix in suffixes if attributes.get(f"{prefix}{suffix}") not in (None, "")), None)
        max_stay = _parse_duration_minutes(value("time_h"))
        days = _parse_days(str(value("days") or ""))
        window = _parse_24_hour_range(str(value("start_time") or "") + "-" + str(value("end_time") or ""))
        if not (max_stay and days and window):
            continue
        vehicle = str(value("veh_type") or "general vehicles").strip()
        permit = str(value("permit") or "").strip()
        text = f"Up to {max_stay // 60}h" if max_stay % 60 == 0 else f"Up to {max_stay} min"
        if vehicle and vehicle.lower() not in {"general", "general vehicles", "all", "any"}:
            text += f" · {vehicle}"
        if permit and permit.lower() not in {"n", "no", "none"}:
            text += " · permit condition"
        schedules.append(_schedule(days, window[0], window[1], max_stay, text, outside_unrestricted=True))
    return schedules


def build_wodonga_records(features: list[dict[str, Any]], *, checked_at: str) -> list[dict[str, Any]]:
    source = _source(
        "wodonga-parking-lot", "Wodonga Council parking lot",
        "https://services-ap1.arcgis.com/w6r4LlwgJu8O0neQ/arcgis/rest/services/parking_lot_edit_view/FeatureServer/0",
        checked_at, license_name="Wodonga Council public ArcGIS service",
    )
    records: list[dict[str, Any]] = []
    for feature in features:
        attributes = feature.get("attributes") or {}
        if attributes.get("public_view") in {0, False, "0", "N", "No", "no"}:
            continue
        coordinate = _feature_coordinate(feature)
        if not coordinate:
            continue
        identifier = _safe_component(attributes.get("OBJECTID"), len(records))
        name = str(attributes.get("park_name") or "Public parking area").strip()
        capacity = _positive_int(attributes.get("spaces"))
        is_accessible = str(attributes.get("disable") or "").strip().lower() in {"y", "yes", "true", "1"}
        records.append(_record(
            f"wodonga-{identifier}", name, "Wodonga", coordinate, source,
            capacity=capacity, accessible_spaces=capacity if is_accessible else None,
            schedules=_wodonga_schedules(attributes),
        ))
    return records


def build_manningham_records(features: list[dict[str, Any]], *, checked_at: str) -> list[dict[str, Any]]:
    source = _source(
        "manningham-council-carparks", "Manningham Council car parks",
        "https://services5.arcgis.com/DRwxVzcV3wgNIuSu/arcgis/rest/services/ManninghamCarparks/FeatureServer/0",
        checked_at, license_name="Manningham Council public ArcGIS service",
    )
    records: list[dict[str, Any]] = []
    for feature in features:
        attributes = feature.get("attributes") or {}
        coordinate = _feature_coordinate(feature)
        if not coordinate:
            continue
        identifier = _safe_component(attributes.get("ASSET_ID_ASSETIC"), attributes.get("OBJECTID") or len(records))
        name = str(attributes.get("ASSETNAME") or attributes.get("ASSETZONE") or "Council car park").strip()
        records.append(_record(f"manningham-{identifier}", name, "Manningham", coordinate, source))
    return records


def build_latrobe_records(features: list[dict[str, Any]], *, checked_at: str) -> list[dict[str, Any]]:
    source = _source(
        "latrobe-accessible-parking", "Latrobe City accessible parking",
        "https://services-ap1.arcgis.com/AtixmNNZDz8cwc9l/arcgis/rest/services/Accessible_Parking%20View/FeatureServer/0",
        checked_at, license_name="Latrobe City Council public ArcGIS service",
    )
    records: list[dict[str, Any]] = []
    for feature in features:
        attributes = feature.get("attributes") or {}
        coordinate = _feature_coordinate(feature)
        if not coordinate:
            continue
        locality = str(attributes.get("Locality") or "Latrobe City").strip()
        descriptor = str(attributes.get("Larger_Car") or attributes.get("Access_To_") or "Accessible parking").strip()
        timed = str(attributes.get("Timed") or "").strip()
        max_stay = _parse_duration_minutes(timed)
        schedules = [_schedule(range(1, 8), 0, 24 * 60, max_stay, timed)] if max_stay else []
        records.append(_record(
            f"latrobe-accessible-{_safe_component(attributes.get('OBJECTID'), len(records))}",
            f"{descriptor} · {locality}", "Latrobe", coordinate, source,
            kind="on_street", accessible_spaces=1, schedules=schedules,
        ))
    return records


def build_mildura_accessible_records(features: list[dict[str, Any]], *, checked_at: str) -> list[dict[str, Any]]:
    updated_values = [
        str((feature.get("properties") or {}).get("Updated") or "")
        for feature in features
        if re.fullmatch(r"\d{8}", str((feature.get("properties") or {}).get("Updated") or ""))
    ]
    latest = max(updated_values, default="")
    dataset_updated_at = f"{latest[:4]}-{latest[4:6]}-{latest[6:]}T00:00:00Z" if latest else None
    source = _source(
        "mildura-accessible-parking", "Mildura Rural City Council",
        "https://data.gov.au/data/dataset/mildura-rural-city-council-disabled-carparks",
        checked_at,
        license_name="Creative Commons Attribution 3.0 Australia",
        license_url="https://creativecommons.org/licenses/by/3.0/au/",
        dataset_updated_at=dataset_updated_at,
    )
    records: list[dict[str, Any]] = []
    for feature in features:
        properties = feature.get("properties") or {}
        coordinates = (feature.get("geometry") or {}).get("coordinates") or []
        coordinate = _coordinate(coordinates[1], coordinates[0]) if len(coordinates) >= 2 else None
        if not coordinate or str(properties.get("Mode") or "").strip().lower() != "disabled":
            continue
        identifier = _safe_component(properties.get("Ref"), len(records))
        location = str(properties.get("Location") or "").strip()
        address = str(properties.get("Address") or "").strip()
        name = " · ".join(value for value in (location, address) if value) or "Accessible parking bay"
        capacity = _positive_int(properties.get("Capacity")) or 1
        max_stay = _positive_int(properties.get("Minsmax"))
        days = _parse_days(str(properties.get("Days") or "")) or list(range(1, 8))
        schedules = [
            _schedule(days, 0, 24 * 60, max_stay, f"Accessible parking · up to {max_stay} min")
        ] if max_stay else []
        tariffs = []
        try:
            hourly_fee = float(properties.get("Hourlyfee"))
        except (TypeError, ValueError):
            hourly_fee = None
        if hourly_fee == 0:
            tariffs = [_tariff(dataset_updated_at or "2000-01-01T00:00:00Z", days, 0, 24 * 60, hourly_cents=0)]
        kind = "on_street" if str(properties.get("Type") or "").strip().lower() == "street" else "off_street"
        records.append(_record(
            f"mildura-accessible-{identifier}", name, "Mildura", coordinate, source,
            kind=kind, capacity=capacity, accessible_spaces=capacity,
            schedules=schedules, tariffs=tariffs,
        ))
    return records


def build_swan_hill_accessible_records(rows: list[dict[str, Any]], *, checked_at: str) -> list[dict[str, Any]]:
    source = _source(
        "swan-hill-accessible-parking", "Swan Hill Rural City Council",
        "https://data.gov.au/data/dataset/swan-hill-rural-city-council-disabled-parking",
        checked_at,
        license_name="Creative Commons Attribution 3.0 Australia",
        license_url="https://creativecommons.org/licenses/by/3.0/au/",
        dataset_updated_at="2025-11-21T02:31:17Z",
    )
    records: list[dict[str, Any]] = []
    for row in rows:
        coordinate = _coordinate(row.get("lat"), row.get("lon"))
        if not coordinate:
            continue
        identifier = _safe_component(row.get("id"), len(records))
        name = str(row.get("name") or "Accessible parking bay").strip()
        records.append(_record(
            f"swan-hill-accessible-{identifier}", name, "Swan Hill", coordinate, source,
            kind="on_street", capacity=1, accessible_spaces=1,
        ))
    return records


def build_port_phillip_accessible_records(features: list[dict[str, Any]], *, checked_at: str) -> list[dict[str, Any]]:
    source = _source(
        "port-phillip-accessible-parking", "City of Port Phillip",
        "https://data.gov.au/data/dataset/city-of-port-phillip-accessible-parking",
        checked_at,
        license_name="Creative Commons Attribution 2.5 Australia",
        license_url="https://creativecommons.org/licenses/by/2.5/au/",
        dataset_updated_at="2022-08-11T05:43:28Z",
    )
    records: list[dict[str, Any]] = []
    for feature in features:
        properties = feature.get("properties") or {}
        raw_identifier = properties.get("Table_Row_ID")
        if raw_identifier is None or str(raw_identifier).strip() == "":
            continue
        identifier = _safe_component(raw_identifier, "")
        if not identifier:
            continue
        geometry = feature.get("geometry") or {}
        if geometry.get("type") not in (None, "Point"):
            continue
        coordinates = geometry.get("coordinates") or []
        coordinate = _coordinate(coordinates[1], coordinates[0]) if len(coordinates) >= 2 else None
        if not coordinate:
            continue
        records.append(_record(
            f"port-phillip-accessible-{identifier}", "Accessible parking location", "Port Phillip",
            coordinate, source, kind="unknown",
        ))
    return records


def _glen_eira_stable_id(properties: dict[str, Any]) -> Any:
    for key in ("ID", "id", "Id", "ogr_fid", "OGR_FID", "FID", "fid"):
        value = properties.get(key)
        if value is not None and str(value).strip() != "":
            return value
    return None


def _glen_eira_spaces(properties: dict[str, Any]) -> int | None:
    for key in ("Spaces", "spaces", "SPACES"):
        if properties.get(key) is not None:
            parsed = _positive_int(properties.get(key))
            # Distinguish missing/invalid (None) from explicit non-positive; both reject.
            if parsed is not None:
                return parsed
            return None
    return None


def build_glen_eira_accessible_records(features: list[dict[str, Any]], *, checked_at: str) -> list[dict[str, Any]]:
    source = _source(
        "glen-eira-accessible-parking", "Glen Eira City Council",
        "https://data.gov.au/data/dataset/accessible-parking",
        checked_at,
        license_name="Creative Commons Attribution 2.5 Australia",
        license_url="https://creativecommons.org/licenses/by/2.5/au/",
        dataset_updated_at="2022-08-01T04:22:41Z",
    )
    records: list[dict[str, Any]] = []
    seen_locations: set[tuple[float, float, int]] = set()
    for feature in features:
        properties = feature.get("properties") or {}
        raw_identifier = _glen_eira_stable_id(properties)
        if raw_identifier is None:
            continue
        identifier = _safe_component(raw_identifier, "")
        if not identifier:
            continue
        accessible_spaces = _glen_eira_spaces(properties)
        if accessible_spaces is None:
            continue
        geometry = feature.get("geometry") or {}
        if geometry.get("type") not in (None, "Point"):
            continue
        coordinates = geometry.get("coordinates") or []
        coordinate = _coordinate(coordinates[1], coordinates[0]) if len(coordinates) >= 2 else None
        if not coordinate:
            continue
        location_key = (
            coordinate["latitude"], coordinate["longitude"], accessible_spaces
        )
        # The published file contains an exact duplicate pair (source IDs 119
        # and 120). Keep the first stable source row instead of presenting the
        # same bay twice; nearby bays with different coordinates or counts stay.
        if location_key in seen_locations:
            continue
        seen_locations.add(location_key)
        records.append(_record(
            f"glen-eira-accessible-{identifier}", "Accessible parking bay", "Glen Eira",
            coordinate, source, kind="unknown", accessible_spaces=accessible_spaces,
        ))
    return records


_BRIMBANK_DATASET_UPDATED_AT = "2019-03-12T00:00:00Z"
_BRIMBANK_LICENSE_NAME = "Creative Commons Attribution 2.5 Australia"
_BRIMBANK_LICENSE_URL = "https://creativecommons.org/licenses/by/2.5/au/"
_BRIMBANK_EXCLUDED_RESTRICTION_SUBSTRINGS = (
    "no stopping",
    "no parking",
    "bus zone",
    "loading zone",
    "taxi zone",
    "permit zone",
    "staff excepted",
    "council vehicles excepted",
    "library staff excepted",
    "drop off zone",
    "clearway",
    "disabled only",
)


def _brimbank_coordinate(properties: dict[str, Any]) -> dict[str, float] | None:
    for lat_key in ("Lat", "LAT", "lat", "Latitude", "LATITUDE"):
        for lon_key in ("Long", "LONG", "long", "Lon", "LON", "lon", "Longitude", "LONGITUDE", "Lng", "LNG"):
            if properties.get(lat_key) is not None and properties.get(lon_key) is not None:
                coordinate = _coordinate(properties.get(lat_key), properties.get(lon_key))
                if coordinate:
                    return coordinate
    return None


def build_brimbank_carpark_records(features: list[dict[str, Any]], *, checked_at: str) -> list[dict[str, Any]]:
    source = _source(
        "brimbank-carparks", "Brimbank City Council",
        "https://data.gov.au/data/dataset/brimbank-carparks",
        checked_at,
        license_name=_BRIMBANK_LICENSE_NAME,
        license_url=_BRIMBANK_LICENSE_URL,
        dataset_updated_at=_BRIMBANK_DATASET_UPDATED_AT,
    )
    records: list[dict[str, Any]] = []
    for feature in features:
        properties = feature.get("properties") or {}
        restriction = str(properties.get("Parking_Re") or "")
        lowered = restriction.lower()
        if any(phrase in lowered for phrase in _BRIMBANK_EXCLUDED_RESTRICTION_SUBSTRINGS):
            continue
        raw_identifier = feature.get("id")
        if raw_identifier is None or str(raw_identifier).strip() == "":
            continue
        identifier = _safe_component(raw_identifier, "")
        if not identifier:
            continue
        name = str(properties.get("Type") or "").strip()
        if not name:
            continue
        coordinate = geometry_centroid(feature.get("geometry")) or _brimbank_coordinate(properties)
        if not coordinate:
            continue
        capacity = _positive_int(properties.get("Num_Of_Bay"))
        records.append(_record(
            f"brimbank-{identifier}", name, "Brimbank", coordinate, source,
            kind="unknown", capacity=capacity,
        ))
    return records


def build_brimbank_disabled_records(features: list[dict[str, Any]], *, checked_at: str) -> list[dict[str, Any]]:
    source = _source(
        "brimbank-disabled-car-parks", "Brimbank City Council",
        "https://data.gov.au/data/dataset/brimbank-disabled-car-parks",
        checked_at,
        license_name=_BRIMBANK_LICENSE_NAME,
        license_url=_BRIMBANK_LICENSE_URL,
        dataset_updated_at=_BRIMBANK_DATASET_UPDATED_AT,
    )
    records: list[dict[str, Any]] = []
    for feature in features:
        properties = feature.get("properties") or {}
        raw_identifier = feature.get("id")
        if raw_identifier is None or str(raw_identifier).strip() == "":
            continue
        identifier = _safe_component(raw_identifier, "")
        if not identifier:
            continue
        type_text = str(properties.get("Type") or "").strip()
        location_text = str(properties.get("Location") or "").strip()
        if type_text and location_text:
            name = f"{type_text} · {location_text}"
        else:
            name = type_text or location_text or "Accessible parking bay"
        coordinate = geometry_centroid(feature.get("geometry")) or _brimbank_coordinate(properties)
        if not coordinate:
            continue
        accessible_spaces = _positive_int(properties.get("Num_Of_Bay"))
        records.append(_record(
            f"brimbank-disabled-{identifier}", name, "Brimbank", coordinate, source,
            kind="unknown", accessible_spaces=accessible_spaces,
        ))
    return records


def build_vicmap_parking_records(
    features: list[dict[str, Any]], *, checked_at: str, dataset_updated_at: str | None,
) -> list[dict[str, Any]]:
    source = _source(
        "vicmap-features-of-interest-parking", "Vicmap Features of Interest",
        VICMAP_FOI_URL, checked_at,
        license_name="Creative Commons Attribution 4.0",
        license_url="https://creativecommons.org/licenses/by/4.0/",
        dataset_updated_at=dataset_updated_at,
    )
    records: list[dict[str, Any]] = []
    for feature in features:
        attributes = feature.get("attributes") or {}
        if str(attributes.get("feature_subtype") or "").strip().lower() != "parking area":
            continue
        coordinate = _feature_coordinate(feature)
        if not coordinate:
            continue
        identifier = _safe_component(attributes.get("feature_ufi") or attributes.get("ufi"), attributes.get("OBJECTID") or len(records))
        name = str(attributes.get("name_label") or attributes.get("name") or attributes.get("parent_name") or "Mapped parking area").strip()
        records.append(_record(
            f"vicmap-parking-{identifier}", name, "Victoria", coordinate, source,
            kind="off_street",
        ))
    return records


def build_moorabool_records(features: list[dict[str, Any]], *, checked_at: str) -> list[dict[str, Any]]:
    source = _source(
        "moorabool-carparks", "Moorabool Shire car parks",
        "https://services8.arcgis.com/LhxDRRTcDHsigpYl/arcgis/rest/services/Carpark/FeatureServer/0",
        checked_at, license_name="Moorabool Shire Council public ArcGIS service",
    )
    excluded_statuses = {"inactive", "disposed", "decommissioned", "deleted", "proposed"}
    records: list[dict[str, Any]] = []
    for feature in features:
        attributes = feature.get("attributes") or {}
        if str(attributes.get("Status") or "").strip().lower() in excluded_statuses:
            continue
        coordinate = _feature_coordinate(feature)
        if not coordinate:
            continue
        identifier = _safe_component(attributes.get("AssetId") or attributes.get("Id"), attributes.get("FID") or len(records))
        name = str(attributes.get("Name") or attributes.get("Location") or attributes.get("Locality") or "Public car park").strip()
        records.append(_record(f"moorabool-{identifier}", name, "Moorabool", coordinate, source))
    return records


def build_colac_otway_records(features: list[dict[str, Any]], *, checked_at: str) -> list[dict[str, Any]]:
    source = _source(
        "colac-otway-carparks", "Shepherd Services / Colac Otway carparks",
        "https://services1.arcgis.com/bLsSwu2wpv4JvxHE/arcgis/rest/services/Colac_Otway_Carparks/FeatureServer/0",
        checked_at, license_name="Public contractor-hosted ArcGIS service",
    )
    excluded_statuses = {"inactive", "disposed", "decommissioned", "deleted", "proposed"}
    records: list[dict[str, Any]] = []
    for feature in features:
        attributes = feature.get("attributes") or {}
        if str(attributes.get("Status") or "").strip().lower() in excluded_statuses:
            continue
        coordinate = _feature_coordinate(feature)
        if not coordinate:
            continue
        identifier = _safe_component(attributes.get("Carpark_AM_ID"), attributes.get("OBJECTID") or attributes.get("ObjectID") or len(records))
        street = str(attributes.get("Street_Name") or "").strip()
        location = str(attributes.get("Location") or "").strip()
        name = " · ".join(value for value in (street, location) if value) or "Mapped car park"
        kind = "on_street" if "on" in str(attributes.get("Type") or "").lower() else "off_street"
        records.append(_record(f"colac-otway-{identifier}", name, "Colac Otway", coordinate, source, kind=kind))
    return records


def build_monash_records(
    street_features: list[dict[str, Any]], carpark_features: list[dict[str, Any]], *, checked_at: str,
) -> list[dict[str, Any]]:
    source = _source(
        "monash-wga-parking-review", "WGA / City of Monash parking review",
        "https://services8.arcgis.com/GAZiuYWXmnwzoGFY/arcgis/rest/services/WGA240930_City_of_Monash_Parking_Layer/FeatureServer",
        checked_at, license_name="Public consultant-hosted ArcGIS study layer",
    )
    records: list[dict[str, Any]] = []
    for kind, features in (("on_street", street_features), ("off_street", carpark_features)):
        for feature in features:
            attributes = feature.get("attributes") or {}
            coordinate = _feature_coordinate(feature)
            if not coordinate:
                continue
            raw_identifier = attributes.get("LocationID") or attributes.get("OBJECTID") or len(records)
            identifier = _safe_component(raw_identifier, len(records))
            readable = re.sub(r"[_-]+", " ", str(raw_identifier)).strip()
            prefix = "Street parking" if kind == "on_street" else "Car park"
            records.append(_record(f"monash-{kind}-{identifier}", f"{prefix} · {readable}", "Monash", coordinate, source, kind=kind))
    return records


def build_southern_grampians_records(features: list[dict[str, Any]], *, checked_at: str) -> list[dict[str, Any]]:
    source = _source(
        "southern-grampians-carpark-inspection-2024", "Shepherd Services / Southern Grampians carpark inspection 2024",
        "https://services1.arcgis.com/bLsSwu2wpv4JvxHE/arcgis/rest/services/southern_grampians_carpark_inspection_2024/FeatureServer/0",
        checked_at, license_name="Public contractor-hosted ArcGIS inspection layer", dataset_updated_at="2024-12-31T00:00:00Z",
    )
    records: list[dict[str, Any]] = []
    for feature in features:
        attributes = feature.get("attributes") or {}
        if str(attributes.get("carpark_yesno") or "yes").strip().lower() in {"no", "n", "false", "0"}:
            continue
        coordinate = _feature_coordinate(feature)
        if not coordinate:
            continue
        identifier = _safe_component(attributes.get("asset_id") or attributes.get("fulcrum_id"), attributes.get("ObjectId") or len(records))
        name = str(attributes.get("asset_description") or attributes.get("road_name") or "Inspected car park").strip()
        records.append(_record(f"southern-grampians-{identifier}", name, "Southern Grampians", coordinate, source))
    return records


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


_OSM_DAY_NAMES = {"Mo": "Mon", "Tu": "Tue", "We": "Wed", "Th": "Thu", "Fr": "Fri", "Sa": "Sat", "Su": "Sun"}


def _parse_osm_window(value: str) -> tuple[list[int], int, int] | None:
    normalized = value.strip()
    if normalized == "24/7":
        return list(range(1, 8)), 0, 24 * 60
    if ";" in normalized or "," in normalized:
        return None
    match = re.fullmatch(r"([A-Za-z-]+)\s+(\d{1,2}:\d{2}\s*-\s*\d{1,2}:\d{2})", normalized)
    if not match:
        return None
    day_text = match.group(1)
    for short, full in _OSM_DAY_NAMES.items():
        day_text = re.sub(rf"(?<![A-Za-z]){short}(?![A-Za-z])", full, day_text)
    days = _parse_days(day_text)
    times = _parse_24_hour_range(match.group(2))
    return (days, times[0], times[1]) if days and times else None


def _parse_osm_conditional(value: str) -> tuple[str, tuple[list[int], int, int]] | None:
    match = re.fullmatch(r"\s*(.+?)\s*@\s*\((.+)\)\s*", value)
    if not match:
        return None
    window = _parse_osm_window(match.group(2))
    return (match.group(1).strip(), window) if window else None


def _osm_tariff(charge: str, days: list[int], start: int, end: int) -> dict[str, Any] | None:
    normalized = charge.strip().lower().replace("aud", "").strip()
    match = re.fullmatch(r"\$?\s*(\d+(?:\.\d{1,2})?)\s*/\s*(hour|hr|h|day|daily)", normalized)
    if not match:
        return None
    cents = round(float(match.group(1)) * 100)
    if match.group(2) in {"day", "daily"}:
        return _tariff("2000-01-01T00:00:00Z", days, start, end, daily_cap_cents=cents)
    return _tariff("2000-01-01T00:00:00Z", days, start, end, hourly_cents=cents)


def _osm_schedules(tags: dict[str, Any]) -> list[dict[str, Any]]:
    schedules: list[dict[str, Any]] = []
    unconditional = _parse_duration_minutes(tags.get("maxstay"))
    opening_raw = str(tags.get("opening_hours") or "").strip()
    window = _parse_osm_window(opening_raw) if opening_raw else (list(range(1, 8)), 0, 24 * 60)
    if unconditional and window:
        schedules.append(_schedule(
            window[0], window[1], window[2], unconditional,
            f"OSM maxstay {tags.get('maxstay')}", outside_unrestricted=bool(opening_raw),
        ))
    elif unconditional and opening_raw:
        schedules.append(_schedule(
            range(1, 8), 0, 24 * 60, None, f"Unparsed OSM opening_hours: {opening_raw}",
            unparsed_condition=opening_raw,
        ))
    conditional_raw = str(tags.get("maxstay:conditional") or "").strip()
    conditional = _parse_osm_conditional(conditional_raw)
    if conditional:
        duration = _parse_duration_minutes(conditional[0])
        if duration:
            condition_window = conditional[1]
            schedules.append(_schedule(
                condition_window[0], condition_window[1], condition_window[2], duration,
                f"OSM conditional maxstay {conditional[0]}", outside_unrestricted=True,
            ))
    elif conditional_raw:
        schedules.append(_schedule(
            range(1, 8), 0, 24 * 60, None, f"Unparsed OSM maxstay condition: {conditional_raw}",
            unparsed_condition=conditional_raw,
        ))
    return schedules


def _osm_tariffs(tags: dict[str, Any]) -> list[dict[str, Any]]:
    fee = str(tags.get("fee") or "").strip().lower()
    if fee in {"no", "free"}:
        return [_tariff("2000-01-01T00:00:00Z", range(1, 8), 0, 24 * 60, hourly_cents=0)]
    conditional_raw = str(tags.get("charge:conditional") or "").strip()
    conditional = _parse_osm_conditional(conditional_raw)
    if conditional:
        value, window = conditional
        tariff = _osm_tariff(value, window[0], window[1], window[2])
        if tariff:
            return [tariff]
    if conditional_raw:
        return [_tariff(
            "2000-01-01T00:00:00Z", range(1, 8), 0, 24 * 60,
            unparsed_condition=conditional_raw,
        )]
    opening_raw = str(tags.get("opening_hours") or "").strip()
    window = _parse_osm_window(opening_raw) if opening_raw else (list(range(1, 8)), 0, 24 * 60)
    charge_raw = str(tags.get("charge") or "").strip()
    tariff = _osm_tariff(charge_raw, window[0], window[1], window[2]) if window else None
    if tariff:
        return [tariff]
    if charge_raw:
        return [_tariff(
            "2000-01-01T00:00:00Z", range(1, 8), 0, 24 * 60,
            unparsed_condition=charge_raw,
        )]
    return []


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
        tariffs = _osm_tariffs(tags)
        schedules = _osm_schedules(tags)
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
            kind=kind, archetype=archetype, capacity=capacity, accessible_spaces=accessible,
            schedules=schedules, tariffs=tariffs,
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

    bendigo = _source(
        "bendigo-hargreaves-multistorey", "City of Greater Bendigo",
        "https://www.bendigo.vic.gov.au/community-services/parking/where-park/hargreaves-street-multi-storey-car-park",
        checked_at, license_name="Official council facility page",
    )
    records.append(_record(
        "bendigo-hargreaves-multistorey", "Hargreaves Street Multi-Storey Car Park", "Greater Bendigo",
        _coordinate(-36.7588004, 144.2812571), bendigo, archetype="cbd_retail", capacity=290,
        accessible_spaces=6,
        schedules=[
            _schedule([2, 3, 4, 5], 7 * 60, 19 * 60 + 30, None, "Open 7:00 am–7:30 pm"),
            _schedule([6], 7 * 60, 22 * 60, None, "Open 7:00 am–10:00 pm"),
            _schedule([7], 7 * 60, 22 * 60, None, "Open 7:00 am–10:00 pm · free parking"),
            _schedule([1], 7 * 60, 18 * 60, None, "Open 7:00 am–6:00 pm · free parking"),
        ],
        tariffs=[
            _tariff("2026-07-01T00:00:00+10:00", [2, 3, 4, 5, 6], 7 * 60, 22 * 60,
                    hourly_cents=240, daily_cap_cents=1000),
            _tariff("2026-07-01T00:00:00+10:00", [1, 7], 7 * 60, 22 * 60, hourly_cents=0),
        ],
    ))

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

    geelong = _source(
        "geelong-central-2p", "City of Greater Geelong",
        "https://yoursay.geelongaustralia.com.au/digital-parking/central-geelong-moving-100-cent-digital-parking",
        checked_at, license_name="Official council parking notice",
        dataset_updated_at="2026-02-25T00:00:00+11:00",
    )
    records.append(_record(
        "geelong-central-2p", "Central Geelong signed 2P parking area", "Greater Geelong",
        _coordinate(-38.14717, 144.36043), geelong, kind="on_street", archetype="cbd_retail",
        schedules=[_schedule(range(1, 8), 0, 24 * 60, 120, "2P signed spaces", public_holidays=True)],
        tariffs=[_tariff("2026-03-09T00:00:00+11:00", range(1, 8), 0, 24 * 60, hourly_cents=0)],
    ))

    wangaratta = _source(
        "wangaratta-cbd-paid", "Rural City of Wangaratta",
        "https://www.wangaratta.vic.gov.au/Services/Parking/Parking-FAQs",
        checked_at, license_name="Official council parking FAQ",
    )
    records.append(_record(
        "wangaratta-cbd-paid", "Wangaratta CBD standard paid parking", "Wangaratta",
        _coordinate(-36.35518, 146.32547), wangaratta, kind="on_street", archetype="cbd_retail",
        schedules=[_schedule([2, 3, 4, 5, 6], 9 * 60, 17 * 60, None,
                             "Paid bays · check posted time limit", outside_unrestricted=True)],
        tariffs=[_tariff("2025-05-27T00:00:00+10:00", [2, 3, 4, 5, 6], 9 * 60, 17 * 60, hourly_cents=120)],
    ))

    horsham = _source(
        "horsham-cbd-free-2p", "Horsham Rural City Council",
        "https://www.hrcc.vic.gov.au/Our-Council/News-and-Media/Latest-News/council-removing-parking-maters",
        checked_at, license_name="Official council parking decision",
        dataset_updated_at="2025-06-25T00:00:00+10:00",
    )
    records.append(_record(
        "horsham-cbd-free-2p", "Horsham CBD signed free 2P parking", "Horsham",
        _coordinate(-36.71491, 142.19978), horsham, kind="on_street", archetype="cbd_retail",
        schedules=[_schedule(range(1, 8), 0, 24 * 60, 120, "Free 2P signed area", public_holidays=True)],
        tariffs=[_tariff("2025-06-25T00:00:00+10:00", range(1, 8), 0, 24 * 60, hourly_cents=0)],
    ))

    swan_hill = _source(
        "swan-hill-curlewis-ticketed", "Swan Hill Rural City Council",
        "https://www.swanhill.vic.gov.au/Our-Council/News-and-publications/News-and-public-notices/Council-Leases-Curlewis-Street-Carpark-to-Boost-CBD-Parking-Options",
        checked_at, license_name="Official council parking notice",
    )
    records.append(_record(
        "swan-hill-curlewis-ticketed", "Curlewis Street ticketed parking area", "Swan Hill",
        _coordinate(-35.33950, 143.56150), swan_hill, kind="on_street", archetype="cbd_retail",
        schedules=[_schedule([2, 3, 4, 5, 6], 9 * 60, 17 * 60 + 30, 120, "2P ticketed area", outside_unrestricted=True)],
        tariffs=[_tariff("2026-02-02T00:00:00+11:00", [2, 3, 4, 5, 6], 9 * 60, 17 * 60 + 30, hourly_cents=140)],
    ))

    # Greater Dandenong council facility pages verified 2026-09-19. Pages expose
    # no resource date, so sources carry checkedAt only (no datasetUpdatedAt).
    # Their fee tables do not publish an effective date; the model requires one,
    # so tariffs are deliberately withheld rather than assigned a guessed date.
    number_8 = _source(
        "greater-dandenong-number-8", "City of Greater Dandenong",
        "https://www.greaterdandenong.vic.gov.au/number-8-car-park",
        checked_at, license_name="Official council facility page",
    )
    records.append(_record(
        "greater-dandenong-number-8", "Number 8 Balmoral Avenue Multi-deck Car Park", "Greater Dandenong",
        _coordinate(-37.949639, 145.151733), number_8, kind="off_street",
        # The page says "more than 500". The model represents exact capacities
        # only, so retain the useful facility without inventing an exact count.
        capacity=None,
        schedules=[_schedule(range(1, 8), 7 * 60, 23 * 60, None, "Open 7:00 am–11:00 pm")],
        tariffs=[],
    ))

    thomas_street = _source(
        "greater-dandenong-thomas-street", "City of Greater Dandenong",
        "https://www.greaterdandenong.vic.gov.au/council-car-parks/thomas-street-multi-deck-car-park",
        checked_at, license_name="Official council facility page",
    )
    records.append(_record(
        "greater-dandenong-thomas-street", "Thomas Street Multi-deck Car Park", "Greater Dandenong",
        _coordinate(-37.986932, 145.212884), thomas_street, kind="off_street",
        schedules=[
            _schedule([2, 3, 4, 5, 6, 7], 6 * 60, 22 * 60, None, "Open 6:00 am–10:00 pm"),
            _schedule([1], 9 * 60, 22 * 60, None, "Open 9:00 am–10:00 pm"),
        ],
        tariffs=[],
    ))

    walker_street = _source(
        "greater-dandenong-walker-street", "City of Greater Dandenong",
        "https://www.greaterdandenong.vic.gov.au/council-car-parks/walker-street-multi-deck-car-park",
        checked_at, license_name="Official council facility page",
    )
    records.append(_record(
        "greater-dandenong-walker-street", "Walker Street Multi-deck Car Park", "Greater Dandenong",
        _coordinate(-37.987707, 145.211924), walker_street, kind="off_street",
        schedules=[
            # Cross-midnight Mon-Sat 06:00–01:00 encoded with end > 24h,
            # matching the existing Whitehorse cross-midnight pattern.
            _schedule([2, 3, 4, 5, 6, 7], 6 * 60, 24 * 60 + 60, None, "Open 6:00 am–1:00 am"),
            _schedule([1], 9 * 60, 23 * 60, None, "Open 9:00 am–11:00 pm"),
        ],
        tariffs=[],
    ))

    carroll_lane = _source(
        "greater-dandenong-carroll-lane", "City of Greater Dandenong",
        "https://www.greaterdandenong.vic.gov.au/council-car-parks/carroll-lane-car-park",
        checked_at, license_name="Official council facility page",
    )
    records.append(_record(
        "greater-dandenong-carroll-lane", "Carroll Lane Car Park", "Greater Dandenong",
        _coordinate(-37.989876, 145.207576), carroll_lane, kind="off_street",
        schedules=[_schedule(range(1, 8), 0, 24 * 60, None, "Open 24 hours")],
        # No tariff: page offers free parking only for public-transport users
        # and the tariff model cannot represent that user condition, so an
        # unconditional free tariff would mislead.
        tariffs=[],
    ))
    return records


_LGA_SHORT_NAME_EXCEPTIONS = {
    "MERRI-BEK": "Merri-bek",
}


def lga_short_municipality_name(lga_name: str) -> str:
    """Title-case Vicmap lga_name values to match existing catalog municipality labels."""

    stripped = " ".join(str(lga_name or "").split())
    if not stripped:
        return stripped
    return _LGA_SHORT_NAME_EXCEPTIONS.get(stripped.upper(), stripped.title())


def assign_spatial_municipality(
    records: list[dict[str, Any]], geojson: dict[str, Any]
) -> list[dict[str, Any]]:
    """Replace generic statewide municipality labels using Vicmap LGA polygons.

    Only records whose municipality is exactly "Victoria" are rewritten. Source
    provenance, identifiers, classification, schedules, and tariffs stay intact.
    Points outside every polygon, including polygon holes, remain "Victoria".
    """

    areas = lga_areas_from_geojson(geojson)
    for record in records:
        if record.get("municipality") != "Victoria":
            continue
        coordinate = record.get("coordinate") or {}
        try:
            point = (float(coordinate["longitude"]), float(coordinate["latitude"]))
        except (KeyError, TypeError, ValueError):
            continue
        match = matching_lga(areas, point)
        if match is None:
            continue
        short_name = lga_short_municipality_name((match or {}).get("name", ""))
        if not short_name:
            continue
        record["municipality"] = short_name
    return records


def locality_summary(records: list[dict[str, Any]]) -> dict[str, int]:
    """Manifest-facing locality counts derived only from assigned records."""
    labeled = sum(1 for record in records if record.get("locality"))
    return {
        "localityLabeled": labeled,
        "localityUnmatched": len(records) - labeled,
        "localityDistinct": len(
            {record.get("locality") for record in records if record.get("locality")}
        ),
    }


def assign_spatial_locality(
    records: list[dict[str, Any]],
    geojson: dict[str, Any],
    *,
    index: dict[str, Any] | None = None,
    min_count: int = VICMAP_LOCALITY_MIN_SANE_COUNT,
) -> list[dict[str, Any]]:
    """Add suburb/locality only from authoritative Vicmap polygon containment.

    Uses the official Vicmap Admin Locality Boundaries layer 11 polygons
    (CC BY 4.0 International, item 51eed453d31243a795850b765a400769). The
    full paginated result is validated first; a partial page fails closed
    with RuntimeError instead of silently labeling a subset. Points are
    matched through a grid/bounds candidate index plus the shared
    hole-aware Polygon/MultiPolygon containment, never from a record name
    and never via reverse-geocoding.

    Existing locality values are preserved (no overwrite). Unmatched points
    (outside every polygon, inside a hole, or with bad coordinates) keep
    locality absent or null. Municipality, source, IDs, classification,
    kind, schedules, and tariffs are never modified.

    min_count exists only so offline unit fixtures can use tiny polygons;
    production callers must keep the default sane threshold.
    """

    validate_locality_geojson(geojson, min_count=min_count)
    areas = locality_areas_from_geojson(geojson)
    if not areas:
        raise RuntimeError("Locality GeoJSON produced no usable polygons")
    spatial_index = index if index is not None else build_locality_index(areas)
    for record in records:
        if record.get("locality"):
            continue
        coordinate = record.get("coordinate") or {}
        try:
            point = (float(coordinate["longitude"]), float(coordinate["latitude"]))
        except (KeyError, TypeError, ValueError):
            record["locality"] = None
            continue
        match = matching_locality(spatial_index, point)
        if match is None:
            record["locality"] = None
            continue
        label = match.get("name") or natural_locality_name(
            str(match.get("rawName") or "")
        )
        record["locality"] = label or None
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


def fetch_arcgis_features(service_url: str, timeout: int, *, where: str = "1=1") -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    offset = 0
    while True:
        payload = request_json(f"{service_url}/query", {
            "where": where, "outFields": "*", "returnGeometry": "true", "outSR": "4326",
            "resultOffset": offset, "resultRecordCount": 2000, "f": "json",
        }, timeout)
        features = payload.get("features", [])
        output.extend(features)
        if len(features) < 2000:
            return output
        offset += len(features)


def arcgis_dataset_updated_at(service_url: str, timeout: int) -> str | None:
    metadata = request_json(service_url, {"f": "json"}, timeout)
    milliseconds = (metadata.get("editingInfo") or {}).get("dataLastEditDate")
    try:
        return datetime.fromtimestamp(float(milliseconds) / 1000, timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    except (TypeError, ValueError, OSError):
        return None


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
    errors: list[str] = []
    for endpoint in OVERPASS_ENDPOINTS:
        request = urllib.request.Request(
            endpoint, data=data,
            headers={"User-Agent": USER_AGENT, "Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=max(timeout, 240)) as response:
                payload = json.load(response)
            return payload.get("elements", []), (payload.get("osm3s") or {}).get("timestamp_osm_base")
        except Exception as error:
            errors.append(f"{endpoint}: {type(error).__name__}: {error}")
    raise RuntimeError("All Overpass endpoints failed: " + " | ".join(errors))


def build_catalog(
    timeout: int = 45,
    *,
    include_osm: bool = True,
    lga_geojson: dict[str, Any] | None = None,
    locality_geojson: dict[str, Any] | None = None,
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    checked_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    arcgis_root = "https://services2.arcgis.com/PovBcp8J7VQYyDEI/arcgis/rest/services"
    maribyrnong_regular = fetch_arcgis_features(f"{arcgis_root}/Reg_Parking_Bay_GreenZone_Ply/FeatureServer/0", timeout)
    maribyrnong_accessible = fetch_arcgis_features(f"{arcgis_root}/Reg_Parking_Bay_BlueZone_Ply/FeatureServer/0", timeout)
    ballarat = fetch_opendatasoft_rows("https://data.ballarat.vic.gov.au/api/explore/v2.1/catalog/datasets/realtime0", timeout)
    casey_restrictions = fetch_opendatasoft_rows("https://data.casey.vic.gov.au/api/explore/v2.1/catalog/datasets/city-of-casey-parking-zones", timeout)
    casey_stations = fetch_opendatasoft_rows("https://data.casey.vic.gov.au/api/explore/v2.1/catalog/datasets/railway-station-carparks-ptv", timeout)
    boroondara_public = request_json("https://www.boroondara.vic.gov.au/rest/category/locations", {"tid[]": "766"}, timeout)
    boroondara_accessible = request_json("https://www.boroondara.vic.gov.au/rest/category/locations", {"tid[]": "1396"}, timeout)
    wodonga = fetch_arcgis_features("https://services-ap1.arcgis.com/w6r4LlwgJu8O0neQ/arcgis/rest/services/parking_lot_edit_view/FeatureServer/0", timeout)
    manningham = fetch_arcgis_features("https://services5.arcgis.com/DRwxVzcV3wgNIuSu/arcgis/rest/services/ManninghamCarparks/FeatureServer/0", timeout)
    latrobe = fetch_arcgis_features("https://services-ap1.arcgis.com/AtixmNNZDz8cwc9l/arcgis/rest/services/Accessible_Parking%20View/FeatureServer/0", timeout)
    moorabool = fetch_arcgis_features("https://services8.arcgis.com/LhxDRRTcDHsigpYl/arcgis/rest/services/Carpark/FeatureServer/0", timeout)
    colac_otway = fetch_arcgis_features("https://services1.arcgis.com/bLsSwu2wpv4JvxHE/arcgis/rest/services/Colac_Otway_Carparks/FeatureServer/0", timeout)
    monash_streets = fetch_arcgis_features("https://services8.arcgis.com/GAZiuYWXmnwzoGFY/arcgis/rest/services/WGA240930_City_of_Monash_Parking_Layer/FeatureServer/0", timeout)
    monash_carparks = fetch_arcgis_features("https://services8.arcgis.com/GAZiuYWXmnwzoGFY/arcgis/rest/services/WGA240930_City_of_Monash_Parking_Layer/FeatureServer/1", timeout)
    southern_grampians = fetch_arcgis_features("https://services1.arcgis.com/bLsSwu2wpv4JvxHE/arcgis/rest/services/southern_grampians_carpark_inspection_2024/FeatureServer/0", timeout)
    mildura_accessible = request_json(MILDURA_ACCESSIBLE_URL, timeout=timeout).get("features", [])
    swan_hill_accessible = list(csv.DictReader(io.StringIO(request_text(SWAN_HILL_ACCESSIBLE_URL, timeout))))
    port_phillip_accessible = request_json(PORT_PHILLIP_ACCESSIBLE_URL, timeout=timeout).get("features", [])
    glen_eira_accessible = request_json(GLEN_EIRA_ACCESSIBLE_URL, timeout=timeout).get("features", [])
    brimbank_carparks = request_json(BRIMBANK_CARPARK_WFS_URL, timeout=timeout).get("features", [])
    brimbank_disabled = request_json(BRIMBANK_DISABLED_WFS_URL, timeout=timeout).get("features", [])
    vicmap_parking = fetch_arcgis_features(VICMAP_FOI_URL, timeout, where="feature_subtype='parking area'")
    vicmap_updated_at = arcgis_dataset_updated_at(VICMAP_FOI_URL, timeout)

    groups = {
        "maribyrnong": build_maribyrnong_records(maribyrnong_regular, maribyrnong_accessible, checked_at=checked_at),
        "ballarat": build_ballarat_records(ballarat, checked_at=checked_at),
        "casey": build_casey_records(casey_restrictions, casey_stations, checked_at=checked_at),
        "boroondara": build_boroondara_records(boroondara_public, boroondara_accessible, checked_at=checked_at),
        "wodonga": build_wodonga_records(wodonga, checked_at=checked_at),
        "manningham": build_manningham_records(manningham, checked_at=checked_at),
        "latrobe": build_latrobe_records(latrobe, checked_at=checked_at),
        "moorabool": build_moorabool_records(moorabool, checked_at=checked_at),
        "colacOtway": build_colac_otway_records(colac_otway, checked_at=checked_at),
        "monash": build_monash_records(monash_streets, monash_carparks, checked_at=checked_at),
        "southernGrampians": build_southern_grampians_records(southern_grampians, checked_at=checked_at),
        "milduraAccessible": build_mildura_accessible_records(mildura_accessible, checked_at=checked_at),
        "swanHillAccessible": build_swan_hill_accessible_records(swan_hill_accessible, checked_at=checked_at),
        "portPhillipAccessible": build_port_phillip_accessible_records(port_phillip_accessible, checked_at=checked_at),
        "glenEiraAccessible": build_glen_eira_accessible_records(glen_eira_accessible, checked_at=checked_at),
        "brimbankCarparks": build_brimbank_carpark_records(brimbank_carparks, checked_at=checked_at),
        "brimbankDisabled": build_brimbank_disabled_records(brimbank_disabled, checked_at=checked_at),
        "vicmapParking": build_vicmap_parking_records(
            vicmap_parking, checked_at=checked_at, dataset_updated_at=vicmap_updated_at,
        ),
        "curatedOfficial": curated_official_records(checked_at),
    }
    if include_osm:
        osm_elements, osm_updated_at = fetch_osm_parking(timeout)
        groups["openStreetMap"] = build_osm_records(
            osm_elements, checked_at=checked_at, dataset_updated_at=osm_updated_at
        )
    records = deduplicate_records([record for values in groups.values() for record in values])
    boundaries = lga_geojson if lga_geojson is not None else fetch_lga_geojson(
        timeout=max(timeout, 90), user_agent=USER_AGENT
    )
    records = assign_spatial_municipality(records, boundaries)
    locality_boundaries = (
        locality_geojson
        if locality_geojson is not None
        else fetch_locality_geojson(timeout=max(timeout, 90), user_agent=USER_AGENT)
    )
    records = assign_spatial_locality(records, locality_boundaries)
    retained_ids = {record["id"] for record in records}
    claimed_ids: set[str] = set()
    counts: dict[str, int] = {}
    for name, values in groups.items():
        group_ids = {
            record.get("id") for record in values
            if record.get("id") in retained_ids and record.get("id") not in claimed_ids
        }
        counts[name] = len(group_ids)
        claimed_ids.update(group_ids)
    summary = locality_summary(records)
    counts["localityLabeled"] = summary["localityLabeled"]
    counts["localityUnmatched"] = summary["localityUnmatched"]
    counts["localityDistinct"] = summary["localityDistinct"]
    counts["localityPolygons"] = len((locality_boundaries or {}).get("features", []))
    return records, counts


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("ParkAlong/Resources/Generated/victoria_static_parking.json"))
    parser.add_argument("--manifest", type=Path, default=Path("ParkAlong/Resources/Generated/victoria_static_manifest.json"))
    parser.add_argument("--timeout", type=int, default=45)
    parser.add_argument("--without-osm", action="store_true", help="Skip the statewide OpenStreetMap layer")
    args = parser.parse_args()

    records, counts = build_catalog(args.timeout, include_osm=not args.without_osm)
    required_sources = (
        "maribyrnong", "ballarat", "casey", "boroondara", "wodonga", "manningham", "latrobe",
        "moorabool", "colacOtway", "monash", "southernGrampians",
        "milduraAccessible", "swanHillAccessible", "portPhillipAccessible", "glenEiraAccessible",
        "brimbankCarparks", "brimbankDisabled",
        "vicmapParking",
    )
    if not records or any(counts[name] == 0 for name in required_sources):
        raise RuntimeError(f"Required public source produced no records: {counts}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    output = json.dumps(records, separators=(",", ":")).encode("utf-8")
    args.output.write_bytes(output)
    sources = {record["source"]["id"]: record["source"] for record in records}
    source_counts = {
        key: value for key, value in counts.items() if not key.startswith("locality")
    }
    summary = locality_summary(records)
    manifest = {
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "recordCount": len(records),
        "municipalityCount": len({record["municipality"] for record in records}),
        "sourceCount": len(sources),
        "sourceCounts": source_counts,
        "sourceAttributions": [sources[key] for key in sorted(sources)],
        "accessibleRecordCount": sum(1 for record in records if (record.get("accessibleSpaces") or 0) > 0),
        "localityLabeledCount": summary["localityLabeled"],
        "localityUnmatchedCount": summary["localityUnmatched"],
        "localityDistinctCount": summary["localityDistinct"],
        "localityPolygonCount": counts.get("localityPolygons", 0),
        "localityBoundarySource": VICMAP_LOCALITY_QUERY_URL,
        "localityServiceURL": VICMAP_LOCALITY_SERVICE_URL,
        "localityItemId": VICMAP_LOCALITY_ITEM_ID,
        "localityLicenseName": VICMAP_LOCALITY_LICENSE_NAME,
        "localityLicenseURL": VICMAP_LOCALITY_LICENSE_URL,
        "localityDatasetUpdatedAt": VICMAP_LOCALITY_DATASET_UPDATED_AT,
        "outputBytes": args.output.stat().st_size,
        "outputSHA256": hashlib.sha256(output).hexdigest(),
    }
    args.manifest.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps(manifest, sort_keys=True))


if __name__ == "__main__":
    main()
