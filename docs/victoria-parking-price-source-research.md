# Victoria parking price source research

Research checkpoint: **23 August 2026 (Australia/Melbourne)**.

ParkAlong currently falls back to “Check current price” for most locations. The honest way to improve that is a time-versioned price ledger—not a single `hourlyPrice` field—because Victorian parking can have free initial periods, hourly bands, daily caps, weekday/weekend differences, public-holiday exceptions and app/card surcharges.

## Verified public tariff examples

These are strong current examples found during the statewide pass. The checked-in catalog now implements the location-scoped Ballarat, Bendigo, Stonnington and Wyndham rules plus conservative OpenStreetMap `fee`/`charge` rules. The remaining council-wide findings stay in the verified-source queue until they can be attached to exact zones or facilities without overgeneralising.

| Area | Current public evidence | Rule ParkAlong could represent |
| --- | --- | --- |
| Melbourne CBD | [City review](https://participate.melbourne.vic.gov.au/central-city-parking-review/parking-improvements) | $7/hour to 7 pm weekdays; $4/hour after 7 pm and weekends; one free stay up to 15 minutes through EasyPark where eligible |
| Ballarat | [Current council FAQ](https://www.ballarat.vic.gov.au/city/parking/parking-ballarat/parking-frequently-asked-questions) | From 1 Aug 2026: first hour free after registration; then $3.60/hour; selected all-day carparks cap at $6.50; free Sundays/public holidays |
| Greater Bendigo | [Hargreaves Street carpark](https://www.bendigo.vic.gov.au/community-services/parking/where-park/hargreaves-street-multi-storey-car-park) | $2.40/hour or $10/day on weekdays; free weekends; opening hours, after-hours release and reserved rates are separate products |
| Greater Geelong | [Digital-parking change](https://yoursay.geelongaustralia.com.au/digital-parking/central-geelong-moving-100-cent-digital-parking) and [2025–26 fee schedule](https://www.geelongaustralia.com.au/common/Public/Documents/8dd8234f6ccad96-2025-26to2028-29proposedbudget-endorsedforexhibition-22april2025.pdf) | From 9 Mar 2026, 2P zones give two free hours and weekends are free; other paid products/rules must retain their zone-specific $3.70/hour and $10 cap evidence rather than flattening all Geelong to “free” |
| Hamilton / Southern Grampians | [Adopted 2026–27 pricing register](https://www.sthgrampians.vic.gov.au/files/assets/public/v/1/council-documents/governance/2026-27-pricing-register-public.pdf) | $1.50/hour in metered areas from the 2026–27 financial year; current parking page identifies 17 payment meters and surrounding free supply |
| Wangaratta | [Current council FAQ](https://www.wangaratta.vic.gov.au/Services/Parking/Parking-FAQs) | $1.20/hour Monday–Friday 9 am–5 pm in paid bays; free after 5 pm and weekends; free timed/all-day alternatives also exist |
| Warrnambool | [Current council parking page](https://www.warrnambool.vic.gov.au/parking) | $2/hour in hourly spaces, billed to actual duration in CellOPark; free first-hour and weekend/off-street conditions need to be attached to the exact carpark/zone |
| Swan Hill | [Current council trial notice](https://www.swanhill.vic.gov.au/Our-Council/News-and-publications/News-and-public-notices/Council-Leases-Curlewis-Street-Carpark-to-Boost-CBD-Parking-Options) | $1.40/hour, maximum two hours, for the described CBD/ticketed area |
| Horsham | Current council policy change found in the area audit | Meters were removed in June 2025; parking is free but posted two-hour limits still apply. Old paid records must be expired rather than averaged with current policy |
| Queenscliffe | Current council parking page found in the area audit | Council-managed parking is free; posted limits and special-purpose bays still control legality |
| Lake Mountain and all six alpine resorts | [Alpine Resorts Victoria](https://www.alpineresorts.vic.gov.au/news/behind-the-fees-resort-entry) and [Lake Mountain shop](https://shop.lakemountainresort.com.au/shop/product/78) | $69 vehicle day-entry/parking permit in winter 2026; seasonal dates, entry hours, overnight rules and resort-specific access restrictions are essential parts of the quote |

The Ballarat example proves why effective dates are mandatory: its open zone layer can carry an older $3 figure while the council's current page states $3.60 from 1 August 2026. The resolver must select the rule valid at the planned arrival time and show the source/effective date.

## Implemented coverage snapshot

The 23 August 2026 generated catalog contains:

- **3,432** records with a machine-readable tariff;
- **1,319** records with one or more schedule/rule windows;
- **2,708** records with known capacity;
- **970** records with an accessible-space count.

Tariffs currently comprise 3,131 attributed OpenStreetMap records, 291 Ballarat zone records, four Stonnington facilities, Hargreaves Street Multi-Storey Car Park in Bendigo, Hunter Werribee Public Car Park, and current official area-specific records for central Geelong 2P parking, Wangaratta paid CBD bays, free signed Horsham CBD 2P parking and Swan Hill's Curlewis Street ticketed area. City of Melbourne live-zone details also calculate the published central-CBD $7/$4 time bands and the up-to-15-minute EasyPark waiver only inside the CBD geography. The rule resolver calculates the selected plan across day boundaries, weekly tariff windows, initial free time, stepped tiers and daily caps. Unsupported conditional text is retained for the UI to say “check posted signs” rather than guessed.

## Source ladder

For each parking place, use the strongest available level and preserve all provenance:

1. **Authority meter/bay/zone service:** exact geometry plus a current rate table and effective dates.
2. **Authority current tariff page or adopted fee schedule:** convert the published rule into a reviewed ledger record linked to the source.
3. **Licensed payment/operator quote:** EasyPark, PayStay, CellOPark or garage-operator data tied to a zone, arrival and duration.
4. **Operator public booking result:** show the current quoted total and timestamp, with a deep link; never imply it is a permanent drive-up rate.
5. **OpenStreetMap `charge`, `fee`, `maxstay`, `opening_hours` and conditional tags:** useful community evidence, labelled accordingly and superseded by authority/sign data.
6. **Price estimate:** only from observed recent quotes for the same facility/product/time regime, with a range and explicit “estimated” label. A council-wide average must never be assigned to an individual bay.
7. **Unknown:** retain “check price” only when the product cannot support a narrower truthful answer.

## Internal price model

A price rule needs at least:

- place/zone/bay identifier and geometry;
- authority/operator and payment channel;
- effective-from and effective-to timestamps;
- applicable weekdays, public-holiday behavior and daily time window;
- free initial minutes;
- incremental rate bands and rounding unit;
- maximum charge/cap and maximum legal stay;
- entry/exit or overnight fee where relevant;
- taxes, card/app surcharges and reservation/drive-up distinction;
- source URL, fetched/checked time and confidence in source identity;
- posted-sign precedence and any known conflicts.

The UI should calculate the expected total for the selected arrival day/time and stay, for example:

> **$0 for 2 hours** · free 2P period applies Tuesday at 10:30 am  
> Then **$3.70/hour** in this zone · signs take precedence

or:

> **About $12–$18 for 4 hours** · recent online quotes, not a guaranteed drive-up price  
> Check live quote with provider

The first is a deterministic rule. The second is an estimate and must be visually distinct.

## Commercial and partnership paths

- **EasyPark:** broad Victorian council coverage and a commercial operator dashboard that advertises occupancy, restrictions, zoning, pricing and transaction views. A documented agreement could solve both current tariffs and transaction-history gaps for participating councils.
- **PayStay:** participating councils advertise payments and traffic-light availability. Anonymous calls did not produce a usable response, so formal access is preferable to reverse-engineered runtime dependencies.
- **CellOPark:** relevant to Ballarat and Warrnambool; council contracts/exports may provide zone/rate and transaction history.
- **Parkopedia:** licensed static/dynamic parking, prices and probability products could materially improve off-street coverage if commercial terms and Victorian accuracy are acceptable.
- **Wilson, Secure Parking and independent operators:** booking pages can support provider links and current quotes; stable ingestion requires permission or a documented partner feed.
- **MapKit place discovery:** useful for finding facilities and provider websites, but it is not a tariff source and must not invent rates.

The commercial track and public-data track should coexist. Public council rules are authoritative for public kerbside parking; operators are often the only realistic route for changing garage prices and payment transactions.

## Release checks

Before a tariff appears as current:

1. its source identity and exact geographic scope are resolved;
2. the arrival timestamp falls inside its effective and weekly rule windows;
3. a later contradictory authority source has not superseded it;
4. public-holiday and free-period behavior is known or explicitly marked unknown;
5. the total never exceeds a legal stay without warning the user;
6. deterministic tariffs, observed quotes and statistical estimates use different labels;
7. the source link and last-checked date are visible in details.

This structure lets ParkAlong show far more pricing while being safer than a generic estimate attached to every red `P` pin.
