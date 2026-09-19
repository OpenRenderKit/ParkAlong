# Victorian parking catalogue geographic coverage

Audited on **19 September 2026 (Australia/Melbourne)** by spatially joining the generated 38,610-record catalogue to the current [Vicmap Admin LGA polygon service](https://services-ap1.arcgis.com/P744lA0wf4LlBZ84/arcgis/rest/services/Vicmap_Admin/FeatureServer/9). The complete machine-readable 87-area result is in [`victoria-parking-geographic-coverage-2026-09-19.json`](victoria-parking-geographic-coverage-2026-09-19.json), and the repeatable analysis is in [`Scripts/analyze_victoria_catalog_coverage.py`](../Scripts/analyze_victoria_catalog_coverage.py).

## What the statewide total hides

- **38,606 of 38,610 records** fall inside one of Vicmap's 87 polygons. Four OpenStreetMap polygon centroids sit outside the land polygons and are reported separately rather than silently forced into a council.
- **79 of 79 councils** contain at least one catalogue point, but this is not equivalent to adequate coverage. All councils inherit at least an OpenStreetMap discovery baseline.
- Only **44 of 79 councils** have even one non-OpenStreetMap record. The remaining **35 councils are discovery-only**.
- Only **15 councils** have an authority-specific record with a structured schedule, **9** have an authority-specific tariff record, **15** have authority-specific capacity, and **14** have authority-specific accessible-space evidence.
- **Zero catalogue records carry live occupancy.** Current occupancy remains a separate runtime City of Melbourne source and is not fabricated from static catalogue data.
- Generic municipality labels were reduced from **29,385 records to 4 records** by an authoritative 87-area Vicmap Admin spatial join. The join only rewrites records whose municipality is exactly `Victoria` and preserves explicit council labels, source provenance, identifiers, classification, schedules, and tariffs. The manifest now reports 87 municipality labels; the 4 remaining `Victoria` labels are the 4 LGA-outside points (`osm-way-39889371`, `osm-way-41803181`, `osm-way-89782111`, `osm-way-503565304`). LGA relabelling improves search and display geography but does not upgrade source authority or freshness.

These distinctions separate three different problems:

1. **True location absence:** no catalogue point exists. This applies only to Gabo Island, where normal public road parking is not a meaningful product case.
2. **Thin or discovery-only evidence:** points exist, but they are sparse or only OpenStreetMap. This is the main statewide gap.
3. **Naming and normalization:** points existed in a council but their raw source label was generic. This previously affected 29,385 records and explained why the earlier manifest reported only 23 municipality labels. That labelling gap is now closed to 4 outside records by the spatial join, without changing the underlying authority or freshness of any source.

## Coverage bands

The audit deliberately does not let a large OSM count masquerade as authority coverage.

| Band | Rule | Areas |
| --- | --- | ---: |
| `zero` | No catalogue record | 1 |
| `extremely_thin` | 1 to 9 records, regardless of provenance | 3 |
| `discovery_only` | 10 or more records, all from OpenStreetMap | 35 |
| `authority_thin` | At least 10 total records, but only 1 to 9 non-OSM records | 27 |
| `authority_backed` | At least 10 non-OSM records | 21 |

Vicmap parking-area centroids count as authority geometry, but do not prove bay-level supply, restrictions, tariffs, accessibility, or occupancy. An `authority_backed` label is therefore still not a completeness claim.

## Metropolitan Melbourne static-source expansion

This matrix covers exactly the 30 metropolitan Melbourne councils affected by the completed static-source expansion and the catalogue-wide LGA relabelling. Before totals are from the 35,004-record catalogue; after totals are from the current 38,610-record catalogue. Authority-specific means non-OpenStreetMap records spatially assigned to that council.

| Council | Before total / After total | Before authority / After authority |
| --- | ---: | ---: |
| Yarra | 548 / 548 | 0 / 0 |
| Port Phillip | 192 / 594 | 0 / 402 |
| Stonnington | 194 / 194 | 5 / 5 |
| Boroondara | 819 / 819 | 224 / 224 |
| Darebin | 618 / 617 | 0 / 0 |
| Merri-bek | 421 / 421 | 0 / 0 |
| Moonee Valley | 478 / 478 | 0 / 0 |
| Maribyrnong | 844 / 844 | 481 / 481 |
| Hobsons Bay | 376 / 376 | 0 / 0 |
| Bayside | 258 / 258 | 0 / 0 |
| Glen Eira | 274 / 379 | 0 / 105 |
| Kingston | 636 / 636 | 1 / 1 |
| Monash | 2255 / 2255 | 1440 / 1440 |
| Whitehorse | 764 / 764 | 1 / 1 |
| Manningham | 908 / 908 | 385 / 385 |
| Banyule | 482 / 482 | 0 / 0 |
| Nillumbik | 422 / 422 | 0 / 0 |
| Knox | 620 / 620 | 0 / 0 |
| Maroondah | 601 / 601 | 0 / 0 |
| Yarra Ranges | 866 / 866 | 0 / 0 |
| Greater Dandenong | 715 / 719 | 11 / 15 |
| Casey | 2247 / 2247 | 655 / 655 |
| Cardinia | 590 / 590 | 4 / 4 |
| Frankston | 460 / 460 | 6 / 6 |
| Mornington Peninsula | 1079 / 1079 | 2 / 2 |
| Whittlesea | 1057 / 1057 | 0 / 0 |
| Hume | 992 / 992 | 0 / 0 |
| Brimbank | 741 / 3837 | 0 / 3096 |
| Wyndham | 1396 / 1396 | 1 / 1 |
| Melton | 463 / 463 | 0 / 0 |
| **Totals** | **22,316 / 25,922** | **3,216 / 6,823** |

Darebin moves from 618 to 617 through one normal live-fetched OpenStreetMap record movement, not source removal. Glen Eira authority-specific count is 105 retained accessible records. Port Phillip gains 402 authority-specific records, Brimbank gains 3,096 authority-specific records, and Greater Dandenong gains four facility records. The metro net change from the 35,004 baseline is therefore +3,606 total records and +3,607 authority-specific records. All new Brimbank and Greater Dandenong feeds are static-only.

LGA relabelling improves search and display geography but does not upgrade source authority or freshness. A record that moves from `Victoria` to a council name through the polygon join keeps its original source, licence, dataset time, and `static_only` classification.

## Lowest-density councils

Every council below has fewer than 50 catalogue points. The authority count shows that most of that already small baseline is OSM-only.

| Council | Total records | Authority records | Current interpretation |
| --- | ---: | ---: | --- |
| West Wimmera | 31 | 1 | Extremely sparse; one Vicmap parking-area centroid |
| Gannawarra | 34 | 0 | Discovery-only |
| Queenscliffe | 34 | 0 | Discovery-only in a high-season coastal destination |
| Central Goldfields | 38 | 1 | Extremely sparse; one Vicmap centroid |
| Yarriambiack | 39 | 1 | Extremely sparse; one Vicmap centroid |
| Strathbogie | 43 | 0 | Discovery-only |
| Pyrenees | 44 | 0 | Discovery-only |
| Hindmarsh | 46 | 0 | Discovery-only |
| Loddon | 46 | 0 | Discovery-only |
| Ararat | 49 | 2 | Authority-thin; neither record supplies a municipality-wide rules layer |

## Highest-value geographic gaps

Priorities combine likely user value with the actual evidence gap. They are not ranked by raw record count.

| Priority cluster | Council | Total | Authority | Why it remains a gap |
| --- | --- | ---: | ---: | --- |
| Growth corridor | Wyndham | 1,396 | 1 | One curated facility does not cover Werribee activity centres, stations, or growth-area rules |
| Regional/transport hub | Greater Geelong | 1,304 | 1 | One curated rule record; the former sensor feeds are historical, and the structured ticket-machine resources remain dated 2014/2015 despite 2026 catalogue metadata activity |
| Growth corridor | Whittlesea | 1,057 | 0 | Large OSM baseline, no reusable authority structure |
| Growth corridor | Hume | 992 | 0 | Large OSM baseline, no reusable authority structure |
| Growth corridor | Brimbank | 3,837 | 3,096 | 2019-dated Brimbank car-park and accessible snapshots ingested as static-only; restrictions with exclusion semantics withheld/filtered conservatively |
| Growth corridor | Melton | 463 | 0 | Discovery-only despite major growth-centre use cases |
| Peri-urban/transport | Mitchell | 163 | 0 | Discovery-only along a major regional commuter corridor |
| Regional centre | Greater Shepparton | 314 | 9 | Curated facilities are useful but not a municipality-wide geometry/rule feed |
| Regional centre | Warrnambool | 190 | 2 | Current council price information is document-level; structured coverage is two centroids |
| Regional centre | Wangaratta | 132 | 1 | One curated CBD tariff record, not general coverage |
| Regional/tourism | Campaspe | 179 | 0 | Echuca has published maps and rules, but no reusable structured layer was verified |
| Regional centre | Benalla | 67 | 0 | Discovery-only |
| Coastal/regional | East Gippsland | 481 | 2 | Broad visitor geography with only two authority centroids |
| Coastal/tourism | Mornington Peninsula | 1,079 | 2 | Large OSM baseline, but only two station-car-park snapshot polygons are authority records |
| Coastal/tourism | Bass Coast | 251 | 2 | Council sensor claims exist, but no safe current anonymous endpoint was verified |
| Coastal/tourism | Surf Coast | 272 | 1 | One authority centroid; public sensor readings were not verified |
| Coastal/tourism | Queenscliffe | 34 | 0 | Sparse, seasonal, and discovery-only |
| Coastal/tourism | South Gippsland | 166 | 0 | Discovery-only; studies are not maintained structured data |
| Alpine/tourism | Alpine | 128 | 0 | Discovery-only despite seasonal access and parking complexity |
| Alpine/tourism | Mansfield | 53 | 0 | Discovery-only despite resort gateway traffic |

The practical acquisition order is therefore: growth-corridor council geometry and rules; Geelong and regional-city structured tariffs/rules; coastal and alpine seasonal restrictions; then lower-density rural discovery gaps. A commercial or credentialed operator feed should be pursued only through a documented agreement and should not be substituted for council restriction authority.

## Unincorporated areas

- Gabo Island has zero records and is the only true geographic zero. This is an appropriate product outcome for an island without ordinary public road access.
- Mount Stirling and Lake Mountain have four and seven OSM records respectively, with no authority records in the catalogue.
- French/Elizabeth/Sandstone Islands have seven records, including two Vicmap centroids.
- Falls Creek, Mount Hotham, and Mount Buller are authority-thin. Mount Baw Baw reaches the numerical `authority_backed` threshold through Vicmap centroids, but still has no structured schedule, tariff, capacity, accessibility, or live occupancy record.

## Interpretation limits

- Counts are feature counts, not bay counts. A single polygon can represent many spaces, while a row can represent one bay.
- Boundary-spanning source geometry is assigned by its stored point or centroid. The four outside points remain explicit in the JSON report.
- The spatial join only rewrites the exact `Victoria` municipality label. Explicit council labels are preserved, and the rewrite does not change source authority, licence, dataset time, or freshness.
- OSM fee, capacity, access, and opening-hours tags remain useful discovery evidence, but are not treated as council-authoritative.
- Static council or state geometry is not current occupancy. The audit contains no inference that changes a record's fail-closed classification.
