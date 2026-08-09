---
name: bike-route-planner
description: Plan cycling routes with BRouter/bikerouter.de, generate clickable route-review links and GPX files, and—only after separate confirmations—hand an approved course to Garmin Connect. Trigger for cycling route planning, BRouter, bikerouter.de links, cycling GPX creation, or sending an approved course to Garmin.
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

## 5. Route approval and GPX (first boundary)

Do **not** call `brouter_download_gpx` merely because a candidate exists or a link was opened. First obtain an explicit approval of the selected route, for example: “I approve Loop 2.”

After approval:

1. Confirm the desired Garmin course name and propose an appropriate type (usually `gravel_cycling` for gravel, otherwise an appropriate cycling type).
2. Call `brouter_download_gpx` using the exact approved `routeSpecification`, with the confirmed course name. Omit `outputPath` for a temporary GPX. Provide `outputPath` only when the user asks to retain a copy.
3. Check the returned specification still matches the approved candidate. The tool validates GPX before writing it.
4. Show the course name, proposed type, approximate distance, path, and intended device. A GPX download is **not** authorization to mutate Garmin.

Temporary GPX files must be retained until Garmin import succeeds. A retained requested copy is never deleted automatically.

## 6. Garmin handoff (second boundary)

Only after a separate, explicit final confirmation that names the course/type and authorizes Garmin import/send, load and follow the `garmin-connect` skill. Then:

1. Run `gccli auth status`.
2. Import: `gccli courses import <gpx-path> --name <name> --type <type>`.
3. Obtain the created course ID from the result.
4. Query devices in JSON form: `gccli devices list --json` (or the CLI's supported JSON equivalent).
5. Automatically select a device only if **exactly one** device matches `Edge 540`. If none or multiple match, present the candidates and ask the user which device to use.
6. Send: `gccli courses send <course-id> <device-id>`.
7. Report the course ID and send result.
8. Delete a temporary GPX only after successful import. If import fails, retain it and report the path. Never delete a user-requested retained copy.

Do not delete or replace existing Garmin courses automatically.
