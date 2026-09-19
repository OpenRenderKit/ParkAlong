# Generated parking data

These artifacts are generated from public parking data and bundled so ParkAlong can join stable metadata locally, provide a clearly labelled historical fallback, and discover parking across Victoria:

- `zone_metadata.json`
- `restrictions.json`
- `historical_availability.json`
- `victoria_static_parking.json`
- `victoria_static_manifest.json`

The Victorian catalog currently contains 38,610 records: 28,920 OpenStreetMap features suitable for general discovery after excluding explicitly private/customer/resident/permit/employee/no-access parking, plus 9,690 records derived from anonymous council/state datasets, approved attributed layers, or official parking pages. This includes 2,909 Brimbank car-park records and 187 Brimbank accessible records from the 2019-dated source resource, four Greater Dandenong facilities with schedules but no tariffs, 368 public disabled-only Mildura bays, 45 Swan Hill accessible spaces, 402 Port Phillip accessible locations, 105 Glen Eira accessible bays, and 464 Vicmap parking areas. All Brimbank and Greater Dandenong feeds are static-only. Brimbank restrictions with exclusion semantics were withheld/filtered conservatively. Greater Dandenong tariffs were omitted because the pages publish no fee-effective date. Number 8 capacity remains unknown because the source says more than 500. Locality labels on 38,606 records are derived from 2,973 official Vicmap locality polygons (1,481 distinct localities; 4 outside-polygon records remain unlabeled) and do not upgrade parking-source authority. It is deliberately static; its download timestamp must never be presented as an occupancy timestamp. Regenerate it with `python3 Scripts/generate_victoria_static_catalog.py` and use the manifest to verify exact counts, attribution, size and hash. The 2026-09-19 manifest records 38,610 records, 34 sources, 87 municipalities, outputBytes 26776047 and SHA-256 `c550ee228f28acfcb5491d0385006b4af3029010c6fa7186323feb3e8ed81617`. Do not manually edit generated artifacts or commit the raw 2019 archive.

City of Melbourne data is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). OpenStreetMap data is © OpenStreetMap contributors and licensed under the [ODbL](https://www.openstreetmap.org/copyright). Council records keep their source name, link, dataset timestamp where available, and published licence in each record. See [`NOTICE.md`](../../../NOTICE.md) for attribution details.
