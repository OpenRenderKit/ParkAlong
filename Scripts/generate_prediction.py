#!/usr/bin/env python3
"""Stream the City of Melbourne 2019 parking-event archive into compact buckets."""

from __future__ import annotations

import argparse
import csv
import io
import json
import math
import re
import zipfile
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path


STREET_SUFFIXES = {
    "street": "st", "st": "st", "road": "rd", "rd": "rd", "avenue": "ave", "ave": "ave",
    "lane": "ln", "ln": "ln", "place": "pl", "pl": "pl", "parade": "pde", "pde": "pde",
    "boulevard": "blvd", "drive": "dr", "terrace": "tce"
}
DATE_FORMATS = (
    "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%d/%m/%Y %H:%M:%S",
    "%m/%d/%Y %H:%M:%S", "%d/%m/%Y %I:%M:%S %p", "%m/%d/%Y %I:%M:%S %p"
)


def canonical_street(value: str) -> str:
    tokens = re.findall(r"[a-z0-9]+", (value or "").lower())
    if tokens and tokens[-1] in STREET_SUFFIXES:
        tokens[-1] = STREET_SUFFIXES[tokens[-1]]
    return "".join(tokens)


def normalize_segment(street: str, between_one: str, between_two: str) -> str:
    cross_streets = sorted((canonical_street(between_one), canonical_street(between_two)))
    return "|".join((canonical_street(street), *cross_streets))


def parse_time(value: str) -> datetime | None:
    cleaned = (value or "").strip()
    try:
        if len(cleaned) >= 22 and cleaned[2] == "/" and cleaned[5] == "/":
            hour = int(cleaned[11:13])
            meridiem = cleaned[20:22].upper()
            if meridiem == "PM" and hour != 12:
                hour += 12
            elif meridiem == "AM" and hour == 12:
                hour = 0
            return datetime(int(cleaned[6:10]), int(cleaned[0:2]), int(cleaned[3:5]), hour, int(cleaned[14:16]), int(cleaned[17:19]))
        if len(cleaned) >= 19 and cleaned[4] == "-" and cleaned[7] == "-":
            return datetime.fromisoformat(cleaned[:19])
    except (ValueError, IndexError):
        return None
    for date_format in DATE_FORMATS:
        try:
            return datetime.strptime(cleaned, date_format)
        except ValueError:
            pass
    return None


def swift_weekday(value: datetime) -> int:
    return ((value.weekday() + 1) % 7) + 1


def load_bay_mapping(metadata_path: Path | None) -> dict[str, str]:
    if metadata_path is None:
        return {}
    records = json.loads(metadata_path.read_text())
    mapping: dict[str, str] = {}
    for record in records:
        for sensor_id in record.get("sensorIDs", []):
            mapping[str(sensor_id)] = record["segmentKey"]
    return mapping


