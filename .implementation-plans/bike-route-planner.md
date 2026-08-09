# Bike route planner for Pi

## Status

Approved plan. Implementation has not started.

## Goal

Add a Pi capability that plans cycling routes through the public BRouter instance at `https://bikerouter.de/brouter-engine/brouter`, presents clickable bikerouter.de links for iterative review, and—after explicit approval—downloads the selected route as GPX, imports it into Garmin Connect, and sends it to an Edge 540.

Typical requests include:

- A closed gravel loop starting at a named place with a target distance.
- A trekking route between two locations with optional via points.
- A road route with a preferred initial direction or areas to avoid.
- Iterative changes such as “make it 10 km shorter”, “more gravel”, or “avoid that road”.

## Architecture decision

Implement this as a hybrid:

1. A **Pi extension** provides deterministic BRouter HTTP operations, route analysis, URL generation, candidate generation, and GPX download.
2. A **bike-route-planner skill** defines the conversational planning workflow, review loop, approval boundaries, and handoff to the existing `garmin-connect` skill.

The extension is responsible for mechanics and structured data. The skill is responsible for judgment and user interaction. Garmin operations remain in the existing Garmin skill rather than being coupled into the BRouter extension.

## Accepted defaults

- Support both closed round trips and point-to-point routes with optional via points in v1.
- Use public OpenStreetMap Nominatim for free-text geocoding, with a descriptive User-Agent, conservative rate limiting, and no persistence of locations.
- Friendly profile aliases:
  - `gravel` → `cxb-gravel`
  - `trekking` → `trekking`
  - `road` → `fastbike`
- Also permit an explicit BRouter profile name so the extension is not limited to the aliases.
- For a target-length round trip, initially generate three candidates and aim for approximately ±10% of the requested distance.
- Include no-go circles and an initial heading in v1. Defer weighted polygons and weighted polylines unless implementation experience shows they are needed.
- Automatically select the Garmin device when exactly one device matches `Edge 540`; ask the user if zero or multiple devices match.
- Store GPX files in a temporary directory by default and remove them after successful Garmin import. Allow the user to request retaining a copy.
- Route approval authorizes the final GPX download, but Garmin import/send requires a separate final confirmation showing the course name and type.

## Authoritative references

Use upstream BRouter source as the API authority:

- Repository: `https://github.com/abrensch/brouter`
- HTTP parameters: `brouter-server/src/main/java/btools/server/request/ServerHandler.java`
- GeoJSON format: `brouter-core/src/main/java/btools/router/FormatJson.java`
- Profile examples: `misc/profiles2/`

The upstream repository defines the protocol and bundled profiles. The bikerouter.de deployment may expose additional profiles such as `cxb-gravel`; therefore profile validation must not be restricted to the upstream profile filenames.

Relevant confirmed BRouter parameters include:

- `lonlats=lon,lat|...`
- `profile=<profile-name>`
- `alternativeidx=0|1|2|3`
- `format=gpx|geojson|kml|csv`
- `nogos=lon,lat,radius,weight|...`
- `heading=<angle>`
- `trackname=<name>`
- `exportWaypoints=1`
- `exportCorrectedWaypoints=1`
- `timode=<mode>`
- `profile:<name>=<value>`
- `straight=<waypoint indexes>`
- `pois=lon,lat,name|...`

## Planned repository changes

### Pi extension

Create:

- `modules/home/pi-extensions/brouter.ts`

Register it in:

- `modules/home/pi.nix`

Place it before `stefan-path-protection.ts`, which must remain last.

The extension should use built-in `fetch` and Pi APIs and avoid adding an npm dependency unless a concrete need emerges.

### Agent skill

Create:

- `modules/home/agent-skills/bike-route-planner/SKILL.md`

Install it through Home Manager in:

- `modules/home/home-darwin.nix`

The skill description must clearly trigger for cycling route planning, BRouter, bikerouter.de links, cycling GPX creation, and sending an approved course to Garmin.

