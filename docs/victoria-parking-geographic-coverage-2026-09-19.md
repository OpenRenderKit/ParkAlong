# Victorian parking catalogue geographic coverage

Audited on **19 September 2026 (Australia/Melbourne)** by spatially joining the generated 35,004-record catalogue to the current [Vicmap Admin LGA polygon service](https://services-ap1.arcgis.com/P744lA0wf4LlBZ84/arcgis/rest/services/Vicmap_Admin/FeatureServer/9). The complete machine-readable 87-area result is in [`victoria-parking-geographic-coverage-2026-09-19.json`](victoria-parking-geographic-coverage-2026-09-19.json), and the repeatable analysis is in [`Scripts/analyze_victoria_catalog_coverage.py`](../Scripts/analyze_victoria_catalog_coverage.py).

## What the statewide total hides

- **35,000 of 35,004 records** fall inside one of Vicmap's 87 polygons. Four OpenStreetMap polygon centroids sit outside the land polygons and are reported separately rather than silently forced into a council.
- **79 of 79 councils** contain at least one catalogue point, but this is not equivalent to adequate coverage. All councils inherit at least an OpenStreetMap discovery baseline.
- Only **41 of 79 councils** have even one non-OpenStreetMap record. The remaining **38 councils are discovery-only**.
- Only **15 councils** have an authority-specific record with a structured schedule, **9** have an authority-specific tariff record, **14** have authority-specific capacity, and **12** have authority-specific accessible-space evidence.
- **Zero catalogue records carry live occupancy.** Current occupancy remains a separate runtime City of Melbourne source and is not fabricated from static catalogue data.
- **29,385 records (83.9%)** use the generic raw municipality label `Victoria`. The manifest's 23 municipality labels therefore describe source labelling, not geographic reach. The polygon join recovers the actual geographic distribution without rewriting source provenance.

These distinctions separate three different problems:

1. **True location absence:** no catalogue point exists. This applies only to Gabo Island, where normal public road parking is not a meaningful product case.
2. **Thin or discovery-only evidence:** points exist, but they are sparse or only OpenStreetMap. This is the main statewide gap.
3. **Naming and normalization:** points exist in a council but their raw source label is generic. This affects 83.9% of records and explains why the manifest reports only 23 municipality labels.

## Coverage bands

The audit deliberately does not let a large OSM count masquerade as authority coverage.

| Band | Rule | Areas |
| --- | --- | ---: |
| `zero` | No catalogue record | 1 |
| `extremely_thin` | 1 to 9 records, regardless of provenance | 3 |
| `discovery_only` | 10 or more records, all from OpenStreetMap | 38 |
| `authority_thin` | At least 10 total records, but only 1 to 9 non-OSM records | 27 |
| `authority_backed` | At least 10 non-OSM records | 18 |

Vicmap parking-area centroids count as authority geometry, but do not prove bay-level supply, restrictions, tariffs, accessibility, or occupancy. An `authority_backed` label is therefore still not a completeness claim.

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
| Growth corridor | Brimbank | 741 | 0 | Public candidates exist, but the reusable snapshot is old and richer ArcGIS layers lack clear licence terms |
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
- OSM fee, capacity, access, and opening-hours tags remain useful discovery evidence, but are not treated as council-authoritative.
- Static council or state geometry is not current occupancy. The audit contains no inference that changes a record's fail-closed classification.
