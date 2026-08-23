#!/usr/bin/env python3
"""Probe anonymous Victorian parking sources without assuming that HTTP 200 means live.

The output deliberately separates live occupancy from historical feeds and static
parking geometry. Network errors and ambiguous records fail closed.
"""

from __future__ import annotations

import argparse
import json
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from typing import Any


USER_AGENT = "ParkAlong-Victoria-Source-Probe/1.0"


def _parse_timestamp(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def classify_occupancy_records(
    records: list[dict[str, Any]],
    *,
    timestamp_field: str,
    occupancy_field: str,
    occupied_values: set[str],
    vacant_values: set[str],
    now: datetime | None = None,
    max_age_hours: int = 24,
    future_skew_minutes: int = 5,
) -> dict[str, Any]:
    """Classify timestamped occupancy records using ParkAlong's fail-closed rule."""

    checked_at = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    cutoff = checked_at - timedelta(hours=max_age_hours)
    future_limit = checked_at + timedelta(minutes=future_skew_minutes)
    accepted = {str(value) for value in occupied_values | vacant_values}

    observed: list[tuple[datetime, str]] = []
    recognized: list[tuple[datetime, str, str]] = []
    trusted: list[tuple[datetime, str, str]] = []
    for record in records:
        raw_timestamp = record.get(timestamp_field)
        parsed = _parse_timestamp(raw_timestamp)
        if parsed is not None:
            observed.append((parsed, str(raw_timestamp)))

        raw_state = record.get(occupancy_field)
        state = str(raw_state) if raw_state is not None else ""
        if parsed is None or state not in accepted:
            continue
        recognized.append((parsed, str(raw_timestamp), state))
        if cutoff <= parsed <= future_limit:
            trusted.append((parsed, str(raw_timestamp), state))

    if trusted:
        classification = "verified_live_occupancy"
    elif recognized and max(item[0] for item in recognized) < cutoff:
        classification = "stale_or_historical"
    else:
        classification = "ambiguous_or_unverified"

    newest_observed = max(observed, default=None, key=lambda item: item[0])
    newest_trusted = max(trusted, default=None, key=lambda item: item[0])
    return {
        "classification": classification,
        "totalRows": len(records),
        "trustedRows": len(trusted),
        "rejectedRows": len(records) - len(trusted),
        "newestObservedTimestamp": newest_observed[1] if newest_observed else None,
        "newestTrustedTimestamp": newest_trusted[1] if newest_trusted else None,
    }


def _request_json(
    url: str,
    *,
    timeout: int,
    query: dict[str, Any] | None = None,
    body: str | None = None,
) -> dict[str, Any]:
    if query:
        url = f"{url}?{urllib.parse.urlencode(query)}"
    data = body.encode("utf-8") if body is not None else None
    headers = {"User-Agent": USER_AGENT}
    if body is not None:
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    request = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def probe_melbourne(timeout: int) -> dict[str, Any]:
    dataset_url = "https://data.melbourne.vic.gov.au/api/explore/v2.1/catalog/datasets/on-street-parking-bay-sensors"
    metadata = _request_json(dataset_url, timeout=timeout)
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(hours=24)
    future_limit = now + timedelta(minutes=5)
    where = (
        f"status_timestamp >= date'{cutoff.isoformat().replace('+00:00', 'Z')}' "
        f"AND status_timestamp <= date'{future_limit.isoformat().replace('+00:00', 'Z')}' "
        "AND zone_number is not null AND location is not null "
        "AND status_description in ('Present','Unoccupied')"
    )
    payload = _request_json(
        f"{dataset_url}/records",
        timeout=timeout,
        query={
            "select": "status_description,count(*) as bay_count,max(status_timestamp) as newest_timestamp",
            "where": where,
            "group_by": "status_description",
            "limit": 100,
        },
    )
    catalog = metadata.get("metas", {}).get("default", {})
    catalog_rows = int(catalog.get("records_count") or 0)

    recognized: list[tuple[datetime, str, int]] = []
    trusted: list[tuple[datetime, str, int]] = []
    for row in payload.get("results", []):
        state = row.get("status_description")
        timestamp = _parse_timestamp(row.get("newest_timestamp"))
        try:
            count = int(row.get("bay_count", 0))
        except (TypeError, ValueError):
            count = 0
        if state not in {"Present", "Unoccupied"} or timestamp is None or count <= 0:
            continue
        recognized.append((timestamp, state, count))
        if cutoff <= timestamp <= future_limit:
            trusted.append((timestamp, state, count))

    trusted_rows = sum(item[2] for item in trusted)
    if trusted_rows:
        classification = "verified_live_occupancy"
    elif recognized and max(item[0] for item in recognized) < cutoff:
        classification = "stale_or_historical"
    else:
        classification = "ambiguous_or_unverified"

    newest_observed = max(recognized, default=None, key=lambda item: item[0])
    newest_trusted = max(trusted, default=None, key=lambda item: item[0])
    counts = {"Present": 0, "Unoccupied": 0}
    for _, state, count in trusted:
        counts[state] += count

    return {
        "classification": classification,
        "source": "City of Melbourne",
        "scope": "City of Melbourne municipality",
        "catalogRows": catalog_rows,
        "trustedRows": trusted_rows,
        "rejectedRows": max(0, catalog_rows - trusted_rows),
        "present": counts["Present"],
        "unoccupied": counts["Unoccupied"],
        "newestObservedTimestamp": newest_observed[0].isoformat() if newest_observed else None,
        "newestTrustedTimestamp": newest_trusted[0].isoformat() if newest_trusted else None,
        "bbox": catalog.get("bbox"),
    }


def _probe_datavic_resource(
    resource_id: str,
    *,
    timestamp_field: str,
    occupancy_field: str,
    occupied_values: set[str],
    vacant_values: set[str],
    timeout: int,
) -> dict[str, Any]:
    payload = _request_json(
        "https://discover.data.vic.gov.au/api/3/action/datastore_search",
        timeout=timeout,
        query={"resource_id": resource_id, "limit": 100},
    )["result"]
    result = classify_occupancy_records(
        payload.get("records", []),
        timestamp_field=timestamp_field,
        occupancy_field=occupancy_field,
        occupied_values=occupied_values,
        vacant_values=vacant_values,
    )
    result["catalogRows"] = payload.get("total")
    return result


def probe_geelong(timeout: int) -> dict[str, Any]:
    catalog = _request_json(
        "https://www.geelongdataexchange.com.au/api/v2/catalog/datasets",
        timeout=timeout,
        query={"limit": 100},
    )
    dataset_ids = [item.get("datasetid", "") for item in catalog.get("datasets", [])]
    status = _probe_datavic_resource(
        "7f381a3a-fd9e-477f-a6ae-b45e1a65bb16",
        timestamp_field="metadata_time",
        occupancy_field="payload_fields_park_flag",
        occupied_values={"1"},
        vacant_values={"0"},
        timeout=timeout,
    )
    occupancy = _probe_datavic_resource(
        "027f8bb4-3f90-4f8b-8c91-357c58c13ab9",
        timestamp_field="updatetime",
        occupancy_field="occupied",
        occupied_values={str(value) for value in range(1, 10001)},
        vacant_values={"0"},
        timeout=timeout,
    )
    return {
        "classification": "stale_or_historical"
        if status["classification"] == occupancy["classification"] == "stale_or_historical"
        else "ambiguous_or_unverified",
        "source": "City of Greater Geelong",
        "currentCatalogDatasetCount": len(dataset_ids),
        "currentCatalogParkingDatasetIds": [item for item in dataset_ids if "parking" in item.lower()],
        "cachedSpaceStatus": status,
        "cachedLotOccupancy": occupancy,
    }


def _arcgis_count(url: str, timeout: int) -> int:
    return int(
        _request_json(
            f"{url}/query",
            timeout=timeout,
            query={"where": "1=1", "returnCountOnly": "true", "f": "json"},
        )["count"]
    )


def summarize_maribyrnong(
    counts: dict[str, int],
    historical_payload: dict[str, Any] | None = None,
    *,
    historical_error: str | None = None,
) -> dict[str, Any]:
    if historical_payload is not None:
        historical_map = {
            "status": "available",
            "layerNames": [item.get("Name") for item in historical_payload.get("Layers", [])],
        }
    else:
        historical_map = {"status": "unavailable", "error": historical_error}
    return {
        "classification": "static_locations_or_restrictions",
        "source": "City of Maribyrnong",
        "parkingExplorerCounts": counts,
        "historicalMap": historical_map,
        "occupancy": "not exposed by these anonymous endpoints",
    }


def probe_maribyrnong(timeout: int) -> dict[str, Any]:
    root = "https://services2.arcgis.com/PovBcp8J7VQYyDEI/arcgis/rest/services"
    services = {
        "regularBays": f"{root}/Reg_Parking_Bay_GreenZone_Ply/FeatureServer/0",
        "accessibleBays": f"{root}/Reg_Parking_Bay_BlueZone_Ply/FeatureServer/0",
        "permitOrLoadingBays": f"{root}/Reg_Parking_Bay_RedZone_Ply/FeatureServer/0",
        "parklets": f"{root}/Reg_Parking_Parklets_Ply/FeatureServer/0",
    }
    counts = {name: _arcgis_count(url, timeout) for name, url in services.items()}
    try:
        historical = _request_json(
            "https://www.maribyrnong.vic.gov.au/ocmaps/get/c935ddf0-fe8c-4c98-be58-95cb0f66eb56",
            timeout=timeout,
        )
        return summarize_maribyrnong(counts, historical)
    except Exception as error:
        return summarize_maribyrnong(counts, historical_error=f"{type(error).__name__}: {error}")


def probe_ballarat(timeout: int) -> dict[str, Any]:
    base = "https://data.ballarat.vic.gov.au/api/explore/v2.1/catalog/datasets"
    zones = _request_json(f"{base}/realtime0/records", timeout=timeout, query={"limit": 1})
    meters = _request_json(f"{base}/realtime1/records", timeout=timeout, query={"limit": 1})
    transactions = _request_json(
        f"{base}/parking-transactions/records",
        timeout=timeout,
        query={"limit": 1, "order_by": "date DESC"},
    )
    newest_transaction = (transactions.get("results") or [{}])[0].get("date")
    return {
        "classification": "static_locations_or_restrictions",
        "source": "City of Ballarat",
        "parkingZoneRecords": zones.get("total_count"),
        "parkingMeterRecords": meters.get("total_count"),
        "transactionRows": transactions.get("total_count"),
        "newestTransactionDate": newest_transaction,
        "occupancy": "transactions are monthly usage history, not vacant bays",
    }


def probe_casey(timeout: int) -> dict[str, Any]:
    base = "https://data.casey.vic.gov.au/api/explore/v2.1/catalog/datasets"
    restrictions = _request_json(
        f"{base}/city-of-casey-parking-zones/records", timeout=timeout, query={"limit": 1}
    )
    station_parks = _request_json(
        f"{base}/railway-station-carparks-ptv/records", timeout=timeout, query={"limit": 1}
    )
    return {
        "classification": "static_locations_or_restrictions",
        "source": "City of Casey / PTV snapshot",
        "parkingRestrictionRecords": restrictions.get("total_count"),
        "stationCarParkPolygons": station_parks.get("total_count"),
        "occupancy": "not present",
    }


def probe_osm(timeout: int) -> dict[str, Any]:
    query = (
        '[out:json][timeout:90];area["boundary"="administrative"]'
        '["ISO3166-2"="AU-VIC"]->.a;nwr["amenity"="parking"](area.a);out count;'
    )
    payload = _request_json(
        "https://overpass-api.de/api/interpreter",
        timeout=max(timeout, 100),
        body=urllib.parse.urlencode({"data": query}),
    )
    tags = (payload.get("elements") or [{}])[0].get("tags", {})
    return {
        "classification": "static_locations_or_restrictions",
        "source": "OpenStreetMap Overpass",
        "parkingFeatures": int(tags.get("total", 0)),
        "osmBaseTimestamp": payload.get("osm3s", {}).get("timestamp_osm_base"),
        "occupancy": "not part of the parking feature model",
    }


PROBES = {
    "melbourne": probe_melbourne,
    "geelong": probe_geelong,
    "maribyrnong": probe_maribyrnong,
    "ballarat": probe_ballarat,
    "casey": probe_casey,
    "osm": probe_osm,
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", choices=["all", *PROBES], default="all")
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args()

    names = list(PROBES) if args.source == "all" else [args.source]
    output: dict[str, Any] = {
        "checkedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "sources": {},
    }
    for name in names:
        try:
            output["sources"][name] = PROBES[name](args.timeout)
        except Exception as error:  # A failed source must never be interpreted as available.
            output["sources"][name] = {
                "classification": "unavailable_or_error",
                "error": f"{type(error).__name__}: {error}",
            }
    print(json.dumps(output, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
