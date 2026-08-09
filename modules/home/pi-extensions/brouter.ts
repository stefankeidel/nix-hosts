import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { withFileMutationQueue } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { lstat, mkdtemp, realpath, writeFile } from "node:fs/promises";
import { basename, dirname, isAbsolute, relative, resolve } from "node:path";
import { tmpdir } from "node:os";

const BROUTER_URL = "https://bikerouter.de/brouter-engine/brouter";
const NOMINATIM_URL = "https://nominatim.openstreetmap.org/search";
const USER_AGENT = "nix-hosts-pi-bike-route-planner/1.0 (personal route planning)";
const PROFILE_ALIASES: Record<string, string> = {
	gravel: "cxb-gravel",
	trekking: "trekking",
	road: "fastbike",
};
const MAX_WAYPOINTS = 12;
const MAX_PROFILE_PARAMETERS = 20;
const MAX_REQUEST_BYTES = 8_000;
const MAX_GPX_BYTES = 5_000_000;
let lastGeocodeAt = 0;
let geocodeQueue: Promise<void> = Promise.resolve();

const waypointSchema = Type.Object({
	longitude: Type.Number({ description: "Longitude in WGS84 degrees (-180 to 180)" }),
	latitude: Type.Number({ description: "Latitude in WGS84 degrees (-90 to 90)" }),
	label: Type.Optional(Type.String({ maxLength: 120, description: "Optional human-readable waypoint label" })),
});
const noGoSchema = Type.Object({
	longitude: Type.Number({ description: "Circle center longitude" }),
	latitude: Type.Number({ description: "Circle center latitude" }),
	radius: Type.Number({ description: "Circle radius in metres" }),
	weight: Type.Optional(Type.Number({ description: "BRouter no-go weight; defaults to infinity" })),
});
const routeInputSchema = Type.Object({
	waypoints: Type.Array(waypointSchema, { minItems: 2, maxItems: MAX_WAYPOINTS, description: "Ordered route points" }),
	profile: Type.String({ description: "gravel, trekking, road, or an explicit BRouter profile name" }),
	alternativeIndex: Type.Optional(Type.Integer({ minimum: 0, maximum: 3, description: "BRouter alternativeidx, default 0" })),
	noGoCircles: Type.Optional(Type.Array(noGoSchema, { maxItems: 10 })),
	heading: Type.Optional(Type.Number({ minimum: 0, maximum: 359.999, description: "Initial heading in degrees" })),
	profileParameters: Type.Optional(Type.Record(Type.String(), Type.Union([Type.String(), Type.Number(), Type.Boolean()]), { maxProperties: MAX_PROFILE_PARAMETERS })),
	trackName: Type.Optional(Type.String({ maxLength: 120 })),
	exportWaypoints: Type.Optional(Type.Boolean()),
	exportCorrectedWaypoints: Type.Optional(Type.Boolean()),
});
const roundtripSchema = Type.Object({
	start: waypointSchema,
	targetDistanceKm: Type.Number({ exclusiveMinimum: 1, maximum: 500, description: "Requested loop distance in km" }),
	profile: Type.String({ description: "gravel, trekking, road, or an explicit BRouter profile name" }),
	heading: Type.Optional(Type.Number({ minimum: 0, maximum: 359.999 })),
	noGoCircles: Type.Optional(Type.Array(noGoSchema, { maxItems: 10 })),
	profileParameters: Type.Optional(Type.Record(Type.String(), Type.Union([Type.String(), Type.Number(), Type.Boolean()]), { maxProperties: MAX_PROFILE_PARAMETERS })),
	candidateCount: Type.Optional(Type.Integer({ minimum: 1, maximum: 3 })),
});
const downloadSchema = Type.Intersect([
	routeInputSchema,
	Type.Object({
		trackName: Type.String({ minLength: 1, maxLength: 120, description: "Course name; it is sanitized for GPX and file names" }),
		outputPath: Type.Optional(Type.String({ maxLength: 1_000, description: "Optional persistent output file path; absent writes a temporary GPX" })),
	}),
]);

export type Waypoint = { longitude: number; latitude: number; label?: string };
export type NoGoCircle = { longitude: number; latitude: number; radius: number; weight?: number };
export type RouteSpec = {
	waypoints: Waypoint[];
	profile: string;
	alternativeIndex: number;
	noGoCircles: NoGoCircle[];
	heading?: number;
	profileParameters: Record<string, string | number | boolean>;
	trackName?: string;
	exportWaypoints?: boolean;
	exportCorrectedWaypoints?: boolean;
};

type JsonRecord = Record<string, unknown>;
type Breakdown = Record<string, { distanceMeters: number; percent: number }>;

export type RouteAnalysis = {
	distanceKm?: number;
	ascentM?: number;
	durationSeconds?: number;
	energy?: number;
	cost?: number;
	analyzedDistanceMeters: number;
	surface: Breakdown;
	highway: Breakdown;
	tracktype: Breakdown;
	smoothness: Breakdown;
	warnings: string[];
};

