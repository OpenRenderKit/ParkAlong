# Victoria parking prediction research

Research checkpoint: **23 August 2026 (Australia/Melbourne)**.

The product goal is not to put a decorative percentage beside a parking pin. A useful prediction must answer a driver question—such as “what is the chance at least one legal space will be available when I arrive?”—and must be allowed to abstain when the evidence cannot support that answer.

This document separates observed parking truth, inferred parking truth, demand context and uncertainty. Mixing those layers is how a confident-looking but inaccurate product is created.

## Baseline diagnosis and shipped correction

The old implementation did not calculate a statistically meaningful confidence percentage. It converted sample count into a 20–100% score, so missing history repeatedly became 20% and a large but inaccurate sample could look certain. It also selected the nearest time bucket, reused current live counts too far into the future, and emitted occupied-event buckets without explicit vacant observation states.

The shipped `melbourne-events-v3-2019-conformal` baseline removes that score entirely:

1. January–October 2019 forms the training window, November calibrates a 90% residual interval, and December is an untouched evaluation window.
2. The generator emits all 96 quarter-hour buckets for observed bay-days and labels each as `observed_occupied` or `inferred_vacant`; runtime lookup requires an exact weekday and quarter-hour match.
3. Validation records carry held-out support, normalized MAE, per-bay binary Brier score, interval coverage, interval radius, observation date and model version.
4. Numeric forecasts require at least 500 held-out bay-interval outcomes, MAE and Brier score no greater than 0.20, coverage of at least 0.80, interval radius no greater than 0.35, known capacity and observations no more than two years old.
5. Live influence decays to zero by six hours. A later arrival never inherits today's live count indefinitely.
6. A failed gate returns a specific abstention reason. Rules, price, place and walking distance remain useful while availability says unknown.

The regenerated artifact contains **225,792 quarter-hour buckets across 338 segments** and **310 held-out segment validation records**. Of those validation records, 258 pass the statistical support/error/coverage/radius gates. Median held-out normalized MAE is 0.0262, median per-bay Brier score is 0.0171, median interval coverage is 0.8972 and median interval radius is 0.0543. The newest observation is 31 December 2019, so **zero records pass the separate two-year production freshness gate in 2026**. ParkAlong therefore ships the evaluated baseline and its evidence, but correctly abstains from current numeric historical forecasts until a recent training stream is available.

The `probabilityAtLeastOne` value is a capacity-aware modelled chance derived from the expected per-bay vacancy rate under an independence assumption. Its component per-bay probability is held-out scored, but the any-space transformation is not yet directly calibrated against simultaneous segment snapshots. The UI must call it a modelled chance, disclose that assumption in model details, and never call it a measured probability or confidence.

## Data roles

### A. Direct occupancy ground truth

These sources may supply labels for training and evaluation:

