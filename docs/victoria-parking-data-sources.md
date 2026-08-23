# Victorian parking data source audit

Checked on **23 August 2026 (Australia/Melbourne)**. This is an endpoint audit, not a list of vendor claims.

## Integration rule

ParkAlong may show live availability only when an anonymously accessible response contains:

1. a recognized occupied/vacant state;
2. a usable parking location or zone;
3. a source event timestamp no more than 24 hours old and no more than five minutes in the future.

An HTTP 200 response, recent catalog metadata, an app-store description, or the word “real-time” is not enough. Static data can provide locations or restrictions, but must never be converted into an availability colour. Sources that require an app session, private token, or commercial agreement are rejected for ParkAlong. A Transport Victoria portal account was created during this audit because the user explicitly requested it; the signed-in catalog still exposed no parking occupancy collection, so ParkAlong has no reason to carry that account or key at runtime.

## Outcome

**City of Melbourne remains the only verified, current, anonymous live occupancy feed found.** Several councils operate sensor networks and consumer apps, but no second feed met all of ParkAlong's anonymous-access and timestamp requirements during this audit.

Useful anonymous static sources do exist for Maribyrnong, Ballarat, Casey, Boroondara, selected official council car parks, and statewide through OpenStreetMap. The generated ParkAlong catalog currently contains 30,890 nearby-searchable records after filtering explicitly restricted OpenStreetMap parking. Geelong's cached “real-time” resources are historical and are not safe for current availability.

## Source matrix

