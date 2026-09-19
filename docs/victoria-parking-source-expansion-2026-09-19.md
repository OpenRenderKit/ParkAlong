# Victorian parking source expansion checkpoint

Checked on **19 September 2026 (Australia/Melbourne)** against the anonymous publisher endpoints and pages, not only catalogue descriptions.

## Decision method

Candidates were scored from 0 to 5 on user value, Victorian coverage, data freshness, reuse clarity, and expected maintenance reliability. A source also had to preserve ParkAlong's trust boundary: geometry, restrictions, prices, transactions, and occupancy are different evidence types. Only a fresh timestamped occupied/vacant observation may be labelled live.

| Candidate | Value | Coverage | Freshness | Licence | Maintenance | Total | Decision |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| [Vicmap Features of Interest](https://www.arcgis.com/home/item.html?id=57b2690423b14af89ae67c6c47606e9f), `parking area` subtype | 4 | 4 | 5 | 5 | 5 | 23 | **Shipped** as current statewide static authority geometry |
| [Mildura disabled carparks](https://data.gov.au/data/dataset/mildura-rural-city-council-disabled-carparks) | 5 | 3 | 3 | 5 | 4 | 20 | **Shipped** as accessible static bays; restricted staff, permit, club-patron and no-stopping rows excluded |
| [Swan Hill disabled parking](https://data.gov.au/data/dataset/swan-hill-rural-city-council-disabled-parking) | 5 | 2 | 4 | 5 | 4 | 20 | **Shipped** as accessible static bays |
| Brimbank disabled carparks | 4 | 3 | 1 | 5 | 3 | 16 | Hold: reusable, but the resource itself dates to 2019; refresh or field validation is needed |
| Port Phillip accessible parking | 4 | 3 | 2 | 5 | 3 | 17 | Hold: reusable 2022 snapshot, but not current enough to displace stronger mapped evidence without validation |
| Southern Grampians disabled parking | 3 | 2 | 0 | 5 | 3 | 13 | Hold: published resource is from 2016 |
| Brimbank car-park management ArcGIS layers | 4 | 4 | 4 | 0 | 3 | 15 | Blocked: public endpoint found, but item metadata does not provide clear reuse terms |
| Commercial operator occupancy and tariff APIs | 5 | 4 | 5 | 0 | 2 | 16 | Blocked: credentials, agreement, or commercial terms required |
| Geelong cached sensor/lot feeds | 4 | 2 | 0 | 2 | 1 | 9 | Rejected for live use: latest observed events remain historical |
| [Geelong parking ticket machines](https://data.gov.au/data/dataset/c3449764-6703-4d3a-ad5c-459552c2494b) | 4 | 2 | 0 | 5 | 1 | 12 | Hold: clear CC BY 3.0 fields for time limit, rate, days, and hours, but the actual GeoJSON/SHP resource is dated 2014 and CSV is dated 2015; 2026 catalogue metadata churn is not evidence that the parking rules are current |
| OSM charging stations as parking | 3 | 4 | 4 | 5 | 4 | 20 | Research only: a charger does not prove public parking access, capacity, stay legality, or current availability |
| Road closures, event calendars, and transactions | 3 | 3 | 3 | 2 | 2 | 13 | Context only until a source can be joined to exact parking records with effective times; never vacancy |

Scores guide sequencing rather than overriding a hard trust or licensing failure.

## Implemented sources

### Vicmap Features of Interest

- The state-managed feature service was updated on 13 September 2026 and returned **464** features whose exact subtype is `parking area`.
- The ArcGIS item publishes Vicmap under **Creative Commons Attribution 4.0**.
- Records use the authoritative feature UFI as their stable identity and retain name, parent name, dataset time, check time, source URL, and licence.
- The source contains no parking occupancy, capacity, access entitlement, detailed restriction, or tariff fields. Every result is therefore `static_only`, with availability unknown.

### Mildura accessible parking

- The official Data.gov.au GeoJSON returned **389** rows. ParkAlong retains **368** public disabled-only rows.
- Rows explicitly scoped to staff, permit holders, club patrons/members, workers, or no-stopping conditions are excluded rather than shown as general suggestions.
- The retained rows preserve exact geometry, capacity, street/off-street kind, published maximum stay, zero hourly fee where supplied, record freshness, council attribution, and **CC BY 3.0 Australia** terms.
- The `Sensor` field is descriptive metadata. It contains no occupied/vacant event or event time and is never treated as availability.

### Swan Hill accessible parking

- The official council CSV returned and retained **45** geocoded accessible spaces across Swan Hill and Robinvale.
- The publisher page reports an update on 21 November 2025 and **CC BY 3.0 Australia**.
- Rows contain location only. They are `static_only`; posted signs remain authoritative.

## Precedence and deduplication

The generator retains stable source IDs and rejects invalid coordinates. At runtime, accepted authority, council, and approved attributed records sort ahead of OpenStreetMap; an OSM result within 75 metres of an accepted official result is suppressed. The three new sources therefore improve provenance without multiplying nearby pins. They do not override a more precise live City of Melbourne sensor observation because the live and static repositories retain different evidence classifications.

## Measured bundle result

| Measure | Before | After | Change |
| --- | ---: | ---: | ---: |
| Records | 34,023 | 35,004 | +981 |
| Generated JSON bytes | 22,546,415 | 23,344,113 | +797,698 (+3.54%) |
| Manifested source groups | 13 | 16 | +3 |
| Distinct source IDs | 23 | 26 | +3 |
| Municipality labels | 22 | 23 | +1 (Mildura) |
| Records with known accessible capacity | 970 | 1,389 | +419 |

The net record change includes normal movement in the live-fetched static inputs: the three new adapters contribute 877 retained records, while existing council and OpenStreetMap sources account for the remaining 104-record change. The app still makes no new runtime request: the catalogue is generated by a developer and bundled as the offline baseline.

The manifest now includes the record count, municipality count, distinct source count, accessible-record count, per-generator-source counts, complete source attribution metadata, output bytes, and SHA-256. The rebuilt catalogue hash is `918be7f3c6e15a4565a2eb2ce3293707c9c4bb41ef9b13f42c787e065bddf272`.

The separate [fresh 87-area spatial audit](victoria-parking-geographic-coverage-2026-09-19.md) prevents the larger statewide total from hiding geographic and evidence-quality gaps. It finds that all 79 councils have at least an OSM point, but only 41 have any non-OSM catalogue record and 38 remain discovery-only. The raw `municipality` field is `Victoria` for 29,385 records, so source labels must not be used as a proxy for geographic coverage.

## Reliability and verification

- The generator and probe now try two anonymous Overpass endpoints in a fixed order. A source still fails closed if both endpoints fail; the fallback does not reuse a stale cached response.
- Adapter tests cover identity, coordinate order, accessibility, restrictions/tariffs, dataset time, licensing, and `static_only` classification.
- Probe tests ensure that static sensor-related metadata cannot become live occupancy.
- The full generated JSON contains 35,004 unique IDs and 26 source IDs, and its count and hash match the manifest.

## Remaining opportunities

1. Revalidate Brimbank and Port Phillip accessible snapshots against current council maps before shipping them.
2. Obtain explicit reuse terms for otherwise useful official ArcGIS layers whose public accessibility alone does not establish a licence.
3. Add EV charging only when charging geometry can be joined to legal public parking access and stay rules; a charger pin alone is insufficient.
4. Treat parking transactions, road closures, venue events, and holiday calendars as time-bounded demand or restriction context, never occupied/vacant observations.
5. Pursue EasyPark, CellOPark, Wilson, Secure Parking, Parkopedia, Chargefox, and similar operator data only through documented commercial agreements. Do not scrape consumer apps or copy session-bound endpoints.
6. Continue to require anonymous fresh event timestamps before any second Victorian area is described as live. City of Melbourne remains the only verified source meeting that bar.
7. Ask Greater Geelong for a refreshed ticket-machine export before importing the otherwise well-structured CC BY 3.0 dataset. Its catalogue page changed in 2026, but the underlying published resources remain dated 2014 and 2015.
