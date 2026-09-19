# Generated parking data

These artifacts are generated from public parking data and bundled so ParkAlong can join stable metadata locally, provide a clearly labelled historical fallback, and discover parking across Victoria:

- `zone_metadata.json`
- `restrictions.json`
- `historical_availability.json`
- `victoria_static_parking.json`
- `victoria_static_manifest.json`

The Victorian catalog currently contains 35,004 records: 28,921 OpenStreetMap features suitable for general discovery after excluding explicitly private/customer/resident/permit/employee/no-access parking, plus 6,083 records derived from anonymous council/state datasets, approved attributed layers, or official parking pages. This includes 368 public disabled-only Mildura bays, 45 Swan Hill accessible spaces, and 464 Vicmap parking areas. It is deliberately static; its download timestamp must never be presented as an occupancy timestamp. Regenerate it with `python3 Scripts/generate_victoria_static_catalog.py` and use the manifest to verify exact counts, attribution, size and hash. Do not manually edit generated artifacts or commit the raw 2019 archive.

City of Melbourne data is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). OpenStreetMap data is © OpenStreetMap contributors and licensed under the [ODbL](https://www.openstreetmap.org/copyright). Council records keep their source name, link, dataset timestamp where available, and published licence in each record. See [`NOTICE.md`](../../../NOTICE.md) for attribution details.
