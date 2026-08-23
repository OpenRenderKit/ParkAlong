# Victoria parking prediction research

Research checkpoint: **23 August 2026 (Australia/Melbourne)**.

The product goal is not to put a decorative percentage beside a parking pin. A useful prediction must answer a driver question—such as “what is the chance at least one legal space will be available when I arrive?”—and must be allowed to abstain when the evidence cannot support that answer.

This document separates observed parking truth, inferred parking truth, demand context and uncertainty. Mixing those layers is how a confident-looking but inaccurate product is created.

## Current implementation diagnosis

The existing code does not calculate a statistically meaningful confidence percentage:

1. `PredictionEngine.estimate` calculates confidence as `sqrt(sampleCount / 500)`, clamped to 20–100%. It never checks whether past predictions were correct. Five hundred samples therefore produce 100% even if the model is badly calibrated.
2. When a historical bucket is absent, the live path passes `sampleCount = 0`, which always becomes 20%. That is why 20% appears repeatedly.
3. The live-versus-history weight is a hand-written ETA curve, not a learned decay based on how quickly each zone changes.
4. `historicalProfile` chooses the nearest time bucket. It does not impose a maximum time gap or record that the requested bucket was missing.
5. The bundled history uses only Melbourne 2019. The source archive is valuable, but one year cannot represent post-pandemic travel, changed prices, changed streets or regional Victoria.
6. The history generator emits keys only when an arrival or occupied interval exists. In the current artifact there are **225,390 buckets across 338 street segments, but no bucket has `occupiedRatio == 0`**. Missing empty intervals can be replaced by the nearest occupied interval at runtime, systematically biasing estimates toward “busy.” There are also 11,760 exactly-100%-occupied buckets, so the saturation needs sensor-coverage and denominator audits.
7. `sampleCount` is currently derived as inferred capacity multiplied by observed days. That is exposure, not independent evidence, and it should not be converted directly into probability confidence.
8. The static estimator contains sensible product guards—known capacity, at least 100 samples and a calibration-error field no worse than 10%—but the occupancy adjustments are hand-set archetype rules. They are hypotheses to test, not learned Victorian effects.

The immediate product conclusion is simple: remove the fake universal “confidence %” concept. Replace it with a measured probability and interval only when rolling held-out tests support them; otherwise show a qualitative demand signal or “availability unknown.”

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
| Live-informed forecast | “Likely 3–6 spaces at 7:20 pm · 78% chance of at least one” | Live state plus a held-out calibrated ETA model |
| Historical forecast | “Usually 1–4 spaces around this time” | Sufficient comparable history and interval coverage, but no fresh state |
| Demand outlook | “Usually busy after school pickup” | Corroborated survey/context evidence without validated vacancy labels |
| Location/rules only | “Availability unknown · 2P until 6:30 pm · $2.40/hr” | Verified location and current rule/price data |

The displayed probability is a model output with a measurement date and supported horizon. “Source quality: high/medium/low” is a separate explanation. Neither should be called a generic confidence percentage.

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
