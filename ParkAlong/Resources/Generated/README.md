# Generated parking data

These artifacts are generated from public parking data and bundled so ParkAlong can join stable metadata locally, provide a clearly labelled historical fallback, and discover parking across Victoria:

- `zone_metadata.json`
- `restrictions.json`
- `historical_availability.json`
- `victoria_static_parking.json`
- `victoria_static_manifest.json`

The Victorian catalog currently contains 30,890 records: 28,825 OpenStreetMap features suitable for general discovery after excluding explicitly private/customer/resident/permit/employee/no-access parking, plus 2,065 records derived from anonymous council datasets or official council pages. It is deliberately static; its download timestamp must never be presented as an occupancy timestamp. Regenerate it with `python3 Scripts/generate_victoria_static_catalog.py` and use the manifest to verify exact counts. Do not manually edit generated artifacts or commit the raw 2019 archive.

City of Melbourne data is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). OpenStreetMap data is © OpenStreetMap contributors and licensed under the [ODbL](https://www.openstreetmap.org/copyright). Council records keep their source name, link, dataset timestamp where available, and published licence in each record. See [`NOTICE.md`](../../../NOTICE.md) for attribution details.
