# ParkAlong

ParkAlong is an iOS-only SwiftUI unified parking finder for central Melbourne. It puts live on-street availability, exact location, active time limit, current price or provider link, and sensible off-street options on one map. Live City of Melbourne bay sensors remain primary; bundled 2019 history is secondary arrival guidance and an explicitly labelled fallback when live data cannot be trusted.

There are no accounts, payments, reservations, backend, database, Google Maps, or runtime AI calls. Availability is never a guarantee—street signs govern.

## Run

Requirements: Xcode 26.x (the app targets iOS 17+), an iPhone simulator, Python 3, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
xcodebuild build \
  -project ParkingAvailability.xcodeproj \
  -scheme ParkingAvailability \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  CODE_SIGNING_ALLOWED=NO
```

Open `ParkingAvailability.xcodeproj` to run interactively. Simulator builds do not require a paid Apple Developer account. To set a Melbourne simulator location:

```bash
xcrun simctl location booted set -37.8136,144.9631
```

## Tests

Deterministic unit and UI tests never depend on the network:

```bash
xcodebuild test \
  -project ParkingAvailability.xcodeproj \
  -scheme ParkingAvailability \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  CODE_SIGNING_ALLOWED=NO

python3 -m unittest discover -s Scripts/tests -v
```

The separate live contract check queries the real sensor feed around Melbourne CBD, applies the 24-hour cutoff, and reports latency/counts:

```bash
python3 Scripts/smoke_live_api.py
```

UI tests launch with `-ui-testing` plus deterministic `-fixture-live`, `-fixture-loading`, or `-fixture-error` arguments. `-location-denied` proves the CBD fallback and `-intercept-navigation` verifies the Apple Maps handoff without leaving the test app. These fixtures are never selected by the normal app launch.

## Architecture

- `ParkingAPIClient`: Opendatasoft request construction, spatial filters, explicit pagination, response validation, and decoding.
- `ParkingRepository`: metadata/history joins, short-lived cache, refresh lifecycle, legal filtering, and live-to-typical fallback.
- `AvailabilityEngine`: recognised statuses, 24-hour trust cutoff, and zone counts.
- `RestrictionEngine`: Melbourne-local day/time resolution, midnight-spanning periods, supported public-parking codes, paid/free labels, and stay eligibility.
- `PredictionEngine`: live-heavy arrival blending, clamping, conservative confidence, and plain-language ranges.
- `RankingEngine`: deterministic 70% availability, 20% walking distance, 10% confidence/freshness ordering.
- `ParkingOption`: normalized on-street/off-street availability, location, restriction, price/provider, timestamp, and deep-link model.
- `LocationService`, `DestinationSearchService`, `OffStreetParkingService`, and `AppleMapsNavigator`: narrow wrappers around Core Location and MapKit.
- `ParkingMapViewModel`: UI orchestration only.
- `Scripts/`: reproducible stable-metadata, historical aggregation, and live smoke tools.

The UI is a native MapKit map with numbered on-street availability pins, provider-backed off-street results, individual vacant bays for only the selected zone, a Best bet affordance, destination search, stay-duration control, a unified result sheet, manual/foreground/two-minute refresh, and an About surface.

## Rebuild bundled data

Stable current metadata and restrictions are small API downloads:

```bash
python3 Scripts/generate_metadata.py
```

The historical generator streams the 2019 ZIP directly and does not load 42.7 million rows into memory. Raw archives and CSVs under `Scripts/data/` are gitignored.

```bash
mkdir -p Scripts/data
curl -fL \
  'https://opendatasoft-s3.s3.amazonaws.com/downloads/archive/7pgd-bdf2.zip' \
  -o Scripts/data/2019-parking-events.zip

python3 Scripts/generate_prediction.py \
  Scripts/data/2019-parking-events.zip \
  ParkingAvailability/Resources/Generated/historical_availability.json \
  --metadata ParkingAvailability/Resources/Generated/zone_metadata.json
```

Aggregation is by normalized street/between-street segment, Melbourne weekday, and 15-minute interval. Current bay IDs are used when they overlap the historic IDs; otherwise the normalized segment is the join key. The output contains occupied ratio, turnover, and sample strength. The raw ZIP is about 717 MB and expands to about 7.45 GB, but extraction is not required.

## Demo walkthrough

1. Launch directly onto Melbourne CBD; optionally tap the location arrow to request When-In-Use access.
2. Search for a destination or keep the CBD default.
3. Choose 15m, 1h, 2h, or 3h+. Unsuitable restrictions disappear rather than appearing disabled.
4. Compare green (3+), amber (1–2), and red (0) pins. Availability, not proximity, drives Best bet.
5. Open Best bet or a pin. Availability, location, active time limit, and current price/provider action are immediately scannable; arrival confidence, walk, freshness, and vacant-bay dots are secondary.
6. Tap Navigate to hand the selected coordinate to Apple Maps.

## Data, attribution, and caveats

Data © City of Melbourne, licensed under [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/):

- [On-street parking bay sensors](https://data.melbourne.vic.gov.au/explore/dataset/on-street-parking-bay-sensors/)
- [Sign plates in each parking zone](https://data.melbourne.vic.gov.au/explore/dataset/sign-plates-located-in-each-parking-zone/)
- [Parking zones linked to street segments](https://data.melbourne.vic.gov.au/explore/dataset/parking-zones-linked-to-street-segments/)
- [2019 parking events archive](https://opendatasoft-s3.s3.amazonaws.com/downloads/archive/7pgd-bdf2.zip)

Sensor rows older than 24 hours, missing a zone/location, or reporting an unknown state are excluded. Under-counting is intentional. City guidance warns that sensors are not operational on public holidays and construction can make a bay appear vacant; the app therefore labels broad staleness as Typical availability and repeats that street signs govern. Where no reusable current tariff is available, ParkAlong shows the provider and a price/payment deep link instead of inventing a dollar amount.

Location remains on device. Network traffic is limited to normal City data and Apple MapKit/Maps requests. Denying location keeps destination search and the Melbourne CBD default fully usable.
