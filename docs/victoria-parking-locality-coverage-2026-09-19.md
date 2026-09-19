# Victorian parking catalogue locality coverage

Audited on **19 September 2026 (Australia/Melbourne)** by spatially joining catalogue records to official Vicmap locality polygons. The complete machine-readable before/after result is in [`victoria-parking-locality-coverage-2026-09-19.json`](victoria-parking-locality-coverage-2026-09-19.json).

## Method and authority boundary

- Boundary source: `https://services-ap1.arcgis.com/P744lA0wf4LlBZ84/arcgis/rest/services/Vicmap_Admin/FeatureServer/11/query`.
- Locality polygons: 2,973. Distinct localities in the after catalogue: 1,481 per the manifest.
- Before catalogue: 35,004 records, 35,000 spatially assigned, 0 locality-field labeled, 35,004 unmatched, 4 outside polygons.
- After catalogue: 38,610 records, 38,606 spatially assigned and locality-field labeled, 4 outside polygons.
- Outside-locality-polygon records (locality unlabeled): `osm-way-39889371`, `osm-way-89782111`, `osm-way-186249854`, `osm-way-503565304`. Three of the four also sit outside the LGA land polygons and keep municipality `Victoria`; `osm-way-186249854` sits inside Bass Coast. Conversely `osm-way-41803181` sits outside the LGA polygons (municipality `Victoria`) but inside the Torquay locality polygon, so it is locality-labeled despite keeping the generic municipality.
- Target set: 62 named localities. All 62 polygons are present.
- Locality labels are derived from official Vicmap polygons and do not upgrade parking-source authority. A record that gains a locality name keeps its original source, licence, dataset time, and `static_only` classification.

## New feeds in this window

All new feeds are static-only:

- Brimbank car parks (2,909 records) and Brimbank accessible bays (187 records) from the source resource dated 2019-03-12. Restrictions with exclusion semantics were withheld/filtered conservatively.
- Four Greater Dandenong facilities (Carroll Lane, Thomas Street, Walker Street, Number 8) with opening-hour schedules only. Greater Dandenong tariffs were omitted because the pages publish no fee-effective date.
- Number 8 capacity remains unknown because the source says more than 500.

## Before/after locality coverage

Authoritative means non-OpenStreetMap records spatially assigned to that locality.

| Locality | Before total / After total | Before authority / After authority |
| --- | ---: | ---: |
| St Albans | 123 / 534 | 0 / 411 |
| Sunshine | 86 / 368 | 0 / 282 |
| South Melbourne | 23 / 100 | 0 / 77 |
| St Kilda | 37 / 110 | 0 / 73 |
| Bentleigh | 28 / 60 | 0 / 32 |
| Elsternwick | 18 / 36 | 0 / 18 |
| Carnegie | 20 / 33 | 0 / 13 |
| Caulfield | 10 / 14 | 0 / 4 |
| Dandenong | 181 / 184 | 8 / 11 |
| Springvale | 101 / 102 | 0 / 1 |
| Reservoir | 89 / 88 | 0 / 0 |

Changed source sets:

- St Albans: OSM-only to `brimbank-carparks`, `brimbank-disabled-car-parks`, OSM.
- Sunshine: OSM-only to `brimbank-carparks`, `brimbank-disabled-car-parks`, OSM.
- South Melbourne: OSM-only to OSM, `port-phillip-accessible-parking`.
- St Kilda: OSM-only to OSM, `port-phillip-accessible-parking`.
- Bentleigh, Elsternwick, Carnegie, Caulfield: OSM-only to `glen-eira-accessible-parking`, OSM.
- Dandenong: Casey zones, Casey station snapshot, OSM to the same plus `greater-dandenong-carroll-lane`, `greater-dandenong-thomas-street`, `greater-dandenong-walker-street`.
- Springvale: OSM-only to `greater-dandenong-number-8`, OSM.
- Reservoir: OSM-only in both windows; 89 to 88 is normal live-fetched OpenStreetMap movement, not source removal.

The remaining 51 of 62 target localities are unchanged, including Burwood, Kew, Hawthorn, Glen Waverley, Tarneit, South Yarra, Box Hill, Clayton, Camberwell, Canterbury, Balwyn, Surrey Hills, Blackburn, Nunawading, Mount Waverley, Oakleigh, Chadstone, Noble Park, Prahran, Windsor, Malvern, Armadale, Toorak, Richmond, Cremorne, Fitzroy, Collingwood, Frankston, Cranbourne, and the other listed targets. Glen Waverley, Clayton, Mount Waverley, Oakleigh, and Chadstone retain existing Monash review geometry with no new facility ingest in this window. Tarneit, Ringwood, and the other OSM-only targets remain discovery-only.

## Material research holds

No ingest occurred where reuse permission, exact geometry, or exact current semantics were unresolved. This includes additional Stonnington facilities, Deakin Burwood, West Tarneit, Ringwood/hospital candidates, and Glen Waverley page corrections not safely mappable to source polygons.

## Interpretation limits

- Counts are feature counts, not bay counts.
- Points are assigned by stored coordinate or polygon centroid; points outside every polygon remain explicit and unlabeled.
- Static geometry is not current occupancy. No new live coverage is claimed.