| Area/source | What exists publicly | Direct test on 23 Aug 2026 | Classification | ParkAlong decision |
| --- | --- | --- | --- | --- |
| City of Melbourne | Opendatasoft bay sensor API plus zones/restrictions | Municipality-wide probe: 6,324 catalog rows; 2,667 fresh recognized rows; newest `2026-08-23T04:22:54Z` | **Verified live occupancy** | Keep current adapter and 24-hour fail-closed filter |
| Maribyrnong | Council claims 3,500+ sensors and advertises a live dashboard; a new ArcGIS Parking Explorer is public | Advertised live host timed out in the in-app Browser. ArcGIS returned 10,379 regular, 191 accessible, 1,289 permit/loading bays, 20 parklets, 4,677 EasyPark-machine annotations, 1,094 restriction annotations and 7,158 ticket/pricing annotations, but no occupancy fields | **Current static data; advertised live feed unavailable** | No live adapter. Static geometry is a candidate with council signage caveat |
| Greater Geelong | DataVic pages labelled continual/real-time; old Geelong Data Exchange exports | Current Geelong catalog returned 58 datasets and no parking dataset IDs. DataVic cache: 18 space-status rows newest `2021-08-12T16:44:35Z`; 24 lot rows newest `2022-08-23T23:15:04.634Z` | **Stale/historical** | Never show as live; retain only as research/history |
| Frankston | Council page, about 500 sensors, five digital signs, Urbiotica “Parking at Frankston” app | Android/iOS listings still exist but remain on version 1.1.0 from Dec 2022. Static inspection of the public Android package found the app's API hostname; that hostname did not resolve in DNS on 22 Aug 2026, so no response or event timestamp could be obtained | **Advertised app-only occupancy; app backend unavailable** | Reject until a fresh anonymous response proves otherwise |
| Bass Coast (Cowes/Wonthaggi) | Council says 730 sensors and signs are operational; Urbiotica “Bass Coast Parking” app | The Android listing exists and remains version 1.1.0 from 2 Dec 2022. Its public package uses the same currently unresolvable API hostname as Frankston, so no occupancy response or timestamp could be obtained | **Advertised app-only occupancy; app backend unavailable** | Reject as a live source |
| Glen Eira | Sensors in Carnegie, Bentleigh and Elsternwick; PayStay went live 1 Jun 2026 | Current council page claims real-time availability, but the PayStay public map calls tested anonymously returned errors | **Consumer-app claim; no anonymous feed** | Reject under the no-account/session rule |
| Stonnington | Sensors and PayStay; public signs at multi-level car parks | Council confirms PayStay availability, but no anonymous timestamped endpoint was verified | **Consumer-app only** | Reject |
| Greater Bendigo | PayStay traffic-light availability and city-centre parking map | Council materials describe PayStay availability. Anonymous PayStay map requests failed; the PDF map is static | **Static map plus app-only claim** | Use static map only if converted and maintained; reject occupancy |
| Whitehorse | In-ground enforcement sensors and PayStay payments | Current council pages describe enforcement; older strategy says availability/app should be investigated | **No current public occupancy** | Reject occupancy |
| Greater Dandenong | Sensors in Dandenong and Springvale; council/internal real-time control software | Council explicitly describes public apps/signage as a future capability | **Internal occupancy only** | Reject occupancy; public off-street list is static |
| Bayside | Church Street and Sandringham sensors/signs; UbiPark previously used | Council's 2024 strategy says website publication was investigated and deemed redundant; public consumer endpoint was not found | **Signs/app, no anonymous feed** | Reject occupancy |
| Ballarat | Open-data zones, meters, monthly transactions | API returned 760 zone records, 147 meters and 9,184 transaction aggregates; newest transaction date `2026-03-01` | **Current static plus historical usage** | Good static candidate; transactions must not imply vacancy |
| Casey | Restriction zones, council car-park geometry and a PTV station-car-park snapshot | 4,341 restriction records; 32 station car-park polygons in the public PTV-derived snapshot | **Static locations/restrictions** | Good static candidate, with snapshot date shown |
| Yarra | Thousands of enforcement sensors and PayStay payments | Council's public page describes compliance alerts and provides a static PDF sensor-location map, not vacancy | **Internal enforcement data** | Reject occupancy; PDF is only a coarse static reference |
| Port Phillip | Sensors progressively deployed and PayStay | Public pages describe sensors/payment, but no anonymous timestamped vacancy endpoint was found | **Internal/app-only data** | Reject occupancy |
| Monash | In-ground sensors across 26 listed streets and car parks | [Council's current page](https://www.monash.vic.gov.au/Parking-Streets-Footpaths/Parking/Parking-Fines/In-ground-parking-sensors) says readings go to parking-inspector devices for overstay enforcement and trend monitoring; it exposes no public vacancy map or API | **Internal enforcement data** | Reject occupancy; the location list is a coarse static reference |
| Knox | In-ground sensors across Bayswater, Boronia, Wantirna and Upper Ferntree Gully | [Council's current page](https://www.knox.vic.gov.au/our-services/parking-and-transport/street-parking-sensors) lists installed areas and says the data supports enforcement and planning, but provides no public live map or timestamped response | **Internal enforcement data** | Reject occupancy; the location table is static |
| Greater Shepparton | A 2020 strategy proposed 1,500 sensors and a public app | A [2022 council report](https://greatershepparton.vic.gov.au/assets/files/documents/governance/meetings/2022/10/Agenda_-_Council_Meeting_-_27_October_20221.pdf) says sensors were costed for a future budget and many strategy actions had not been scoped or implemented. No later anonymous live endpoint was found | **Proposal, not a verified feed** | Reject occupancy |
| Mornington Peninsula (Rye/Mornington) | Rye 2020 smart-parking trial; later Mornington trial/sensors | Current material describes trials and internal occupancy analysis, but no current anonymous driver feed was found | **Trial/historical or internal** | Reject occupancy |
| Wyndham (Werribee) | A 180-space camera smart-parking pilot at Westend Carpark | Council marks the pilot completed; no current public vacancy map or timestamped endpoint was found | **Completed pilot/static location** | Keep only as a static location if independently maintained |
| Boroondara | In-ground enforcement sensors and PayStay payment in metered areas | Council explains how to identify sensor bays but exposes no public occupied/vacant map or endpoint | **Internal enforcement data** | Reject occupancy |
| PTV / Transport Victoria | Timetables, road/public-transport APIs, station amenities and static car-park references | A requested portal account was activated with MFA and automatically received a masked subscription key. Signed-in portal and CKAN API searches for `parking`, `carpark`, and `car park` returned zero data collections. The former DataVic train-car-park package is absent; Casey preserves a 32-polygon 2024 snapshot | **No parking feed; static snapshot elsewhere** | Do not add a Transport key to ParkAlong. Casey snapshot may be labelled static |
| OpenStreetMap | Statewide `amenity=parking` geometry and optional tags | Anonymous Overpass query for `AU-VIC` returned 36,622 features at OSM base timestamp `2026-08-23T04:25:10Z` | **Current-ish community static data** | Strong statewide location candidate with ODbL attribution; never occupancy |

## Exact endpoint evidence

### City of Melbourne: verified live

The [on-street parking bay sensor API](https://data.melbourne.vic.gov.au/explore/dataset/on-street-parking-bay-sensors/) currently contains 6,324 sensor rows. The 23 August municipality-wide query accepted only recognized states with a location, a zone number, and an event timestamp inside ParkAlong's 24-hour window:

```json
{
  "catalogRows": 6324,
  "trustedRows": 2667,
  "present": 1780,
  "unoccupied": 887,
  "newest": "2026-08-23T04:22:54+00:00"
}
```

The other 3,657 catalog rows were not treated as current usable occupancy. That conservative under-count is intentional.

For geographic context, the preceding 22 August probe joined its 2,690 trusted sensor points to the City's 13 CLUE small-area polygons and produced this snapshot. These are the only Victorian areas where the audit could actually retrieve a fresh bay state, rather than merely finding a council claim or app listing:

| City of Melbourne small area | Fresh bays | Unoccupied | Present |
| --- | ---: | ---: | ---: |
| Melbourne (CBD) | 1,328 | 496 | 832 |
| Southbank | 326 | 155 | 171 |
| East Melbourne | 270 | 121 | 149 |
| West Melbourne (Residential) | 256 | 165 | 91 |
| Carlton | 215 | 127 | 88 |
| Docklands | 142 | 52 | 90 |
| North Melbourne | 80 | 33 | 47 |
| Melbourne (Remainder) | 69 | 36 | 33 |
| South Yarra | 4 | 0 | 4 |

The API supplies the precise coordinate for every accepted bay, so ParkAlong can render the individual locations on demand without freezing a 2,690-row snapshot into the app.

### Maribyrnong: current static map, no verified live occupancy

The council's [Smart City Projects page](https://www.maribyrnong.vic.gov.au/Community/A-Smart-City-for-Smart-Communities/Smart-City-Projects) says more than 3,500 sensors are installed and links to:

```text
http://scdataplatform.maribyrnong.vic.gov.au/city-discovery-community/available-parking/
```

The in-app Browser timed out while loading that host; direct HTTP and HTTPS tests also timed out. The [Footscray Library Carpark dashboard](https://www.maribyrnong.vic.gov.au/Community/A-Smart-City-for-Smart-Communities/Smart-City-in-Action/Footscray-Library-Carpark) is live, but it counts vehicle, pedestrian and cyclist movement every 30 minutes. It is not parking-bay vacancy.

The older [Footscray parking occupancy map](https://www.maribyrnong.vic.gov.au/Residents/Transport-Parking-and-Road-Safety/Parking-Management-Policy-2017/Parking-Sensors/Parking-Management-in-Footscray-Precinct) exposes anonymous map metadata for exactly three survey layers:

- 23 July–5 August 2018;
- 4–17 February 2019;
- 19 April–2 May 2021.

Those layers are historical even though their map endpoint remains reachable in some browser sessions.

The new [Parking Explorer](https://maribyrnong.maps.arcgis.com/apps/instant/sidebar/index.html?appid=88ed6673549e415086b220dc6f321e3e) is useful static data. Its public ArcGIS services are anonymously queryable:

- [regular parking bays](https://services2.arcgis.com/PovBcp8J7VQYyDEI/arcgis/rest/services/Reg_Parking_Bay_GreenZone_Ply/FeatureServer/0): 10,379 polygons;
- [accessible bays](https://services2.arcgis.com/PovBcp8J7VQYyDEI/arcgis/rest/services/Reg_Parking_Bay_BlueZone_Ply/FeatureServer/0): 191 polygons;
- [permit/loading bays](https://services2.arcgis.com/PovBcp8J7VQYyDEI/arcgis/rest/services/Reg_Parking_Bay_RedZone_Ply/FeatureServer/0): 1,289 polygons;
- [parklets](https://services2.arcgis.com/PovBcp8J7VQYyDEI/arcgis/rest/services/Reg_Parking_Parklets_Ply/FeatureServer/0): 20 polygons.

Inspecting the map in the in-app Browser and following its public ArcGIS item chain (`app -> web map -> FeatureServer`) also exposed 4,677 EasyPark-machine annotations, 1,094 restriction annotations and 7,158 ticket-machine/pricing annotations. None of those services has a sensor state or event-time field.

The app item was modified `2026-08-20T11:35:00Z`; the regular-bay service reports its data edit at `2026-05-07T02:39:43.747Z`. The layers contain geometry/category fields, not sensor state or an occupancy event timestamp. The map's own disclaimer says street signs take precedence.

### Geelong: catalog label disproved by records

The [DataVic real-time availability page](https://discover.data.vic.gov.au/dataset/real-time-parking-availability-status) still says “continual,” but the corresponding export URLs point to datasets absent from Geelong's current catalog.

Anonymous tests found:

- current Geelong catalog: 58 datasets, zero IDs containing `parking`;
- DataVic resource `7f381a3a-fd9e-477f-a6ae-b45e1a65bb16`: 18 cached rows, newest event `2021-08-12T16:44:35Z`;
- DataVic resource `027f8bb4-3f90-4f8b-8c91-357c58c13ab9`: 24 cached rows, newest event `2022-08-23T23:15:04.634Z`.

Metadata updated in 2024 does not refresh the embedded sensor events. ParkAlong must keep Geelong closed until a new direct response proves current timestamps.

### Ballarat and Casey: useful static sources

Ballarat's anonymous Opendatasoft APIs currently provide:

- [car parking zones](https://data.ballarat.vic.gov.au/explore/dataset/realtime0/): 760 records;
- [parking meters](https://data.ballarat.vic.gov.au/explore/dataset/realtime1/): 147 records;
- [parking transactions](https://data.ballarat.vic.gov.au/explore/dataset/parking-transactions/): monthly aggregate usage, not occupancy.

Casey's anonymous catalog provides [4,341 parking restriction records](https://data.casey.vic.gov.au/explore/dataset/city-of-casey-parking-zones/) with type, days, times, exceptions and geometry. Its [Railway Station Carparks (PTV)](https://data.casey.vic.gov.au/explore/dataset/railway-station-carparks-ptv/) snapshot has 32 polygons and capacity fields, processed 13 September 2024. The original statewide DataVic package referenced by Casey now returns 404, so this is a static snapshot rather than a maintained PTV feed.

### OpenStreetMap: broad static coverage, sparse attributes

The following anonymous Overpass query returned 36,622 Victorian parking features:

```overpass
[out:json][timeout:90];
area["boundary"="administrative"]["ISO3166-2"="AU-VIC"]->.a;
nwr["amenity"="parking"](area.a);
out count;
```

Attribute coverage was uneven: 1,924 features had `capacity`, 11,572 had `access`, 4,867 had `fee`, 16,754 had a `parking` subtype, and only 80 had `opening_hours`. OSM is therefore valuable for discovery but cannot safely answer every restriction, capacity, or price question. Any integration needs [OpenStreetMap/ODbL attribution](https://www.openstreetmap.org/copyright).

## Rejected app, vendor, and partnership paths

These are deliberately **not integration leads** under ParkAlong's anonymous-only rule:

- **PayStay:** current council pages for [Glen Eira](https://www.gleneira.vic.gov.au/services/parking/parking-sensors-and-paystay-app), [Stonnington](https://www.stonnington.vic.gov.au/Services/Parking/Parking-sensors), Bendigo, Yarra and Port Phillip describe availability or payments. Static inspection of the publicly distributed Android app identified `POST /ParkingLocator/ParkingMapV2`, but a request with ordinary public map fields and no credentials returned HTTP 500. Public `ParkingMap`, `GetAllSuburbs`, and nearby-suburb calls also returned HTTP 500. A successful `/V2/Core/Ping` only proves the server is running. No credentials, app session, or private token were used or extracted.
- **Urbiotica:** [Frankston](https://www.frankston.vic.gov.au/Community-and-Health/Transportation-and-parking/Smart-Parking-Trial) lists Wells Street, Playne Street, Young Street, Thompson Street, Young Street East Car Park and Playne Street Car Park. [Bass Coast](https://engage.basscoast.vic.gov.au/smart-parking) lists Cowes (Thompson Avenue, Chapel Street, The Esplanade and Transit Centre long-term car park) and Wonthaggi (Graham Street and McBride Avenue). Both public Android packages were inspected without running them and point to the same API hostname, which did not resolve in DNS. No embedded credential was used and no access control was bypassed.
- **UbiPark/Orikan:** Bayside and older Maribyrnong material reference UbiPark. The former public motorist URL now redirects to Orikan's corporate site; no anonymous consumer vacancy map was present.
- **Transport Victoria APIs:** the requested account is active, MFA works, and a subscription key was automatically assigned. The signed-in catalog still has no parking or car-park data collection, so the key is irrelevant to ParkAlong and should not be stored in the project.
- **EasyPark developer APIs:** access is tied to a commercial agreement.
- **CellOPark, Wilson, Secure Parking, Parkopedia and similar operators:** public pages can supply names, addresses, booking links or advertised prices, but no anonymous, documented, timestamped Victorian occupancy API was verified. ParkAlong should continue using MapKit/provider links for off-street discovery instead of inventing availability.

## Implemented integration

1. City of Melbourne remains the only live sensor adapter.
2. The bundled catalog contains 477 clustered Maribyrnong results, 746 Ballarat zones, 668 Casey results, 155 Boroondara car parks, 19 curated official council facilities, and 28,825 OpenStreetMap parking features. The raw query returned 36,622 OSM features; 7,797 explicitly marked private, customer, resident, permit, employee, destination-only, or no-access features are intentionally excluded from suggestions.
3. Runtime search loads that catalog lazily, keeps only the nearest 24 eligible results, prefers council records, and suppresses an OpenStreetMap result within 75 metres of an accepted official result.
4. `sourceTimestamp`, `sourceDatasetAt`, `sourceCheckedAt`, and `classification` remain separate. Download time is never substituted for a sensor event.
5. New live regions still require a fresh anonymous probe. Stale, future-dated, missing, or semantically unclear occupancy fails closed.
6. The prediction path exists but only runs for a location with known capacity, at least 100 relevant observations, and held-out calibration error no greater than 10%. None of the newly bundled static sources currently carries qualifying evidence, so those locations remain honest red `P` results rather than fabricated estimates.

## Simple UI compromise

The implemented map communicates data quality without adding a second legend full of caveats:

1. **Fresh live occupancy:** keep the existing numbered green/orange/red pin. This is the only pin style allowed to say “available now.”
2. **Imperfect estimate:** use a flat deep-plum (`#6B3A6E`) pin with a leading `~` and a small amber warning. Its accessible label says “Estimate, not live.” Green/orange/red availability colours are reserved for current sensor readings.
3. **Location only:** use a flat red `P` pin with a small amber warning. The detail sheet says “Availability unknown” and still shows any trustworthy current restriction, effective price, capacity, walking distance, source age and official provider link.

To stay uncluttered, ParkAlong shows at most 24 nearby static results after a destination search and clusters Maribyrnong's bay geometry into street-scale results instead of drawing more than ten thousand individual bays. The compact amber symbol is the map warning; full source age and limitations live in the selected-place sheet. Posted signs remain authoritative.

## Reproduce the checks

Run the source probe:

```bash
python3 Scripts/probe_victoria_sources.py --source all
```

Run the fail-closed classifier tests:

```bash
python3 -m unittest Scripts/tests/test_probe_victoria_sources.py -v
```

The probe reports network failures as `unavailable_or_error`; it does not promote a source based on reachability alone.