function finiteNumber(value: unknown, name: string): number {
	const numeric = typeof value === "number" ? value : typeof value === "string" ? Number(value) : NaN;
	if (!Number.isFinite(numeric)) throw new Error(`${name} must be a finite number.`);
	return numeric;
}

function nonEmptyString(value: unknown, name: string, maximum = 200): string {
	if (typeof value !== "string" || !value.trim() || value.length > maximum) throw new Error(`${name} must be a non-empty string of at most ${maximum} characters.`);
	return value.trim();
}

function validateCoordinate(point: Waypoint, name: string): Waypoint {
	const longitude = finiteNumber(point.longitude, `${name}.longitude`);
	const latitude = finiteNumber(point.latitude, `${name}.latitude`);
	if (longitude < -180 || longitude > 180 || latitude < -90 || latitude > 90) throw new Error(`${name} is outside valid WGS84 coordinate ranges.`);
	if (point.label !== undefined) nonEmptyString(point.label, `${name}.label`, 120);
	return { longitude, latitude, ...(point.label ? { label: point.label.trim() } : {}) };
}

function profileName(profile: unknown): string {
	const requested = nonEmptyString(profile, "profile", 80);
	const resolved = PROFILE_ALIASES[requested.toLowerCase()] ?? requested;
	if (!/^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$/.test(resolved)) throw new Error("profile may contain only letters, numbers, dot, underscore, and hyphen.");
	return resolved;
}

function normalizeRouteSpec(input: Partial<RouteSpec> & { waypoints: Waypoint[]; profile: string }): RouteSpec {
	if (!Array.isArray(input.waypoints) || input.waypoints.length < 2 || input.waypoints.length > MAX_WAYPOINTS) throw new Error(`waypoints must contain between 2 and ${MAX_WAYPOINTS} points.`);
	const waypoints = input.waypoints.map((point, index) => validateCoordinate(point, `waypoints[${index}]`));
	const alternativeIndex = input.alternativeIndex ?? 0;
	if (!Number.isInteger(alternativeIndex) || alternativeIndex < 0 || alternativeIndex > 3) throw new Error("alternativeIndex must be an integer from 0 to 3.");
	const noGoCircles = (input.noGoCircles ?? []).map((circle, index) => {
		const point = validateCoordinate(circle, `noGoCircles[${index}]`);
		const radius = finiteNumber(circle.radius, `noGoCircles[${index}].radius`);
		const weight = circle.weight === undefined ? undefined : finiteNumber(circle.weight, `noGoCircles[${index}].weight`);
		if (radius <= 0 || radius > 100_000) throw new Error("No-go radius must be greater than 0 and at most 100,000 metres.");
		if (weight !== undefined && (weight < 0 || weight > 1_000_000)) throw new Error("No-go weight must be between 0 and 1,000,000.");
		return { ...point, radius, ...(weight === undefined ? {} : { weight }) };
	});
	if (noGoCircles.length > 10) throw new Error("At most 10 no-go circles are allowed.");
	const heading = input.heading === undefined ? undefined : finiteNumber(input.heading, "heading");
	if (heading !== undefined && (heading < 0 || heading >= 360)) throw new Error("heading must be from 0 (inclusive) to 360 (exclusive).");
	const profileParameters = input.profileParameters ?? {};
	if (Object.keys(profileParameters).length > MAX_PROFILE_PARAMETERS) throw new Error(`At most ${MAX_PROFILE_PARAMETERS} profile parameters are allowed.`);
	for (const [key, value] of Object.entries(profileParameters)) {
		if (!/^[A-Za-z][A-Za-z0-9_.-]{0,79}$/.test(key)) throw new Error(`Invalid profile parameter name: ${key}`);
		if (typeof value !== "string" && typeof value !== "number" && typeof value !== "boolean") throw new Error(`Invalid value for profile parameter ${key}.`);
		if (typeof value === "string" && value.length > 200) throw new Error(`Profile parameter ${key} is too long.`);
	}
	return {
		waypoints,
		profile: profileName(input.profile),
		alternativeIndex,
		noGoCircles,
		...(heading === undefined ? {} : { heading }),
		profileParameters,
		...(input.trackName ? { trackName: sanitizeTrackName(input.trackName) } : {}),
		...(input.exportWaypoints ? { exportWaypoints: true } : {}),
		...(input.exportCorrectedWaypoints ? { exportCorrectedWaypoints: true } : {}),
	};
}

function formatCoordinate(value: number): string {
	return Number(value.toFixed(6)).toString();
}