## Extension tool design

Prefer several focused tools registered by one extension over one tool with many optional, conditionally required fields.

### `brouter_geocode`

Purpose: Resolve a free-text place or address to candidate coordinates.

Inputs:

- Query text.
- Optional result limit with a small maximum.

Behavior:

- Query Nominatim only when free-text geocoding is needed.
- Send a descriptive User-Agent.
- Rate-limit requests and use a bounded timeout.
- Return a compact list containing display name, longitude, latitude, type/category, and bounding box when available.
- Never persist the query or result.
- Make ambiguity visible so the skill can ask the user to choose rather than silently selecting the wrong place.

### `brouter_route`

Purpose: Route ordered points and analyze the result.

Inputs for v1:

- Ordered waypoints containing longitude, latitude, and optional label.
- Profile alias or explicit profile name.
- Alternative index, defaulting to 0.
- Optional no-go circles.
- Optional initial heading.
- Optional profile parameters.
- Optional track name.
- Optional exported/corrected waypoints when useful for diagnostics.

Validation:

- Require at least two waypoints.
- Validate finite longitude and latitude ranges.
- Restrict alternative index to 0–3.
- Validate no-go radii and weights.
- Validate profile names and profile-parameter keys against a conservative character allow-list without restricting them to a hard-coded catalog.
- Reject malformed or unexpectedly large requests before network access.

Behavior:

- Request GeoJSON from BRouter.
- Apply a timeout and the tool cancellation signal.
- Parse the route feature defensively, including numeric values encoded as strings.
- Return a concise human- and model-readable summary plus structured details.
- Do not place the complete route geometry or raw response in model-visible output by default.
- Produce both the exact API request specification and a clickable bikerouter.de review link.
- Clearly report BRouter errors, unsupported profiles, unroutable points, and timeout/rate-limit failures.

Summary fields:

- Profile and alternative index.
- Distance in kilometers.
- Filtered ascent in meters.
- Estimated BRouter duration, clearly labeled as an estimate.
- Energy and cost when present, without presenting them as universal physical measurements.
- Surface breakdown by distance and percentage.
- Highway/path-type breakdown.
- Track-grade and smoothness breakdown when tagged.
- Notable barriers, access restrictions, steep inclines, and difficult MTB/sac-scale sections.
- Requested and corrected waypoint information when available.

### `brouter_roundtrip_candidates`

Purpose: Create closed-loop candidates from a start point and target distance.

Inputs:

- Start longitude/latitude.
- Target distance in kilometers.
- Profile alias or explicit profile.
- Optional preferred heading/direction.
- Optional no-go circles.
- Optional profile parameters.
- Candidate count, default and initial maximum 3.

Candidate algorithm:

1. Generate differently oriented triangular or quadrilateral waypoint patterns around the start.
2. Scale the initial waypoint radius from the requested route length.
3. Route each pattern as an ordered closed loop through BRouter.
4. Compare actual routed distance with the target and rescale once or twice within a strict request budget.
5. Analyze candidate geometry for excessive coordinate/segment reuse as a proxy for doubling back.
6. Rank candidates by:
   - absolute target-distance deviation;
   - profile-relevant surface composition;
   - amount of doubling back;
   - barriers, access restrictions, and difficult surfaces;
   - successful routability.
7. Return the best three distinct candidates with summaries and individual review links.

Operational constraints:

- Keep the number of BRouter requests bounded and conservative because this is a public service.
- Do not run an open-ended optimization loop.
- Stream brief progress updates without exposing raw responses.
- Treat generated loops as suggestions requiring user inspection, not guaranteed scenic or safe routes.

### `brouter_download_gpx`

Purpose: Download the exact approved route as a GPX file.

Inputs:

- The same route specification used for the approved candidate: ordered waypoints, resolved profile, alternative index, no-go circles, heading, and profile parameters.
- Sanitized track/course name.
- Optional requested output path; absent means a temporary directory.