def _aggregate_archive(
    archive_path: Path,
    metadata_path: Path | None = None,
    max_rows: int | None = None,
    holdout_start: datetime = datetime(2019, 11, 1),
    evaluation_start: datetime = datetime(2019, 12, 1),
) -> tuple[list[dict], dict, list[dict]]:
    if evaluation_start <= holdout_start:
        raise ValueError("evaluation_start must be later than holdout_start")

    def data_split(value: datetime) -> str:
        if value < holdout_start:
            return "train"
        if value < evaluation_start:
            return "calibration"
        return "evaluation"

    bay_mapping = load_bay_mapping(metadata_path)
    occupied_minutes: dict[tuple[str, int, int], float] = defaultdict(float)
    arrivals: dict[tuple[str, int, int], int] = defaultdict(int)
    bays: dict[str, set[str]] = defaultdict(set)
    observed_dates: dict[tuple[str, int], set[str]] = defaultdict(set)
    observed_bay_dates: dict[tuple[str, str, int], set[str]] = defaultdict(set)
    split_occupied_minutes: dict[tuple[str, str, int, int], float] = defaultdict(float)
    split_observed_bay_dates: dict[tuple[str, str, str, int], set[str]] = defaultdict(set)
    split_observed_dates: dict[tuple[str, str], set[str]] = defaultdict(set)
    rows_read = 0
    mapped_bays = 0

    with zipfile.ZipFile(archive_path) as archive:
        csv_names = [name for name in archive.namelist() if name.lower().endswith(".csv")]
        if not csv_names:
            raise ValueError("Archive contains no CSV file")
        with archive.open(csv_names[0]) as compressed, io.TextIOWrapper(compressed, encoding="utf-8-sig", errors="replace", newline="") as text:
            reader = csv.DictReader(text)
            for row in reader:
                rows_read += 1
                if max_rows is not None and rows_read > max_rows:
                    break
                bay_id = (row.get("BayId") or "").strip()
                street_key = normalize_segment(row.get("StreetName", ""), row.get("BetweenStreet1", ""), row.get("BetweenStreet2", ""))
                segment = bay_mapping.get(bay_id, street_key)
                if bay_id in bay_mapping:
                    mapped_bays += 1
                if not bay_id or segment.startswith("||"):
                    continue
                arrival = parse_time(row.get("ArrivalTime", ""))
                departure = parse_time(row.get("DepartureTime", ""))
                if arrival is None:
                    continue

                weekday = swift_weekday(arrival)
                arrival_split = data_split(arrival)
                bays[segment].add(bay_id)
                observed_dates[(segment, weekday)].add(arrival.date().isoformat())
                observed_bay_dates[(segment, bay_id, weekday)].add(arrival.date().isoformat())
                split_observed_dates[(arrival_split, segment)].add(arrival.date().isoformat())
                split_observed_bay_dates[(arrival_split, segment, bay_id, weekday)].add(arrival.date().isoformat())
                if departure is None or departure <= arrival:
                    continue
                if departure - arrival > timedelta(days=1):
                    departure = arrival + timedelta(days=1)

                arrival_key = (segment, weekday, (arrival.hour * 60 + arrival.minute) // 15)
                arrivals[arrival_key] += 1
                cursor = arrival
                while cursor < departure:
                    bucket_start = cursor.replace(minute=(cursor.minute // 15) * 15, second=0, microsecond=0)
                    bucket_end = bucket_start + timedelta(minutes=15)
                    overlap_end = min(bucket_end, departure)
                    key = (segment, swift_weekday(cursor), (cursor.hour * 60 + cursor.minute) // 15)
                    occupied_minutes[key] += max(0, (overlap_end - cursor).total_seconds() / 60)
                    split = data_split(cursor)
                    split_occupied_minutes[(split, *key)] += max(0, (overlap_end - cursor).total_seconds() / 60)
                    observed_dates[(segment, key[1])].add(cursor.date().isoformat())
                    split_observed_dates[(split, segment)].add(cursor.date().isoformat())
                    split_observed_bay_dates[(split, segment, bay_id, key[1])].add(cursor.date().isoformat())
                    cursor = overlap_end

    keys = sorted(
        (segment, weekday, interval)
        for segment, weekday in observed_dates
        for interval in range(96)
    )
    records: list[dict] = []
    state_counts: dict[str, int] = defaultdict(int)
    for segment, weekday, interval in keys:
        sample_count = sum(len(observed_bay_dates[(segment, bay_id, weekday)]) for bay_id in bays[segment])
        if sample_count == 0:
            continue
        denominator_minutes = sample_count * 15
        ratio = min(1.0, max(0.0, occupied_minutes[(segment, weekday, interval)] / denominator_minutes))
        turnover = arrivals[(segment, weekday, interval)] / sample_count
        state = "observed_occupied" if occupied_minutes[(segment, weekday, interval)] > 0 else "inferred_vacant"
        state_counts[state] += 1
        records.append({
            "segmentKey": segment,
            "weekday": weekday,
            "interval": interval,
            "occupiedRatio": round(ratio, 4),
            "turnover": round(turnover, 4),
            "sampleCount": sample_count,
            "observationState": state,
            "observedThrough": f"{max(observed_dates[(segment, weekday)])}T23:59:59Z",
        })

    validations: list[dict] = []
    for segment in sorted(bays):
        calibration_errors: list[float] = []
        for weekday in range(1, 8):
            train_count = sum(len(split_observed_bay_dates[("train", segment, bay_id, weekday)]) for bay_id in bays[segment])
            calibration_count = sum(len(split_observed_bay_dates[("calibration", segment, bay_id, weekday)]) for bay_id in bays[segment])
            if train_count == 0 or calibration_count == 0:
                continue
            for interval in range(96):
                train_ratio = min(1.0, max(0.0, split_occupied_minutes[("train", segment, weekday, interval)] / (train_count * 15)))
                calibration_ratio = min(1.0, max(0.0, split_occupied_minutes[("calibration", segment, weekday, interval)] / (calibration_count * 15)))
                calibration_errors.append(abs(calibration_ratio - train_ratio))

        if not calibration_errors:
            continue
        calibration_errors.sort()
        conformal_index = min(
            len(calibration_errors) - 1,
            max(0, math.ceil((len(calibration_errors) + 1) * 0.9) - 1),
        )
        interval_radius = calibration_errors[conformal_index]

        absolute_error_sum = 0.0
        brier_sum = 0.0
        covered_samples = 0
        validation_samples = 0
        for weekday in range(1, 8):
            train_count = sum(len(split_observed_bay_dates[("train", segment, bay_id, weekday)]) for bay_id in bays[segment])
            evaluation_count = sum(len(split_observed_bay_dates[("evaluation", segment, bay_id, weekday)]) for bay_id in bays[segment])
            if train_count == 0 or evaluation_count == 0:
                continue
            for interval in range(96):
                train_ratio = min(1.0, max(0.0, split_occupied_minutes[("train", segment, weekday, interval)] / (train_count * 15)))
                evaluation_ratio = min(1.0, max(0.0, split_occupied_minutes[("evaluation", segment, weekday, interval)] / (evaluation_count * 15)))
                absolute_error_sum += abs(evaluation_ratio - train_ratio) * evaluation_count
                brier_sum += (
                    train_ratio * train_ratio * (1 - evaluation_ratio)
                    + (1 - train_ratio) * (1 - train_ratio) * evaluation_ratio
                ) * evaluation_count
                validation_samples += evaluation_count
                lower = max(0.0, train_ratio - interval_radius)
                upper = min(1.0, train_ratio + interval_radius)
                if lower <= evaluation_ratio <= upper:
                    covered_samples += evaluation_count
        observed = split_observed_dates[("evaluation", segment)]
        if validation_samples == 0 or not observed:
            continue
        validations.append({
            "segmentKey": segment,
            "sampleCount": validation_samples,
            "normalizedMAE": round(absolute_error_sum / validation_samples, 4),
            "brierScore": round(brier_sum / validation_samples, 4),
            "intervalCoverage": round(covered_samples / validation_samples, 4),
            "intervalRadius": round(interval_radius, 4),
            "observedThrough": f"{max(observed)}T23:59:59Z",
            "modelVersion": "melbourne-events-v3-2019-conformal",
        })

    stats = {
        "rowsRead": rows_read,
        "bucketCount": len(records),
        "segmentCount": len(bays),
        "mappedBayRows": mapped_bays,
        "observationStateCounts": dict(sorted(state_counts.items())),
        "validationCount": len(validations),
        "calibrationStart": holdout_start.isoformat(),
        "evaluationStart": evaluation_start.isoformat(),
    }
    return records, stats, validations


def aggregate_archive(
    archive_path: Path,
    metadata_path: Path | None = None,
    max_rows: int | None = None,
) -> tuple[list[dict], dict]:
    records, stats, _ = _aggregate_archive(archive_path, metadata_path, max_rows)
    return records, stats


def aggregate_archive_with_validation(
    archive_path: Path,
    metadata_path: Path | None = None,
    max_rows: int | None = None,
    holdout_start: datetime = datetime(2019, 11, 1),
    evaluation_start: datetime = datetime(2019, 12, 1),
) -> tuple[list[dict], dict, list[dict]]:
    return _aggregate_archive(archive_path, metadata_path, max_rows, holdout_start, evaluation_start)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--metadata", type=Path)
    parser.add_argument("--max-rows", type=int)
    parser.add_argument("--validation-output", type=Path)
    parser.add_argument("--holdout-start", type=datetime.fromisoformat, default=datetime(2019, 11, 1))
    parser.add_argument("--evaluation-start", type=datetime.fromisoformat, default=datetime(2019, 12, 1))
    args = parser.parse_args()
    records, stats, validations = aggregate_archive_with_validation(
        args.archive, args.metadata, args.max_rows, args.holdout_start, args.evaluation_start
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(records, separators=(",", ":")))
    if args.validation_output:
        args.validation_output.parent.mkdir(parents=True, exist_ok=True)
        args.validation_output.write_text(json.dumps(validations, separators=(",", ":")))
        stats["validationOutputBytes"] = args.validation_output.stat().st_size
    stats["outputBytes"] = args.output.stat().st_size
    print(json.dumps(stats, sort_keys=True))


if __name__ == "__main__":
    main()