/** Build BRouter's HTTP endpoint URL. BRouter uses lon,lat points joined by pipes. */
export function buildApiUrl(spec: RouteSpec, format: "geojson" | "gpx" = "geojson"): string {
	const query = new URLSearchParams({
		lonlats: spec.waypoints.map((point) => `${formatCoordinate(point.longitude)},${formatCoordinate(point.latitude)}`).join("|"),
		profile: spec.profile,
		alternativeidx: String(spec.alternativeIndex),
		format,
	});
	if (spec.noGoCircles.length) query.set("nogos", spec.noGoCircles.map((circle) => [formatCoordinate(circle.longitude), formatCoordinate(circle.latitude), String(circle.radius), circle.weight === undefined ? "" : String(circle.weight)].join(",")).join("|"));
	if (spec.heading !== undefined) query.set("heading", String(spec.heading));
	if (spec.trackName) query.set("trackname", spec.trackName);
	if (spec.exportWaypoints) query.set("exportWaypoints", "1");
	if (spec.exportCorrectedWaypoints) query.set("exportCorrectedWaypoints", "1");
	for (const [key, value] of Object.entries(spec.profileParameters)) query.set(`profile:${key}`, String(value));
	const url = `${BROUTER_URL}?${query.toString()}`;
	if (url.length > MAX_REQUEST_BYTES) throw new Error("Route request is unexpectedly large.");
	return url;
}

/** Build BRouter-web's map-first hash; its human permalink groups lon,lat pairs with semicolons. */
export function buildReviewUrl(spec: RouteSpec): string {
	const center = spec.waypoints.reduce((sum, point) => ({ longitude: sum.longitude + point.longitude, latitude: sum.latitude + point.latitude }), { longitude: 0, latitude: 0 });
	center.longitude /= spec.waypoints.length;
	center.latitude /= spec.waypoints.length;
	const parameters = [
		`map=11/${formatCoordinate(center.latitude)}/${formatCoordinate(center.longitude)}/standard`,
		`profile=${encodeURIComponent(spec.profile)}`,
		`alternativeidx=${spec.alternativeIndex}`,
		`lonlats=${spec.waypoints.map((point) => `${formatCoordinate(point.longitude)},${formatCoordinate(point.latitude)}`).join(";")}`,
	];
	if (spec.noGoCircles.length) parameters.push(`nogos=${spec.noGoCircles.map((circle) => [formatCoordinate(circle.longitude), formatCoordinate(circle.latitude), String(circle.radius), circle.weight === undefined ? "" : String(circle.weight)].join(",")).join(";")}`);
	if (spec.heading !== undefined) parameters.push(`heading=${spec.heading}`);
	for (const [key, value] of Object.entries(spec.profileParameters)) parameters.push(`${encodeURIComponent(`profile:${key}`)}=${encodeURIComponent(String(value))}`);
	return `https://bikerouter.de/#${parameters.join("&")}`;
}

function numericProperty(properties: JsonRecord, ...names: string[]): number | undefined {
	for (const name of names) {
		if (properties[name] !== undefined) {
			const value = Number(properties[name]);
			if (Number.isFinite(value)) return value;
		}
	}
	return undefined;
}

function asRecord(value: unknown): JsonRecord {
	return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}

function parseWayTags(value: unknown): Record<string, string> {
	if (typeof value !== "string") return {};
	const tags: Record<string, string> = {};
	for (const token of value.trim().split(/\s+/)) {
		const separator = token.indexOf("=");
		if (separator > 0 && separator < token.length - 1) tags[token.slice(0, separator)] = token.slice(separator + 1);
	}
	return tags;
}

function tableRows(value: unknown): Array<Record<string, unknown>> {
	if (!Array.isArray(value) || value.length < 2 || !Array.isArray(value[0])) return [];
	const header = value[0].map((item) => String(item).trim());
	return value.slice(1).flatMap((row) => Array.isArray(row) ? [Object.fromEntries(header.map((key, index) => [key, row[index]]))] : []);
}

function addDistance(target: Record<string, number>, key: string, distance: number) {
	target[key] = (target[key] ?? 0) + distance;
}

function finalizeBreakdown(breakdown: Record<string, number>, total: number): Breakdown {
	return Object.fromEntries(Object.entries(breakdown).sort((a, b) => b[1] - a[1]).map(([key, distanceMeters]) => [key, { distanceMeters: Math.round(distanceMeters), percent: total ? Number((distanceMeters * 100 / total).toFixed(1)) : 0 }]));
}