Behavior:

- Reconstruct the request from structured inputs rather than accepting an arbitrary URL.
- Request `format=gpx` and set `trackname`.
- Validate the response and reject HTML/error payloads masquerading as successful downloads.
- Use Pi’s file-mutation queue when writing a user-selected persistent path.
- Return the file path, whether it is temporary, and the normalized route specification.
- Do not import or send the route to Garmin; that remains a skill workflow step.

## Bikerouter review links

Implement review-link generation separately from API URL generation and cover it with tests. The link must open bikerouter.de with:

- all ordered route points;
- the selected profile;
- an appropriate map center and zoom;
- the existing standard/gravel-overlay presentation when suitable.

Verify the exact fragment syntax against the deployed BRouter-web frontend rather than assuming API `lonlats` syntax and browser permalink syntax are identical.

## GeoJSON analysis

BRouter’s GeoJSON route feature exposes properties including:

- `track-length`
- `filtered ascend`
- `plain-ascend`
- `total-time`
- `total-energy`
- `cost`
- `messages`
- `times`

The first `messages` row is a header. Subsequent rows contain aggregate route-segment information such as distance and `WayTags`. Parse columns by header name rather than hard-coded numeric indexes wherever practical.

Parse `WayTags` as whitespace-separated key/value tags, while tolerating unknown or missing tags. Aggregate each message row’s `Distance` into categories such as:

- exact `surface` values;
- exact `highway` values;
- `tracktype`;
- `smoothness`;
- barriers/access tags;
- incline and difficulty tags.

Keep exact-tag breakdowns in structured details. A higher-level paved/unpaved/unknown summary may be added, but it must be presented as a derived classification and retain categories such as cobblestone rather than hiding them.

The sum of message distances may not perfectly equal `track-length`; report percentages against the analyzed message distance and tolerate rounding differences.

## Skill workflow

The skill should implement the following dialogue.

### 1. Gather constraints

Ask only for information not already supplied:

- start location;
- round trip or destination;
- target distance and acceptable tolerance;
- gravel, trekking, road, or explicit profile;
- optional via places;
- preferred direction/heading;
- surfaces, roads, ferries, or areas to avoid;
- whether a retained GPX copy is desired.

Use sensible defaults rather than presenting a long questionnaire for every request.

### 2. Resolve locations

- Accept coordinates and bikerouter.de links directly.
- Geocode free-text places through `brouter_geocode`.
- Ask the user to disambiguate materially different matches.
- Confirm potentially sensitive or surprising start-point matches before routing.

### 3. Generate and present candidates

For each candidate, show:

- a short identifying name;
- distance and ascent;
- estimated duration;
- meaningful surface/path composition;
- warnings or notable sections;
- a clickable bikerouter.de link.

Do not overwhelm the user with the raw BRouter message table.

### 4. Iterate

Translate feedback into route changes, for example:

- change target distance;
- shift via points;
- favor a direction;
- add a no-go circle;
- choose another profile or alternative index;
- reduce difficult or paved segments.

Generate revised links and continue until the user explicitly approves one route.

### 5. Finalize GPX

After route approval:

- Confirm the desired Garmin course name.
- Choose an appropriate Garmin course type such as `gravel_cycling`, with the proposed value shown to the user.
- Download the exact approved route with `brouter_download_gpx`.
- Show the course name, type, approximate distance, and intended device.
- Request a separate final confirmation before Garmin import/send.

### 6. Garmin handoff

After final confirmation, load and follow the `garmin-connect` skill:

1. Verify authentication with `gccli auth status`.
2. Import the GPX with `gccli courses import <path> --name <name> --type <type>`.
3. Obtain the created course ID.
4. Query devices using JSON output.
5. Select the device automatically only if exactly one device matches `Edge 540`; otherwise ask the user.
6. Send the course with `gccli courses send <course-id> <device-id>`.
7. Report the course ID and send result.
8. Delete a temporary GPX only after successful import. Retain it and report its path if import fails or the user requested a copy.

