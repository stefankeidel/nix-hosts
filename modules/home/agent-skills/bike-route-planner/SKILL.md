---
name: bike-route-planner
description: Plan cycling routes with BRouter/bikerouter.de, generate clickable route-review links and GPX files, and—after one explicit route approval—hand the course to Garmin Connect. Trigger for cycling route planning, BRouter, bikerouter.de links, cycling GPX creation, or sending an approved course to Garmin.
---

# Bike route planner

Use the BRouter tools for deterministic routing and this workflow for conversation, judgment, and approval boundaries. BRouter/OSM data, trail access, closures, and duration estimates can be stale or incomplete. A route is not a safety, legality, or weather guarantee; encourage review of the map, closures, legal access, weather, and current trail conditions where relevant.

## 1. Gather only missing constraints

Infer what is already supplied. For a normal request, ask only for missing essentials:

- start location and whether the route is a closed loop or has a destination;
- target distance and acceptable tolerance for a loop;
- style: `gravel`, `trekking`, `road`, or an explicit BRouter profile;
- optional via places, desired initial direction, surfaces/roads/ferries/areas to avoid;
- whether the user wants a retained GPX copy.

Use sensible defaults: BRouter's default alternative index is 0, a loop normally gets up to three candidates, and a requested profile alias is accepted. Translate an avoided area into a no-go circle only after obtaining a sensible center and radius. Do not claim that a profile guarantees a surface or access condition.

## 2. Resolve locations safely

- Accept explicit `longitude,latitude` coordinates and existing bikerouter.de links directly. BRouter is longitude first.
- For free text call `brouter_geocode`. It uses public Nominatim only for this request and returns candidates without persistence.
- If candidates are materially different, ask the user to choose; do not silently choose one.
- Confirm a surprising or potentially sensitive start-location match before routing.

## 3. Plan and review

### Closed loop

Call `brouter_roundtrip_candidates` with the confirmed start, target distance, profile, and supplied constraints. It routes candidates sequentially with a bounded public-service request budget. Each result includes a reproducible route specification and a `bikerouter.de` review link.

### Point-to-point or via points

Call `brouter_route` with the ordered, confirmed waypoints. Include no-go circles, initial heading, profile parameters, or an alternative index only when requested or when they are the agreed route revision.

Present each useful candidate concisely:

- short identifying name;
- distance, filtered ascent, and BRouter **estimated** duration;
- meaningful surface/path composition and warnings (not the raw message table);
- a clickable bikerouter.de review link.

State that message-distance percentages are based on tagged/analyzed segments and that BRouter/OSM warnings require inspection. Do not overwhelm the user with raw response geometry or tables.

## 4. Iterate without losing reproducibility

Keep and reuse the `routeSpecification` returned in tool details. Translate feedback such as “10 km shorter”, “more gravel”, “avoid that road”, or “head east first” into an explicit revised target, profile, no-go circle, waypoint, heading, or alternative index. Generate a revised review link and repeat.

Never rely solely on a candidate ID. Before finalizing, ensure the selected normalized specification is exactly the one the user inspected and approved.

## 5. Route approval, GPX, and Garmin handoff (one boundary)

Do **not** call `brouter_download_gpx` merely because a candidate exists or a link was opened. First obtain one explicit approval of the selected route. The approval question must make the consequence clear, for example: “Approve Loop 2? It will be uploaded to Garmin as `YYYY-MM-DD <shortname>` with type `gravel_cycling`.”

Use `YYYY-MM-DD <shortname>` as the default course-name schema, using the current date and a concise route name. Use an appropriate type (usually `gravel_cycling` for gravel, otherwise an appropriate cycling type). The user may override either value before approving.

That route approval authorizes all of the following:

1. Call `brouter_download_gpx` using the exact approved `routeSpecification` and course name. Omit `outputPath` for a temporary GPX. Provide `outputPath` only when the user asks to retain a copy.
2. Check that the returned specification still matches the approved candidate. The tool validates GPX before writing it.
3. Load and follow the `garmin-connect` skill. Run `gccli auth status`, then import with `gccli courses import <gpx-path> --name <name> --type <type>`.
4. Obtain the created course ID and query devices in JSON form: `gccli devices list --json` (or the CLI's supported JSON equivalent).
5. Automatically select a device only if **exactly one** device matches `Edge 540`. If none or multiple match, present the candidates and ask the user which device to use; this is device selection, not a further approval boundary.
6. Send the course with `gccli courses send <course-id> <device-id>`, then report the course ID and send result.
7. Delete a temporary GPX only after successful import. If import fails, retain it and report the path. Never delete a user-requested retained copy.

Do not delete or replace existing Garmin courses automatically.