export function analyzeGeoJson(payload: unknown): RouteAnalysis {
	const root = asRecord(payload);
	const feature = root.type === "Feature" ? root : Array.isArray(root.features) ? root.features[0] : undefined;
	if (!feature || typeof feature !== "object") {
		const error = typeof root.message === "string" ? `: ${root.message}` : "";
		throw new Error(`BRouter returned GeoJSON without a route feature${error}`);
	}
	const properties = asRecord((feature as JsonRecord).properties);
	const surface: Record<string, number> = {};
	const highway: Record<string, number> = {};
	const tracktype: Record<string, number> = {};
	const smoothness: Record<string, number> = {};
	const warnings = new Set<string>();
	let analyzedDistanceMeters = 0;
	for (const row of tableRows(properties.messages)) {
		const distance = numericProperty(row, "Distance", "distance");
		if (distance === undefined || distance <= 0) continue;
		analyzedDistanceMeters += distance;
		const tags = parseWayTags(row.WayTags ?? row.waytags);
		for (const [name, target] of [["surface", surface], ["highway", highway], ["tracktype", tracktype], ["smoothness", smoothness]] as const) if (tags[name]) addDistance(target, tags[name], distance);
		for (const key of ["barrier", "access", "bicycle", "incline", "mtb:scale", "sac_scale", "ford"]) if (tags[key] && tags[key] !== "no") warnings.add(`${key}=${tags[key]}`);
	}
	const messageText = Array.isArray(properties.messages) ? properties.messages.flat().filter((value): value is string => typeof value === "string").join(" ") : "";
	if (/\b(no route|error|unreachable|not found)\b/i.test(messageText)) warnings.add("BRouter reported a routing warning; inspect the review link before approval.");
	const trackLength = numericProperty(properties, "track-length", "track_length", "distance");
	return {
		distanceKm: trackLength === undefined ? undefined : Number((trackLength / 1000).toFixed(2)),
		ascentM: numericProperty(properties, "filtered ascend", "filtered-ascend", "plain-ascend"),
		durationSeconds: numericProperty(properties, "total-time", "total_time"),
		energy: numericProperty(properties, "total-energy", "total_energy"),
		cost: numericProperty(properties, "cost"),
		analyzedDistanceMeters: Math.round(analyzedDistanceMeters),
		surface: finalizeBreakdown(surface, analyzedDistanceMeters),
		highway: finalizeBreakdown(highway, analyzedDistanceMeters),
		tracktype: finalizeBreakdown(tracktype, analyzedDistanceMeters),
		smoothness: finalizeBreakdown(smoothness, analyzedDistanceMeters),
		warnings: [...warnings].slice(0, 12),
	};
}

function summary(spec: RouteSpec, analysis: RouteAnalysis, reviewUrl: string): string {
	const duration = analysis.durationSeconds === undefined ? undefined : `${Math.round(analysis.durationSeconds / 60)} min estimated by BRouter`;
	const surface = Object.entries(analysis.surface).slice(0, 3).map(([name, value]) => `${name} ${value.percent}%`).join(", ");
	const highway = Object.entries(analysis.highway).slice(0, 3).map(([name, value]) => `${name} ${value.percent}%`).join(", ");
	const measures = [analysis.energy === undefined ? undefined : `energy ${Math.round(analysis.energy)}`, analysis.cost === undefined ? undefined : `cost ${Math.round(analysis.cost)}`].filter(Boolean).join("; ");
	return [
		`Profile: ${spec.profile}; alternative ${spec.alternativeIndex}; ${spec.waypoints.length} requested waypoint(s).`,
		analysis.distanceKm === undefined ? "Distance was not supplied by BRouter." : `Distance: ${analysis.distanceKm} km${analysis.ascentM === undefined ? "" : `; filtered ascent: ${Math.round(analysis.ascentM)} m`}.`,
		duration,
		measures ? `BRouter route measures: ${measures} (model-specific, not universal physical measurements).` : undefined,
		surface ? `Surface (from ${analysis.analyzedDistanceMeters} m tagged segments): ${surface}.` : undefined,
		highway ? `Path types: ${highway}.` : undefined,
		analysis.warnings.length ? `Warnings: ${analysis.warnings.join("; ")}.` : undefined,
		`Review before approval: ${reviewUrl}`,
	].filter(Boolean).join("\n");
}

async function fetchWithTimeout(url: string, init: RequestInit, signal: AbortSignal | undefined, timeoutMs: number): Promise<Response> {
	const timeout = AbortSignal.timeout(timeoutMs);
	const combined = signal ? AbortSignal.any([signal, timeout]) : timeout;
	try {
		return await fetch(url, { ...init, signal: combined });
	} catch (error) {
		if (combined.aborted) throw new Error(signal?.aborted ? "Request cancelled." : "Request timed out.");
		throw error;
	}
}

async function responseText(response: Response): Promise<string> {
	const text = await response.text();
	return text.length > 4_000 ? `${text.slice(0, 4_000)}…` : text;
}

function segmentReuseScore(payload: unknown): number {
	const root = asRecord(payload);
	const feature = root.type === "Feature" ? root : Array.isArray(root.features) ? root.features[0] : undefined;
	const geometry = asRecord(asRecord(feature).geometry);
	const coordinates = Array.isArray(geometry.coordinates) ? geometry.coordinates : [];
	const points = coordinates.flatMap((point) => Array.isArray(point) && point.length >= 2 && Number.isFinite(Number(point[0])) && Number.isFinite(Number(point[1])) ? [`${Number(point[0]).toFixed(6)},${Number(point[1]).toFixed(6)}`] : []);
	const segments = new Set<string>();
	let reused = 0;
	for (let index = 1; index < points.length; index += 1) {
		const forward = `${points[index - 1]}>${points[index]}`;
		const reverse = `${points[index]}>${points[index - 1]}`;
		if (segments.has(forward) || segments.has(reverse)) reused += 1;
		segments.add(forward);
	}
	return points.length > 1 ? reused / (points.length - 1) : 0;
}