| Source | Geography/time | Role | Important limitation |
| --- | --- | --- | --- |
| [City of Melbourne historical bay events](https://discover.data.vic.gov.au/dataset/on-street-car-parking-sensor-data-2019) | Annual archives 2011–2019 plus Jan–May 2020 | Primary Victorian bay-level history | Early sensor quality varies; street geometry, rules and prices changed; 2020 is COVID-affected |
| [City of Melbourne current bay sensors](https://data.melbourne.vic.gov.au/explore/dataset/on-street-parking-bay-sensors/) | Current City of Melbourne | Online forecast correction and post-deployment scoring | Only fresh recognized events are truth; missing/stale sensors are not occupied bays |
| Greater Geelong historical parking utilisation cache | 36 devices, 2020–2021; only 21 located in the audited cache | Regional external-validation candidate | COVID-heavy and deleted from the current Geelong catalogue; never present as live |
| Council occupancy surveys in Baw Baw, Wodonga, Moyne, South Gippsland, Whittlesea and other strategies | Point-in-time precinct surveys | Coarse calibration/area archetype evidence | Usually sparse days and aggregated percentages, not bay-level time series |
| [SFpark evaluation data](https://www.sfmta.com/getting-around/drive-park/demand-responsive-pricing/sfpark-evaluation) | San Francisco 2011–2013 | Excellent algorithm benchmark: sensor occupancy, payments, traffic, weather, events and street closures | Benchmark methods and failure modes only; never import San Francisco availability rates into Victoria |

The Melbourne history should be rebuilt across all usable years with explicit observation grids. For every bay and 15-minute interval, the pipeline must distinguish `occupied`, `vacant`, `sensor offline`, `bay not yet installed`, `restriction inactive` and `unknown`. An absent event must not silently become either occupied or vacant.

### B. Inferred occupancy labels

[Research on smart-meter transactions](https://arxiv.org/abs/2106.02270) shows that Particle Markov Chain Monte Carlo can estimate occupancy, arrival rates, parking duration and payment compliance, and validates the method against SFpark sensors. This is relevant to Ballarat and any council/vendor willing to share transactions.

It is not a licence to equate “paid session” with “occupied bay.” Inference must explicitly model:

- non-payment and permit users;
- early departure and overpayment;
- free periods and changing tariffs;
- loading, accessible, resident and enforcement exemptions;
- cash/card/app channels and vendor migrations;
- zone capacity and bay closures.

The sensible rollout is to train the transaction model where simultaneous sensor truth exists, measure its bias by zone/time/day, and only then use it in transaction-only areas. If the transferred model misses the council-level calibration gate, ParkAlong should show payment demand, not predicted vacancy.

### C. Demand context, not occupancy truth

These sources can explain deviations from a normal parking pattern. None may create a vacancy label by itself.

| Source | Coverage/use | Product value |
| --- | --- | --- |
| [SCATS traffic signal volume](https://discover.data.vic.gov.au/dataset/traffic-signal-volume-data) | Daily-updated 15-minute detector volumes across Victoria | Nearby vehicle-demand anomaly and event spillover feature; detector/site mapping and missing-detector limits must be handled |
| [Planned road disruptions](https://discover.data.vic.gov.au/dataset/planned-disruptions-road) and [unplanned disruptions](https://discover.data.vic.gov.au/dataset/unplanned-disruptions-road) | Near-real-time roadworks, events, incidents, lanes and expected timing | Change access/capacity/demand context; APIs require a Transport key and have freshness semantics |
| [VISTA 2021–2026](https://opendata.transport.vic.gov.au/dataset/victorian-integrated-survey-of-travel-and-activity-vista?v=2) | Statewide annual household/person/trip/stop files, including car-park and on-street place types | Regional travel and parking-purpose priors; survey weights and coarse geography are mandatory |
| [Victorian PTAL](https://www.planning.vic.gov.au/guides-and-resources/guides/all-guides/car-parking-requirements) | 82 municipality maps and a queryable metro/regional map service | Structural prior for car dependence and expected demand; annual planning measure, not real-time state |
| [Vicmap Features of Interest](https://discover.data.vic.gov.au/en_AU/dataset/vicmap-features-of-interest-rest-api) | Weekly statewide schools, hospitals, universities, sports, tourism and community venues | Consistent destination archetypes and walking catchments beyond OSM |
| [ABS Census Mesh Block counts](https://www.abs.gov.au/census/guide-census-data/mesh-block-counts/latest-release) and [Census DataPacks](https://www.abs.gov.au/census/find-census-data/datapacks) | Population, dwellings, working population, travel-to-work and small-area land-use context | Stable residential/employment baseline; never a current occupancy signal |
| [SILO climate API](https://www.data.qld.gov.au/dataset/silo-climate-api) | Australian daily weather from 1889 to yesterday, CC BY 4.0; API key required | Long aligned history for rain/temperature effects |
| [ERA5 hourly reanalysis](https://cds.climate.copernicus.eu/datasets/reanalysis-era5-single-levels?tab=download) | Hourly 1940–present, CC BY | Historical weather when station data is incomplete; roughly 31 km context is coarse for local showers |
| WeatherKit/Bureau of Meteorology forecasts | Current and future weather | Arrival-time correction after the historical model is established |
| Victorian public/regional holidays and school terms | State and region-specific calendar rules | Essential for commuter, school, beach and retail demand; substitute/local holidays must be encoded |
| Ticketmaster, Australian Tourism Data Warehouse, council event feeds and venue calendars | Scheduled events | Venue/time/radius event intensity; missing event listings must mean “unknown,” not “no event” |
| PTV station patronage and timetables | Station demand and service frequency | Strong station-carpark pattern input; does not measure spare parking spaces |
| Parks Victoria counters, airport statistics, alpine visitation/snow reports | Tourism gateways and seasonal destinations | Regional/tourism demand context where urban sensor transfer is weakest |

### D. Rules, prices and capacity

Availability is not useful if the space is illegal for the requested stay. The rule engine therefore needs a separate versioned truth ledger:

- geometry and capacity;
- day-of-week and date ranges;
- start/end times, including overnight intervals;
- maximum stay and no-return rules;
- price schedules, free periods, caps and payment provider;
- public-holiday behavior;
- permit/loading/accessible/vehicle exceptions;
- effective-from/effective-to dates and source precedence.

[OpenStreetMap parking tags](https://wiki.openstreetmap.org/wiki/Key:parking) such as `maxstay`, `charge`, `opening_hours` and `*:conditional` can fill gaps, but posted signs and current authority sources remain higher priority. Wodonga's public service is an especially useful schema example because one polygon can contain multiple day/time/vehicle/permit rules.

For interoperability, the internal model should borrow the concepts in the [Alliance for Parking Data Standards specification](https://github.com/parkingdata/spec): places, rights, rates, observations and quotes. ParkAlong does not need to expose the entire standard on day one, but it should avoid flattening a weekly rate table into one timeless string.

## Candidate model ladder

The model should become more sophisticated only when the data can support it.

### Level 0 — observed state

Show fresh sensor count and age. No prediction is needed for “now” unless correcting for a short drive ETA. Source health and sensor coverage are shown separately from forecast uncertainty.

### Level 1 — calibrated seasonal baseline

For each observed zone, estimate occupancy by local time, weekday, date season and restriction regime using hierarchical shrinkage. Sparse zones borrow strength from their precinct/council/archetype, but their intervals widen. This is interpretable, difficult to overfit and establishes the minimum baseline every later model must beat.

### Level 2 — live-informed tabular forecast

Add current occupancy, recent arrivals/departures, ETA, weather, traffic, events, price, max stay, holidays and nearby-zone state. Gradient-boosted probability/count models are a strong practical candidate because missing features can be handled and feature effects can be audited.

### Level 3 — spatiotemporal graph forecast

Once multiple connected Victorian zones have long histories, test a graph model that learns spillover between nearby streets, garages and destinations. Published parking work shows graph/recurrent models can combine parking transactions, traffic and weather, but complexity is justified only if rolling and geographic holdouts beat Level 2.

### Transaction-only transfer model

Keep this as a parallel model class. It estimates latent occupancy from payments and compliance, is calibrated where both sensors and transactions exist, and must pass a council-specific transfer gate before producing numeric vacancy elsewhere.

## Validation and abstention contract

Every model version should have a signed model card with training windows, included councils, feature availability, evaluation splits and known incidents. Required evaluation:

1. **Rolling-origin holdouts:** train only on the past and predict future weeks/months. Random row splitting leaks time patterns and is not acceptable.
2. **Geographic holdouts:** hold out entire zones, precincts and councils to measure whether regional transfer actually works.
3. **Incident holdouts:** separately score holidays, school breaks, major events, severe weather, road closures and post-price-change periods.
4. **Baselines:** beat last-observation, same-time-last-week and hierarchical seasonal baselines.
5. **Count accuracy:** MAE plus quantile/pinball loss for predicted available-space ranges.
6. **Driver probability:** Brier score and reliability diagrams for `P(at least one legal space at arrival)` and `P(at least three)`.
7. **Interval honesty:** empirical coverage and average width. A claimed 80% interval should contain the result about 80% of the time in each supported cohort, not only statewide on average.
8. **Ranking utility:** top recommendation success, legal-at-arrival rate, walking distance and regret versus the best visible legal option.
9. **Freshness/health:** source delay, missing-sensor share, geometry match rate and restriction-rule coverage are measured separately.

Time-series conformal methods such as [Adaptive Conformal Prediction](https://proceedings.mlr.press/v162/zaffran22a.html), [Sequential Predictive Conformal Inference](https://proceedings.mlr.press/v202/xu23r) and [multi-step ACI](https://proceedings.mlr.press/v230/hallberg-szabadvary24a.html) are appropriate candidates for turning model residuals into arrival-horizon intervals under drift. They do not rescue a bad point model or missing ground truth; they quantify observed error when used and monitored correctly.

ParkAlong should abstain from numeric availability when any of these is true:

- no direct or validated inferred occupancy labels for the cohort;
- current rules cannot establish legality for the requested arrival/stay;
- capacity is unknown for a count prediction;
- sensor health or source age fails the acceptance rule;
- held-out probability calibration or interval coverage misses its release threshold;
- the request is materially outside the training distribution.

Abstention is not a blank product. It can still show verified location, legal time window, current price, walking distance and a clearly labelled qualitative demand outlook.

## Product-facing forecast states

Use mutually honest states instead of one purple estimate with an unexplained percentage:

| State | What ParkAlong may say | Minimum evidence |
| --- | --- | --- |
| Live now | “8 of 10 available · updated 45 sec ago” | Fresh recognized bay states and trusted denominator |
| Live-informed forecast | “Likely 3–6 spaces at 7:20 pm · modelled 78% chance of at least one” | Live state plus a held-out calibrated ETA model |
| Historical forecast | “Usually 1–4 spaces around this time” | Sufficient comparable history and interval coverage, but no fresh state |
| Demand outlook | “Usually busy after school pickup” | Corroborated survey/context evidence without validated vacancy labels |
| Location/rules only | “Availability unknown · 2P until 6:30 pm · $2.40/hr” | Verified location and current rule/price data |

The displayed chance is a model output with a measurement date, supported horizon and stated assumptions. “Source quality: high/medium/low” is a separate explanation. Neither should be called a generic confidence percentage.

## Sensible statewide strategy

Victoria-wide does not mean pretending every council has Melbourne-quality labels. It means one product contract with area-specific adapters and graceful evidence levels:

1. train and rigorously calibrate the full pipeline in Melbourne;
2. validate transaction inference in any zone where payments and sensors overlap;
3. use regional surveys and Geelong history for external validation, not blind transfer;
4. build council/archetype priors from VISTA, PTAL, POIs, Census and published studies;
5. allow numeric forecasts only for cohorts that meet the release gates;
6. continuously score live forecasts against subsequently observed sensor truth;
7. widen intervals or automatically demote a model to demand-outlook/unknown when calibration drifts.

This makes prediction an A-class part of the product precisely because it treats evidence, evaluation and abstention as product features rather than caveats hidden in an About sheet.
