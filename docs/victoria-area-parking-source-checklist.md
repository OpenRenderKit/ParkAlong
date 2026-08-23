# Victoria parking source coverage checklist

Research checkpoint: **23 August 2026 (Australia/Melbourne)**.

This is the exhaustive area ledger for ParkAlong's Victorian scope. It uses the [Victorian Electoral Commission's 79-council list](https://www.vec.vic.gov.au/electoral-boundaries/local-councils) and [Vicmap Admin](https://discover.data.vic.gov.au/dataset/vicmap-admin) LGA polygons. Vicmap returns 87 polygons: 79 councils plus eight unincorporated areas.

Every row below has been checked against:

1. the existing 30,890-record ParkAlong catalogue;
2. council/authority parking pages, maps, studies and open-data portals;
3. DataVic parking searches;
4. public ArcGIS items and FeatureServer schemas;
5. known parking-app and sensor vendors.

`[x]` means the area has been researched in this pass. It does **not** mean live data exists. The evidence codes deliberately keep different kinds of data separate:

- **LIVE** — fresh anonymous occupied/vacant events with location and event time;
- **STATIC** — machine-readable authority geometry, capacity, restriction or price data;
- **DOC** — current authority webpage, PDF, map or published strategy/study;
- **HIST** — historical occupancy, transaction, survey or utilisation evidence;
- **APP** — public app/display claim, but no verified anonymous API;
- **INTERNAL** — sensors exist for enforcement/planning or through a private vendor;
- **OSM** — OpenStreetMap is the only machine-readable statewide baseline found;
- **CANDIDATE** — public technical source found, but provenance/licensing is not yet strong enough to ship;
- **N/A** — ordinary public motor-vehicle parking is not a meaningful product case.

The catalogue count is a spatial join of ParkAlong's current static records to the area boundary. It measures discoverable locations, not rule completeness or availability quality.

## 79 councils

| Checked | Council | Catalogue records | Authority-specific evidence found | Honest current state |
| --- | --- | ---: | --- | --- |
| [x] | Alpine | 128 | DOC | Bright/Dinner Plain precinct material; OSM supplies the structured baseline |
| [x] | Ararat | 45 | DOC, APP conflict | Council removed meters in 2020 and retained time limits; EasyPark still lists Ararat, so current payment applicability must be reconciled before showing a price |
| [x] | Ballarat | 1,318 | STATIC, HIST | 760 zone records, 147 meters and monthly transaction aggregates; transaction activity is not vacancy |
| [x] | Banyule | 483 | DOC | Permit-area and parking pages found; no maintained restriction or occupancy feed found |
| [x] | Bass Coast | 249 | APP, INTERNAL, DOC | 730 sensors in Cowes/Wonthaggi; public app is advertised but its inspected backend is unavailable, so no live state is accepted |
| [x] | Baw Baw | 242 | DOC, HIST | Drouin/Yarragon/traffic studies contain supply, restriction, occupancy and duration survey evidence |
| [x] | Bayside | 255 | INTERNAL, DOC | Church Street/Sandringham sensors and signs; no anonymous timestamped feed, and council strategy did not favour web publication |
| [x] | Benalla | 67 | DOC | Rules/enforcement information found; no structured authority dataset or occupancy history found |
| [x] | Boroondara | 750 | STATIC, INTERNAL | Curated council car parks plus enforcement sensors/PayStay; no public live sensor state |
| [x] | Brimbank | 741 | STATIC | Public council car-park polygons include bay count/restriction-style attributes; no live occupancy |
| [x] | Buloke | 51 | OSM | No parking-specific authority dataset, map, price table or utilisation study found in this pass |
| [x] | Campaspe | 179 | DOC | Echuca CBD/port/health maps and current paid/free rules; machine-readable restriction geometry not found |
| [x] | Cardinia | 590 | DOC | General parking rules found; four Casey/PTV station features cross the spatial boundary and need provenance-safe deduplication |
| [x] | Casey | 2,242 | STATIC | 4,341 restriction records plus council car parks and a 32-polygon PTV station-car-park snapshot |
| [x] | Central Goldfields | 37 | OSM | No parking-specific authority dataset, map, current tariff table or utilisation study found |
| [x] | Colac Otway | 137 | CANDIDATE, DOC | Public contractor ArcGIS layer has 173 carpark assets, but council provenance/licence needs confirmation before shipping |
| [x] | Corangamite | 111 | DOC | Accessible-parking maps and an active Port Campbell review; no structured general parking feed found |
| [x] | Darebin | 618 | DOC | Permit/restriction pages and policy material; no public sensor state or structured restriction layer found |
| [x] | East Gippsland | 476 | DOC | Bairnsdale rules identify two-hour and all-day facilities; no structured feed found |
| [x] | Frankston | 460 | APP, INTERNAL | About 500 sensors and signs; vendor app exists but its inspected API hostname does not currently resolve |
| [x] | Gannawarra | 34 | DOC | Timed parking information for Cohuna/Kerang; no structured geometry or history found |
| [x] | Glen Eira | 275 | APP, INTERNAL, DOC | Sensors and PayStay launched in Carnegie/Bentleigh/Elsternwick; no anonymous usable API verified |
| [x] | Glenelg | 99 | DOC | Portland meter/tariff material found; current effective rate needs explicit revalidation before display |
| [x] | Golden Plains | 92 | OSM | No parking-specific authority dataset, map, price table or utilisation study found |
| [x] | Greater Bendigo | 705 | DOC, APP | Current city-centre map and published rates; PayStay availability claim is app-only |
| [x] | Greater Dandenong | 714 | INTERNAL, DOC | Sensors/control software exist; council material treats public app/sign availability as future capability |
| [x] | Greater Geelong | 1,297 | HIST, STATIC stale | Deleted current catalogue feeds survive only as cached 2021/2022 events; historical utilisation is useful only with COVID-era caveats |
| [x] | Greater Shepparton | 295 | DOC, HIST | Named free facilities/capacities and parking studies; proposed sensors were not verified as a public live system |
| [x] | Hepburn | 92 | DOC | Daylesford parking/permit information; no structured restriction, price or occupancy source found |
| [x] | Hindmarsh | 46 | OSM | No parking-specific authority dataset, map, price table or utilisation study found |
| [x] | Hobsons Bay | 374 | DOC, APP | Altona Beach strategy/restriction maps and EasyPark coverage; no anonymous occupancy feed |
| [x] | Horsham | 95 | DOC | Meters removed in 2025; free two-hour limits remain, so old paid-parking records must be expired |
| [x] | Hume | 992 | DOC | Parking management policy and enforcement material; no public structured rule/availability source found |
| [x] | Indigo | 105 | DOC | Named Beechworth/Yackandandah parking facilities and maps; no structured rules/history found |
| [x] | Kingston | 635 | DOC, APP | Beach/trader parking information and EasyPark coverage; no verified occupancy endpoint |
| [x] | Knox | 621 | INTERNAL, DOC | Sensor locations in four activity centres are published, but readings are for enforcement/planning rather than public vacancy |
| [x] | Latrobe | 233 | STATIC, DOC | Official ArcGIS view exposes 273 accessible spaces; car-park register and Traralgon sign material add static context |
| [x] | Loddon | 46 | OSM | No parking-specific authority dataset, map, tariff table or utilisation study found |
| [x] | Macedon Ranges | 142 | DOC | General parking/permit information found; no structured location/rule/history feed |
| [x] | Manningham | 524 | STATIC, INTERNAL | 387 council-owned carpark polygons plus a public restrictions dataset; sensors do not expose vacancy |
| [x] | Mansfield | 53 | OSM | No authority-specific structured parking source or usable study found |
| [x] | Maribyrnong | 838 | STATIC, HIST, INTERNAL | Rich ArcGIS bays/restrictions/ticket annotations and old survey layers; advertised 3,500-sensor live host was unavailable |
| [x] | Maroondah | 600 | DOC | Council parking pages/framework found; no structured authority source or occupancy history found |
| [x] | Melbourne | 883 static | LIVE, STATIC, HIST | Only verified fresh anonymous Victorian occupancy feed; extensive restrictions, meters and 2011–2020 history also exist |
| [x] | Melton | 460 | DOC | Restriction map and general rules found; no maintained structured or live source |
| [x] | Merri-bek | 421 | INTERNAL, APP, DOC | Sensor/vendor and EasyPark evidence plus policies; no anonymous live state found |
| [x] | Mildura | 554 | DOC, HIST | Published parking supply and free-parking context; no public live/transaction feed found |
| [x] | Mitchell | 161 | DOC | General rules/project material only; no structured authority parking source found |
| [x] | Moira | 74 | DOC, HIST | Cobram/Yarrawonga precinct plans provide static/survey evidence; no maintained feed found |
| [x] | Monash | 817 | CANDIDATE, INTERNAL, DOC | Sensors across listed locations plus consultant ArcGIS study geometry; candidate layer lacks licence/rule fields |
| [x] | Moonee Valley | 469 | DOC, APP | Permit/event and school Park-and-Walk maps plus EasyPark coverage; no verified occupancy feed |
| [x] | Moorabool | 154 | STATIC, DOC, HIST | Official public ArcGIS service contains 178 active car-park assets; studies add utilisation context |
| [x] | Mornington Peninsula | 1,075 | INTERNAL, HIST, DOC | Rye/Mornington trials and parking plans; no current anonymous driver feed verified |
| [x] | Mount Alexander | 126 | DOC | Parking restrictions/permits page found; no structured source or occupancy history found |
| [x] | Moyne | 88 | DOC, HIST | Port Fairy strategy contains detailed supply/usage evidence; it is not current occupancy |
| [x] | Murrindindi | 184 | DOC | Town mobility maps identify accessible parking; no general structured parking feed found |
| [x] | Nillumbik | 421 | INTERNAL, DOC | Eltham/Diamond Creek sensors/LPR and restricted-space lists; no public live feed |
| [x] | Northern Grampians | 135 | OSM | No parking-specific authority dataset, current map/tariff or utilisation source found |
| [x] | Port Phillip | 190 | STATIC older, INTERNAL, APP | 52,000 on-street spaces and 1,571 sensors; public static datasets exist but no anonymous live state |
| [x] | Pyrenees | 44 | OSM | No parking-specific authority dataset, map, tariff table or utilisation study found |
| [x] | Queenscliffe | 34 | DOC | Council states parking is free with posted time limits; no live or structured rule feed |
| [x] | South Gippsland | 166 | DOC, HIST | Leongatha study/map provides supply and utilisation evidence; no current structured feed |
| [x] | Southern Grampians | 71 | CANDIDATE, DOC | Current Hamilton tariff material plus a 22-asset contractor inspection layer requiring provenance confirmation |
| [x] | Stonnington | 194 | INTERNAL, APP, STATIC | Sensor/PayStay and public-sign evidence plus curated facilities; no anonymous live endpoint |
| [x] | Strathbogie | 43 | DOC sparse | Individual project evidence found; no municipality-wide structured source or study found |
| [x] | Surf Coast | 270 | INTERNAL, DOC | 399 sensors across major coastal towns; no public timestamped vacancy response verified |
| [x] | Swan Hill | 112 | DOC | Current meter rate and two-hour rule published; no structured tariff/availability API |
| [x] | Towong | 88 | OSM | No parking-specific authority dataset, map, tariff table or utilisation study found |
| [x] | Wangaratta | 130 | DOC, APP | Current weekday meter rate and EasyPark coverage; no anonymous occupancy feed |
| [x] | Warrnambool | 188 | DOC, HIST | Current hourly/all-day prices and studies; no public live source found |
| [x] | Wellington | 228 | DOC | Enforcement/local-law material found; no public carpark/rule dataset or usage history found |
| [x] | West Wimmera | 30 | OSM | No parking-specific authority dataset, map, tariff table or utilisation study found |
| [x] | Whitehorse | 758 | INTERNAL, STATIC | Curated official facilities plus more than 3,000 enforcement sensors; no public live state |
| [x] | Whittlesea | 1,057 | DOC, HIST | Epping Central precinct plan/study evidence; no maintained structured or live feed found |
| [x] | Wodonga | 249 | STATIC, HIST | Official 672-polygon source includes capacity, accessibility and multiple conditional time-limit fields |
| [x] | Wyndham | 1,386 | INTERNAL, STATIC | Council facilities plus a completed 180-space camera pilot; no current public live response |
| [x] | Yarra | 552 | STATIC stale, INTERNAL | Small/stale permit-zone export and sensor-location material; enforcement sensors do not expose vacancy |
| [x] | Yarra Ranges | 860 | DOC | Current framework and possible Warburton digital/paid pilot; no live/structured source found |
| [x] | Yarriambiack | 38 | OSM | No parking-specific authority dataset, map, tariff table or utilisation study found |

## Eight unincorporated areas

| Checked | Area | Catalogue records | Authority-specific evidence found | Honest current state |
| --- | --- | ---: | --- | --- |
| [x] | Falls Creek Alpine Resort | 13 | DOC | 2026 resort-entry/parking permit rules and prices; no anonymous space-level occupancy feed verified |
| [x] | French Island / Elizabeth Island / Sandstone Island | 5 | DOC, N/A in parts | Tankerton/Stony Point access parking is relevant; island groups without road access should not receive fabricated vacancy predictions |
| [x] | Gabo Island | 0 | N/A | Access is by boat or licensed aircraft, not an ordinary public road/parking destination; zero catalogue records is the correct outcome |
| [x] | Lake Mountain Alpine Resort | 7 | DOC | 2026 day vehicle entry is $69; winter entry windows and seasonal closure rules are published, summer entry is free |
| [x] | Mount Baw Baw Alpine Resort | 6 | DOC | 2026 resort-entry/parking permit rules and price found; no public space-level feed verified |
| [x] | Mount Buller Alpine Resort | 22 | APP/display, DOC | 2026 permits plus a public capacity display; display semantics/timestamps need capture before any live classification |
| [x] | Mount Hotham Alpine Resort | 19 | DOC | 2026 resort-entry/parking rules and price found; transit-through exception is materially different from stopping/parking |
| [x] | Mount Stirling Alpine Resort | 4 | DOC | 2026 day and overnight vehicle permit rules/prices found; no public space-level occupancy feed verified |

## Statewide result

- **87/87 areas identified and checked**: 79 councils and eight unincorporated polygons.
- **79/79 councils have at least an OSM location baseline** in the current catalogue.
- **86/87 polygons have at least one catalogue record**; Gabo Island is intentionally the exception because normal road parking is not applicable.
- **One area has verified fresh anonymous occupancy**: City of Melbourne.
- Static official and high-value candidate services are broader than the current app integration, especially in Wodonga, Manningham, Latrobe, Moorabool, Colac Otway, Monash and Southern Grampians.
- A source may help one part of the product without answering the others: a carpark polygon can improve search, a sign layer can resolve time limits, transactions can train demand models, and only a fresh recognized sensor event may claim “available now.”

## Next verification queue

The next passes should be ordered by likely user value and data density, not alphabetically:

1. validate licence/provenance and field semantics for the seven newly discovered ArcGIS services;
2. inspect every public web map's item dependency chain for hidden FeatureServers, not just its visible UI;
3. request documented feeds or data-sharing terms from EasyPark, PayStay, Orikan/Urbiotica and the councils with large sensor fleets;
4. acquire complete Melbourne 2011–2020 history and non-COVID Geelong history as model benchmarks, while keeping geography-specific calibration separate;
5. add official tariff effective dates, public-holiday semantics and sign precedence to a versioned rule ledger;
6. use OSM, Vicmap points of interest, PTAL, traffic, weather, events, school terms and land-use data only as explanatory prediction features—not as made-up vacancy labels.

The detailed endpoint tests and fail-closed acceptance rules live in [Victorian parking data source audit](victoria-parking-data-sources.md).
