# Victorian parking source expansion checkpoint

Checked on **19 September 2026 (Australia/Melbourne)** against the anonymous publisher endpoints and pages, not only catalogue descriptions.

## Decision method

Candidates were scored from 0 to 5 on user value, Victorian coverage, data freshness, reuse clarity, and expected maintenance reliability. A source also had to preserve ParkAlong's trust boundary: geometry, restrictions, prices, transactions, and occupancy are different evidence types. Only a fresh timestamped occupied/vacant observation may be labelled live.

| Candidate | Value | Coverage | Freshness | Licence | Maintenance | Total | Decision |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| [Vicmap Features of Interest](https://www.arcgis.com/home/item.html?id=57b2690423b14af89ae67c6c47606e9f), `parking area` subtype | 4 | 4 | 5 | 5 | 5 | 23 | **Shipped** as current statewide static authority geometry |
| [Mildura disabled carparks](https://data.gov.au/data/dataset/mildura-rural-city-council-disabled-carparks) | 5 | 3 | 3 | 5 | 4 | 20 | **Shipped** as accessible static bays; restricted staff, permit, club-patron and no-stopping rows excluded |
| [Swan Hill disabled parking](https://data.gov.au/data/dataset/swan-hill-rural-city-council-disabled-parking) | 5 | 2 | 4 | 5 | 4 | 20 | **Shipped** as accessible static bays |
| [City of Port Phillip accessible parking](https://data.gov.au/data/dataset/city-of-port-phillip-accessible-parking) | 4 | 3 | 2 | 5 | 3 | 17 | **Shipped** as static_only accessible locations; 2022 snapshot retained under the partial-truth policy and visibly non-live |
| [Glen Eira accessible parking](https://data.gov.au/data/dataset/accessible-parking) | 4 | 3 | 2 | 5 | 3 | 17 | **Shipped** as static_only accessible bays; 2022 snapshot retained under the partial-truth policy and visibly non-live |
| [Brimbank car parks](https://data.gov.au/data/dataset/brimbank-carparks) and [Brimbank disabled car parks](https://data.gov.au/data/dataset/brimbank-disabled-car-parks) | 4 | 3 | 1 | 5 | 3 | 16 | **Shipped** as static_only from the 2019-dated resource; restrictions with exclusion semantics withheld/filtered conservatively |
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

### Port Phillip accessible parking

- The official Data.gov.au GeoJSON was live-verified with **402 Point features**.
- The only stable identity field observed is `Table_Row_ID`; no capacity, restriction, tariff, or event field is present.
- The publisher licence is **CC BY 2.5 Australia**, with underlying Last-Modified **2022-08-11T05:43:28Z**.
- ParkAlong imports all 402 features as `static_only` with kind `unknown` and both total capacity and accessible count unknown. The record name carries only accessible-location meaning (`Accessible parking location`).
- Current council accessibility pages and maps corroborate the ongoing accessible-parking category and use, but not every 2022 point. The dated geometry is retained under the product partial-truth policy and is visibly non-live.

### Glen Eira accessible parking

- The official Data.gov.au JSON was live-verified with **106 Point features**.
- Stable identity uses `ID` / `ogr_fid` and the accessible count uses `Spaces`.
- The publisher licence is **CC BY 2.5 Australia**, with underlying Last-Modified **2022-08-01T04:22:41Z**.
- ParkAlong imports 105 unique locations as `static_only` with kind `unknown`. The source contains 106 features, but IDs 119 and 120 are an exact duplicate at the same coordinate with the same accessible count, so the first stable row is retained once. `accessibleSpaces` is preserved from `Spaces`; total capacity is unknown.
- Current council accessibility pages and maps corroborate the ongoing accessible-parking category and use, but not every 2022 point. The dated geometry is retained under the product partial-truth policy and is visibly non-live.
- The current 38,610-record manifest therefore retains 105 Glen Eira accessible records from 106 published features.

## Completed Victoria parking catalogue expansion

All eight source IDs added in this expansion (Port Phillip, Glen Eira, two Brimbank feeds and four Greater Dandenong facilities) are `static_only`. No new live coverage is claimed.

### Brimbank car parks and accessible bays

- The Data.gov.au WFS resources for `brimbank-carparks` and `brimbank-disabled-car-parks` carry datasetUpdatedAt **2019-03-12T00:00:00Z** and licence **CC BY 2.5 Australia**.
- ParkAlong retains **2,909** car-park records and **187** accessible records.
- Restrictions with exclusion semantics (no stopping, no parking, bus/loading/taxi/permit zones, staff/council/library-staff exceptions, drop-off zones, clearways, and disabled-only rows in the general car-park layer) were withheld/filtered conservatively rather than shown as general suggestions.
- Rows without a usable identifier, name, or coordinate were excluded without inventing values.

### Greater Dandenong council facilities

- Four official council facility pages were ingested with checkedAt only and no datasetUpdatedAt because the pages expose no resource date:
  - Number 8 Balmoral Avenue Multi-deck Car Park;
  - Thomas Street Multi-deck Car Park;
  - Walker Street Multi-deck Car Park;
  - Carroll Lane Car Park.
- Each facility carries opening-hour schedules only. Tariffs were deliberately omitted because the pages publish no fee-effective date and the tariff model requires one; Carroll Lane additionally limits free parking to public-transport users, which the tariff model cannot represent as an unconditional free tariff.
- Number 8 capacity remains unknown because the source says more than 500 and the model represents exact capacities only.

### Locality labelling

- Locality labels on 38,606 records are derived from 2,973 official Vicmap locality polygons (1,481 distinct localities; 4 outside-polygon records remain unlabeled).
- The locality boundary source, service URL, item ID, licence, and dataset time are recorded in the manifest. Locality labelling improves search and display geography but does not upgrade parking-source authority or freshness. See the [62-locality coverage audit](victoria-parking-locality-coverage-2026-09-19.md) for before/after evidence.

### Material research holds

No ingest occurred where reuse permission, exact geometry, or exact current semantics were unresolved. This includes additional Stonnington facilities, Deakin Burwood, West Tarneit, Ringwood/hospital candidates, and Glen Waverley page corrections not safely mappable to source polygons.

## Precedence and deduplication

The generator retains stable source IDs and rejects invalid coordinates. At runtime, accepted authority, council, and approved attributed records sort ahead of OpenStreetMap; an OSM result within 75 metres of an accepted official result is suppressed. The new sources therefore improve provenance without multiplying nearby pins. They do not override a more precise live City of Melbourne sensor observation because the live and static repositories retain different evidence classifications.

## Measured bundle result

| Measure | Before (35,004 baseline) | After (38,610 catalogue) | Change |
| --- | ---: | ---: | ---: |
| Records | 35,004 | 38,610 | +3,606 |
| Generated JSON bytes | 23,344,113 | 26,776,047 | +3,431,934 (+14.70%) |
| Manifested source groups | 16 | 20 | +4 |
| Distinct source IDs | 26 | 34 | +8 |
| Municipality labels | 23 | 87 | +64 via spatial join; only exact `Victoria` labels rewritten |
| Records with known accessible capacity | 1,389 | 1,681 | +292 |

The intermediate 35,511-record checkpoint reflected 402 Port Phillip features and all 106 then-unduplicated Glen Eira source rows, alongside a one-record OSM movement. The completed catalogue retains 105 unique Glen Eira locations after collapsing the exact duplicate pair, and adds 2,909 Brimbank car-park records, 187 Brimbank accessible records, and four Greater Dandenong facilities (3,100 records). Together with normal live-fetched OSM movement (including Reservoir 89 to 88), the net catalogue change from the 35,004 baseline is +3,606. The app still makes no new runtime request: the catalogue is generated by a developer and bundled as the offline baseline.

The manifest now records generatedAt 2026-09-19T03:07:47Z, sourceCount 34, accessibleRecordCount 1,681, municipalityCount 87, localityDistinctCount 1,481, localityLabeledCount 38,606, localityUnmatchedCount 4, outputBytes 26,776,047, and SHA-256 `c550ee228f28acfcb5491d0385006b4af3029010c6fa7186323feb3e8ed81617`. It also includes the record count, municipality count, distinct source count, per-generator-source counts, complete source attribution metadata, output bytes, and hash.

The separate [fresh 87-area spatial audit](victoria-parking-geographic-coverage-2026-09-19.md) prevents the larger statewide total from hiding geographic and evidence-quality gaps. It finds that all 79 councils have at least an OSM point, but only 44 have any non-OSM catalogue record and 35 remain discovery-only. The raw `municipality` field is `Victoria` for only 4 records (the 4 outside points) after the spatial join, down from 29,385. LGA relabelling improves search and display geography but does not upgrade source authority or freshness.

No source yielded fresh occupied or vacant observations. No new live coverage is claimed. City of Melbourne remains the only verified live source.

## Reliability and verification

- The generator and probe now try two anonymous Overpass endpoints in a fixed order. A source still fails closed if both endpoints fail; the fallback does not reuse a stale cached response.
- Adapter tests cover identity, coordinate order, accessibility, restrictions/tariffs, dataset time, licensing, and `static_only` classification.
- Probe tests ensure that static sensor-related metadata cannot become live occupancy.
- The full generated JSON contains 38,610 unique IDs and 34 source IDs, and its count and hash match the manifest.

## Remaining opportunities

1. Brimbank car-park and accessible snapshots are now shipped as static-only from the 2019-dated resource with conservative exclusion filtering; refresh or field validation is still needed before treating the 2019 geometry as current.
2. Obtain explicit reuse terms for otherwise useful official ArcGIS layers whose public accessibility alone does not establish a licence.
3. Add EV charging only when charging geometry can be joined to legal public parking access and stay rules; a charger pin alone is insufficient.
4. Treat parking transactions, road closures, venue events, and holiday calendars as time-bounded demand or restriction context, never occupied/vacant observations.
5. Pursue EasyPark, CellOPark, Wilson, Secure Parking, Parkopedia, Chargefox, and similar operator data only through documented commercial agreements. Do not scrape consumer apps or copy session-bound endpoints.
6. Continue to require anonymous fresh event timestamps before any second Victorian area is described as live. City of Melbourne remains the only verified source meeting that bar.
7. Ask Greater Geelong for a refreshed ticket-machine export before importing the otherwise well-structured CC BY 3.0 dataset. Its catalogue page changed in 2026, but the underlying published resources remain dated 2014 and 2015.