Do not delete or replace existing Garmin courses automatically.

## Safety, privacy, and service etiquette

- Route suggestions are not safety guarantees. Encourage checking closures, legal access, weather, and current trail conditions when relevant.
- Treat BRouter estimates and OSM tags as potentially stale or incomplete.
- Never persist geocoded home/start locations in extension state, logs, memory, or repository files.
- Use HTTPS, timeouts, cancellation, a descriptive User-Agent where applicable, and bounded retries.
- Avoid high-volume parallel calls to public BRouter and Nominatim instances.
- Require explicit route approval before GPX finalization and explicit final confirmation before Garmin mutation.
- Sanitize track names and file names.
- Truncate all model-visible tool output according to Pi extension guidance.

## State and reproducibility

The approved route must be reproducible from a normalized route specification containing:

- resolved profile name;
- ordered waypoints;
- alternative index;
- no-go circles;
- heading;
- profile parameters;
- track name where applicable.

Return this specification in tool-result details so it survives session branching. Do not rely solely on an opaque in-memory candidate ID. Before GPX download, compare the selected specification to the approved candidate to avoid silently downloading a later revision.

## Testing plan

### Unit tests or independently executable parser checks

Use saved, sanitized fixtures rather than relying exclusively on the live service.

Cover:

- API query encoding for multiple waypoints and pipe separators.
- Profile aliases and explicit profile names.
- No-go circles, heading, alternative index, track name, and profile parameters.
- Bikerouter review-link generation.
- Parsing numeric string properties.
- Header-driven parsing of `messages`.
- Surface, highway, track-type, and smoothness aggregation.
- Missing fields, unknown tags, malformed GeoJSON, and BRouter error responses.
- GPX response/content validation and track-name sanitization.
- Round-trip ranking and request-budget enforcement with mocked route results.

If the repository has no suitable TypeScript test runner, keep pure parsing and URL-building functions isolated and add a small deterministic test harness that can be run through the available Pi/Node environment without introducing an unpinned dependency.

### Live smoke tests

- Route the example coordinates with `cxb-gravel` and compare distance/ascent to the live response.
- Open the generated review link and verify waypoints and profile.
- Generate a short round-trip candidate set and verify that request count remains bounded.
- Download a GPX and validate that it is parseable XML containing a track.
- Do not import to Garmin during an automated or unapproved smoke test.

### Repository validation

- Run formatting/type checks available to Pi extensions.
- Run `nix flake check`.
- Build or activate the relevant Home Manager configuration if feasible.
- Start/reload Pi and verify that the new tools and skill are discovered.

## Acceptance criteria

The implementation is complete when:

1. A user can request a route using a named start, desired length, and cycling style.
2. The workflow resolves the location safely and generates up to three useful candidates for round trips.
3. Each candidate includes a concise composition summary and a working bikerouter.de review link.
4. Point-to-point routes with optional via points work.
5. User feedback can revise the route without losing the exact route specification.
6. No-go circles and initial heading are supported.
7. An approved route can be downloaded as valid GPX.
8. Garmin import/send occurs only after a separate final confirmation.
9. Exactly one matching Edge 540 is selected automatically; ambiguous device matches are presented to the user.
10. Temporary GPX cleanup follows the agreed success/failure behavior.
11. Tests cover URL construction, parsing, analysis, and failure handling.
12. `nix flake check` passes, or any unrelated existing failure is clearly documented.

## Deferred work

- Weighted no-go polygons and polylines.
- Rich custom TUI map rendering; browser links are the v1 review mechanism.
- Self-hosting BRouter or caching OSM routing data locally.
- Persisting favorite start points or personal route preferences.
- Automatic scenic-quality claims or safety scoring.
- Automatic deletion/replacement of Garmin courses.