async function route(spec: RouteSpec, signal: AbortSignal | undefined): Promise<{ analysis: RouteAnalysis; reviewUrl: string; apiUrl: string; reuseScore: number }> {
	const apiUrl = buildApiUrl(spec);
	const response = await fetchWithTimeout(apiUrl, { headers: { Accept: "application/geo+json, application/json" } }, signal, 25_000);
	if (!response.ok) throw new Error(`BRouter request failed (${response.status}): ${await responseText(response)}`);
	const contentType = response.headers.get("content-type") ?? "";
	if (!/json|geojson/i.test(contentType)) throw new Error(`BRouter returned an unexpected content type: ${contentType || "unknown"}.`);
	let payload: unknown;
	try { payload = await response.json(); } catch { throw new Error("BRouter returned invalid GeoJSON."); }
	return { analysis: analyzeGeoJson(payload), reviewUrl: buildReviewUrl(spec), apiUrl, reuseScore: segmentReuseScore(payload) };
}

function sleep(milliseconds: number, signal?: AbortSignal): Promise<void> {
	return new Promise((resolveSleep, reject) => {
		const timer = setTimeout(resolveSleep, milliseconds);
		signal?.addEventListener("abort", () => { clearTimeout(timer); reject(new Error("Request cancelled.")); }, { once: true });
	});
}

function waitForPromise(promise: Promise<void>, signal?: AbortSignal): Promise<void> {
	if (!signal) return promise;
	if (signal.aborted) return Promise.reject(new Error("Request cancelled."));
	return new Promise((resolveWait, reject) => {
		const abort = () => reject(new Error("Request cancelled."));
		signal.addEventListener("abort", abort, { once: true });
		promise.then(() => { signal.removeEventListener("abort", abort); resolveWait(); }, (error) => { signal.removeEventListener("abort", abort); reject(error); });
	});
}

async function scheduleNominatim(signal?: AbortSignal): Promise<void> {
	let release!: () => void;
	const predecessor = geocodeQueue;
	geocodeQueue = new Promise<void>((resolveQueue) => { release = resolveQueue; });
	try {
		await waitForPromise(predecessor, signal);
		const delay = Math.max(0, 1_100 - (Date.now() - lastGeocodeAt));
		if (delay) await sleep(delay, signal);
		if (signal?.aborted) throw new Error("Request cancelled.");
		lastGeocodeAt = Date.now();
	} finally {
		release();
	}
}

function destination(start: Waypoint, bearingDegrees: number, distanceKm: number): Waypoint {
	const radiusKm = 6371;
	const angular = distanceKm / radiusKm;
	const bearing = bearingDegrees * Math.PI / 180;
	const latitude = start.latitude * Math.PI / 180;
	const longitude = start.longitude * Math.PI / 180;
	const resultLatitude = Math.asin(Math.sin(latitude) * Math.cos(angular) + Math.cos(latitude) * Math.sin(angular) * Math.cos(bearing));
	const resultLongitude = longitude + Math.atan2(Math.sin(bearing) * Math.sin(angular) * Math.cos(latitude), Math.cos(angular) - Math.sin(latitude) * Math.sin(resultLatitude));
	return { longitude: ((resultLongitude * 180 / Math.PI + 540) % 360) - 180, latitude: resultLatitude * 180 / Math.PI };
}

function loopWaypoints(start: Waypoint, targetKm: number, orientation: number): Waypoint[] {
	// A triangular loop's radius is deliberately conservative; the one bounded rescale below corrects it.
	const radius = targetKm / 4.8;
	return [start, destination(start, orientation, radius), destination(start, orientation + 120, radius), destination(start, orientation + 240, radius), start];
}

function routeSpecDetails(spec: RouteSpec) {
	return {
		profile: spec.profile,
		waypoints: spec.waypoints,
		alternativeIndex: spec.alternativeIndex,
		noGoCircles: spec.noGoCircles,
		heading: spec.heading,
		profileParameters: spec.profileParameters,
		trackName: spec.trackName,
	};
}

export function candidateScore(analysis: RouteAnalysis, targetKm: number, profile: string, reuseScore: number): number {
	const deviation = analysis.distanceKm === undefined ? 1_000 : Math.abs(analysis.distanceKm - targetKm) / targetKm;
	const unpaved = Object.entries(analysis.surface).filter(([surface]) => !["asphalt", "concrete", "paved", "paving_stones", "sett", "cobblestone"].includes(surface)).reduce((sum, [, value]) => sum + value.percent, 0);
	const profilePenalty = profile === "cxb-gravel" ? Math.max(0, 50 - unpaved) / 10 : profile === "fastbike" ? unpaved / 20 : 0;
	return deviation * 100 + profilePenalty + reuseScore * 50 + analysis.warnings.length * 3;
}

export function sanitizeTrackName(value: string): string {
	const normalized = nonEmptyString(value, "trackName", 120).normalize("NFKC").replace(/[\\/:*?"<>|\x00-\x1f]/g, " ").replace(/\s+/g, " ").trim();
	if (!normalized || normalized === "." || normalized === "..") throw new Error("trackName contains no usable file-name characters.");
	return normalized.slice(0, 100);
}

function fileNameForTrack(name: string): string {
	return `${name.replace(/[^A-Za-z0-9._ -]/g, "_").replace(/\s+/g, "-").replace(/^-+|-+$/g, "") || "route"}.gpx`;
}

function validXmlAttributes(value: string): boolean {
	let offset = 0;
	while (offset < value.length) {
		const whitespace = /^\s+/.exec(value.slice(offset));
		if (!whitespace) return false;
		offset += whitespace[0].length;
		if (offset === value.length) return true;
		const name = /^[A-Za-z_:][A-Za-z0-9_.:-]*/.exec(value.slice(offset));
		if (!name) return false;
		offset += name[0].length;
		const beforeEquals = /^\s*/.exec(value.slice(offset))?.[0] ?? "";
		offset += beforeEquals.length;
		if (value[offset] !== "=") return false;
		offset += 1;
		const afterEquals = /^\s*/.exec(value.slice(offset))?.[0] ?? "";
		offset += afterEquals.length;
		const quote = value[offset];
		if (quote !== '"' && quote !== "'") return false;
		offset += 1;
		const end = value.indexOf(quote, offset);
		if (end < 0 || value.slice(offset, end).includes("<")) return false;
		offset = end + 1;
	}
	return true;
}

/** A bounded, non-expanding XML structure check for BRouter GPX responses. */
export function gpxLooksValid(body: string, contentType: string): boolean {
	if (!/xml|gpx/i.test(contentType) || body.length === 0 || body.length > MAX_GPX_BYTES || /<!DOCTYPE|<!ENTITY/i.test(body)) return false;
	const stack: string[] = [];
	let rootSeen = false;
	let routeSeen = false;
	let offset = 0;
	while (offset < body.length) {
		const next = body.indexOf("<", offset);
		if (next < 0) break;
		const text = body.slice(offset, next);
		if ((stack.length === 0 && text.trim()) || text.includes("]]>") || text.includes("<")) return false;
		if (body.startsWith("<!--", next)) {
			const end = body.indexOf("-->", next + 4);
			if (end < 0) return false;
			offset = end + 3;
			continue;
		}
		if (body.startsWith("<![CDATA[", next)) {
			if (stack.length === 0) return false;
			const end = body.indexOf("]]>", next + 9);
			if (end < 0) return false;
			offset = end + 3;
			continue;
		}
		if (body.startsWith("<?", next)) {
			const end = body.indexOf("?>", next + 2);
			if (end < 0) return false;
			offset = end + 2;
			continue;
		}
		let end = -1;
		let quote = "";
		for (let index = next + 1; index < body.length; index += 1) {
			const character = body[index];
			if (quote) {
				if (character === quote) quote = "";
			} else if (character === '"' || character === "'") {
				quote = character;
			} else if (character === ">") {
				end = index;
				break;
			}
		}
		if (end < 0 || quote) return false;
		const token = body.slice(next + 1, end);
		if (token.startsWith("/") ) {
			const closing = /^\/([A-Za-z_:][A-Za-z0-9_.:-]*)\s*$/.exec(token);
			if (!closing || stack.pop() !== closing[1]) return false;
		} else {
			if (rootSeen && stack.length === 0) return false;
			const selfClosing = /\/\s*$/.test(token);
			// GPX emitted by BRouter spreads root attributes over multiple lines, so the
			// attribute suffix must match newlines as well as ordinary spaces.
			const opening = /^([A-Za-z_:][A-Za-z0-9_.:-]*)([\s\S]*)$/.exec(selfClosing ? token.replace(/\/\s*$/, "") : token);
			if (!opening || !validXmlAttributes(opening[2])) return false;
			const name = opening[1];
			if (!rootSeen) {
				if (name !== "gpx") return false;
				rootSeen = true;
			}
			if (name === "trk" || name === "rte") routeSeen = true;
			if (!selfClosing) stack.push(name);
		}
		offset = end + 1;
	}
	return rootSeen && routeSeen && stack.length === 0 && !body.slice(offset).trim();
}

async function persistentOutputPath(cwd: string, input: string): Promise<string> {
	const requested = input.replace(/^@/, "");
	if (!requested || isAbsolute(requested)) throw new Error("outputPath must be a relative path inside the current working directory.");
	const canonicalCwd = await realpath(cwd);
	let candidate = resolve(canonicalCwd, requested);
	if (!candidate.toLowerCase().endsWith(".gpx")) candidate = `${candidate}.gpx`;
	const canonicalParent = await realpath(dirname(candidate));
	const parentRelative = relative(canonicalCwd, canonicalParent);
	if (parentRelative.startsWith("..") || isAbsolute(parentRelative)) throw new Error("outputPath must remain inside the current working directory and may not traverse symlinks.");
	return resolve(canonicalParent, basename(candidate));
}

export default function brouterExtension(pi: ExtensionAPI) {
	pi.registerTool({
		name: "brouter_geocode",
		label: "BRouter Geocode",
		description: "Resolve a free-text place using public Nominatim. Results are candidates; do not silently choose an ambiguous location.",
		promptSnippet: "Resolve a place to candidate longitude/latitude coordinates for bicycle routing",
		promptGuidelines: ["Use brouter_geocode only for a needed free-text location. Ask the user to choose materially different results, and never claim its result is a confirmed start point without user confirmation."],
		parameters: Type.Object({ query: Type.String({ minLength: 1, maxLength: 300 }), limit: Type.Optional(Type.Integer({ minimum: 1, maximum: 5 })) }),
		async execute(_id, params, signal) {
			const query = nonEmptyString(params.query, "query", 300);
			await scheduleNominatim(signal);
			const url = new URL(NOMINATIM_URL);
			url.search = new URLSearchParams({ q: query, format: "jsonv2", addressdetails: "0", limit: String(params.limit ?? 3) }).toString();
			const response = await fetchWithTimeout(url.toString(), { headers: { "User-Agent": USER_AGENT, Accept: "application/json" } }, signal, 12_000);
			if (!response.ok) throw new Error(`Nominatim request failed (${response.status}): ${await responseText(response)}`);
			const payload: unknown = await response.json();
			if (!Array.isArray(payload)) throw new Error("Nominatim returned an unexpected response.");
			const results = payload.slice(0, params.limit ?? 3).flatMap((item) => {
				const value = asRecord(item);
				try {
					return [{ displayName: String(value.display_name ?? "Unnamed result"), longitude: finiteNumber(value.lon, "Nominatim longitude"), latitude: finiteNumber(value.lat, "Nominatim latitude"), type: String(value.type ?? ""), category: String(value.category ?? ""), boundingBox: Array.isArray(value.boundingbox) ? value.boundingbox.map(String) : undefined }];
				} catch { return []; }
			});
			return { content: [{ type: "text", text: results.length ? `Found ${results.length} location candidate(s). Ask the user to choose if they are materially different.\n${results.map((result, index) => `${index + 1}. ${result.displayName} (${result.longitude}, ${result.latitude})`).join("\n")}` : "No location candidates found. Ask for a more specific place or coordinates." }], details: { results } };
		},
	});

	pi.registerTool({
		name: "brouter_route",
		label: "BRouter Route",
		description: "Route ordered cycling waypoints through BRouter and return a compact analysis, reproducible route specification, and BRouter-web review link.",
		promptSnippet: "Route cycling waypoints, analyze tagged route composition, and produce a BRouter review link",
		promptGuidelines: ["Use brouter_route for point-to-point routes and approved revisions. Present the review link and ask for explicit route approval before calling brouter_download_gpx."],
		parameters: routeInputSchema,
		async execute(_id, params, signal) {
			const spec = normalizeRouteSpec(params);
			const result = await route(spec, signal);
			return { content: [{ type: "text", text: summary(spec, result.analysis, result.reviewUrl) }], details: { routeSpecification: routeSpecDetails(spec), analysis: result.analysis, reviewUrl: result.reviewUrl, apiRequest: result.apiUrl } };
		},
	});

	pi.registerTool({
		name: "brouter_roundtrip_candidates",
		label: "BRouter Round-trip Candidates",
		description: "Generate up to three bounded, sequential closed-loop suggestions through BRouter. They require user inspection and approval.",
		promptSnippet: "Generate up to three cycling round-trip candidates with review links",
		promptGuidelines: ["Use brouter_roundtrip_candidates for a requested closed loop. Treat every candidate as a suggestion requiring map inspection and explicit user approval; never download GPX merely because a candidate was generated."],
		parameters: roundtripSchema,
		async execute(_id, params, signal, onUpdate) {
			const start = validateCoordinate(params.start, "start");
			const targetDistanceKm = finiteNumber(params.targetDistanceKm, "targetDistanceKm");
			if (targetDistanceKm <= 1 || targetDistanceKm > 500) throw new Error("targetDistanceKm must be greater than 1 and at most 500.");
			const count = params.candidateCount ?? 3;
			if (!Number.isInteger(count) || count < 1 || count > 3) throw new Error("candidateCount must be from 1 to 3.");
			const baseHeading = params.heading ?? 0;
			const candidates: Array<{ spec: RouteSpec; analysis: RouteAnalysis; reviewUrl: string; reuseScore: number; score: number }> = [];
			// One initial route plus at most one rescale per candidate: maximum six public-service requests.
			for (let index = 0; index < count; index += 1) {
				onUpdate?.({ content: [{ type: "text", text: `Routing candidate ${index + 1}/${count} (bounded request budget)…` }] });
				const orientation = (baseHeading + index * 360 / count) % 360;
				let spec = normalizeRouteSpec({ waypoints: loopWaypoints(start, targetDistanceKm, orientation), profile: params.profile, noGoCircles: params.noGoCircles, heading: params.heading, profileParameters: params.profileParameters, trackName: `Loop ${index + 1}` });
				try {
					let result = await route(spec, signal);
					if (result.analysis.distanceKm && Math.abs(result.analysis.distanceKm - targetDistanceKm) / targetDistanceKm > 0.10) {
						const scale = Math.max(0.55, Math.min(1.65, targetDistanceKm / result.analysis.distanceKm));
						spec = normalizeRouteSpec({ ...spec, waypoints: loopWaypoints(start, targetDistanceKm * scale, orientation) });
						result = await route(spec, signal);
					}
					candidates.push({ spec, analysis: result.analysis, reviewUrl: result.reviewUrl, reuseScore: result.reuseScore, score: candidateScore(result.analysis, targetDistanceKm, spec.profile, result.reuseScore) });
				} catch (error) {
					if (signal?.aborted) throw error;
					candidates.push({ spec, analysis: { analyzedDistanceMeters: 0, surface: {}, highway: {}, tracktype: {}, smoothness: {}, warnings: [error instanceof Error ? error.message : "Routing failed."] }, reviewUrl: buildReviewUrl(spec), reuseScore: 1, score: 10_000 });
				}
			}
			candidates.sort((a, b) => a.score - b.score);
			const details = candidates.map((candidate, index) => ({ name: `Loop ${index + 1}`, routeSpecification: routeSpecDetails(candidate.spec), analysis: candidate.analysis, reviewUrl: candidate.reviewUrl, segmentReusePercent: Number((candidate.reuseScore * 100).toFixed(1)), targetDeviationKm: candidate.analysis.distanceKm === undefined ? undefined : Number((candidate.analysis.distanceKm - targetDistanceKm).toFixed(2)) }));
			return { content: [{ type: "text", text: `Generated ${details.length} bounded loop suggestion(s); review a link and obtain explicit user approval before GPX download.\n\n${details.map((candidate) => `## ${candidate.name}\n${summary(candidate.routeSpecification as RouteSpec, candidate.analysis, candidate.reviewUrl)}`).join("\n\n")}` }], details: { targetDistanceKm, requestBudget: count * 2, candidates: details } };
		},
	});

	pi.registerTool({
		name: "brouter_download_gpx",
		label: "BRouter Download GPX",
		description: "Download the explicitly approved, reproducible BRouter route specification as a validated GPX. This does not import or send to Garmin.",
		promptSnippet: "Download an explicitly approved BRouter route specification as GPX",
		promptGuidelines: ["Call brouter_download_gpx only after the user explicitly approves this exact route specification. It only downloads GPX; after it returns, show course name/type/device and obtain a separate final confirmation before any Garmin import or send."],
		parameters: downloadSchema,
		async execute(_id, params, signal, _onUpdate, ctx) {
			const spec = normalizeRouteSpec(params);
			const trackName = sanitizeTrackName(params.trackName);
			spec.trackName = trackName;
			const response = await fetchWithTimeout(buildApiUrl(spec, "gpx"), { headers: { Accept: "application/gpx+xml, application/xml, text/xml" } }, signal, 30_000);
			const declaredLength = Number(response.headers.get("content-length"));
			if (response.ok && Number.isFinite(declaredLength) && declaredLength > MAX_GPX_BYTES) throw new Error("BRouter GPX response is too large; no file was written.");
			const body = await response.text();
			if (!response.ok) throw new Error(`BRouter GPX download failed (${response.status}): ${body.slice(0, 4_000)}`);
			if (!gpxLooksValid(body, response.headers.get("content-type") ?? "")) throw new Error("BRouter response was not a valid GPX track/route; no file was written.");
			let outputPath: string;
			let temporary: boolean;
			if (params.outputPath?.trim()) {
				outputPath = await persistentOutputPath(ctx.cwd, params.outputPath);
				temporary = false;
				await withFileMutationQueue(outputPath, async () => {
					try {
						await lstat(outputPath);
						throw new Error("outputPath already exists; refusing to overwrite it.");
					} catch (error) {
						if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
					}
					await writeFile(outputPath, body, { encoding: "utf8", flag: "wx" });
				});
			} else {
				const directory = await mkdtemp(resolve(tmpdir(), "brouter-gpx-"));
				outputPath = resolve(directory, fileNameForTrack(trackName));
				temporary = true;
				await writeFile(outputPath, body, "utf8");
			}
			return { content: [{ type: "text", text: `Downloaded validated GPX to ${outputPath}${temporary ? " (temporary; retain it until Garmin import succeeds)" : ""}. Do not import or send yet: show the course name, type, distance, and intended Edge 540, then obtain separate final confirmation.` }], details: { path: outputPath, temporary, routeSpecification: routeSpecDetails(spec), trackName } };
		},
	});
}
