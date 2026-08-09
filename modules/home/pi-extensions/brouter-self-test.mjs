#!/usr/bin/env node
/**
 * Deterministic, dependency-free checks for brouter.ts.
 * Run with: node --experimental-strip-types modules/home/pi-extensions/brouter-self-test.mjs
 */
import { execFile as execFileCallback } from "node:child_process";
import { cp, mkdir, mkdtemp, readFile, rm, stat, symlink } from "node:fs/promises";
import { realpath } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFile = promisify(execFileCallback);

if (!process.execArgv.includes("--experimental-strip-types")) {
	throw new Error("Run this harness with node --experimental-strip-types.");
}

const here = dirname(fileURLToPath(import.meta.url));
const testDirectory = await mkdtemp(join(tmpdir(), "brouter-self-test-"));
const nodeModules = join(testDirectory, "node_modules");
let temporaryGpxDirectory;
let outsideDirectory;

try {
	const { stdout } = await execFile("which", ["pi"]);
	const piBinary = await realpath(stdout.trim());
	const wrapper = await readFile(piBinary, "utf8");
	const runtimeMatch = wrapper.match(/exec\s+(\/nix\/store\/[^\s]+-pi-coding-agent-[^/]+)\/bin\/pi/);
	const piRoot = runtimeMatch?.[1] ?? resolve(dirname(piBinary), "..");
	const piNodeModules = join(piRoot, "lib/node_modules");
	await mkdir(nodeModules);
	await cp(join(here, "brouter.ts"), join(testDirectory, "brouter.ts"));
	await symlink(join(piNodeModules, "@earendil-works"), join(nodeModules, "@earendil-works"));
	await symlink(join(piNodeModules, "typebox"), join(nodeModules, "typebox"));

	const extensionModule = await import(join(testDirectory, "brouter.ts"));
	const {
		analyzeGeoJson,
		buildApiUrl,
		buildReviewUrl,
		default: brouterExtension,
		gpxLooksValid,
		sanitizeTrackName,
	} = extensionModule;
	const spec = {
		waypoints: [{ longitude: 8.68, latitude: 50.11 }, { longitude: 8.7, latitude: 50.1 }, { longitude: 8.69, latitude: 50.105 }],
		profile: "trekking",
		alternativeIndex: 0,
		noGoCircles: [{ longitude: 8.69, latitude: 50.105, radius: 100 }],
		heading: 90,
		profileParameters: { consider_traffic: false },
	};
	const apiUrl = buildApiUrl(spec);
	const reviewUrl = buildReviewUrl(spec);
	if (!apiUrl.includes("lonlats=8.68%2C50.11%7C8.7%2C50.1%7C8.69%2C50.105") || !apiUrl.includes("profile%3Aconsider_traffic=false")) throw new Error("API URL encoding check failed.");
	if (!reviewUrl.includes("#map=11/50.105/8.69/standard&profile=trekking") || !reviewUrl.includes("lonlats=8.68,50.11;8.7,50.1;8.69,50.105")) throw new Error("Review-link map or grouped multi-waypoint serialization check failed.");
	if (!gpxLooksValid("<gpx><trk></trk></gpx>", "application/gpx+xml") || gpxLooksValid("<gpx><trk></gpx>", "application/gpx+xml") || gpxLooksValid("<gpx broken><trk></trk></gpx>", "application/gpx+xml") || gpxLooksValid("<html>error</html>", "text/html") || sanitizeTrackName("A:/B") !== "A B") throw new Error("GPX structural validation or track-name sanitization check failed.");

	const feature = {
		type: "FeatureCollection",
		features: [{
			geometry: { type: "LineString", coordinates: [[8.68, 50.11], [8.7, 50.1], [8.68, 50.11]] },
			properties: {
				"track-length": "12345",
				"filtered ascend": "234",
				messages: [["Distance", "WayTags"], ["6000", "surface=gravel highway=track tracktype=grade2"], ["4000", "surface=asphalt highway=secondary smoothness=good"], ["1000", "barrier=gate access=permissive"]],
			},
		}],
	};
	const analysis = analyzeGeoJson(feature);
	if (analysis.distanceKm !== 12.35 || analysis.surface.gravel.percent !== 54.5 || analysis.highway.track.percent !== 54.5 || !analysis.warnings.includes("barrier=gate")) throw new Error("GeoJSON analysis check failed.");

	const tools = new Map();
	brouterExtension({ registerTool(tool) { tools.set(tool.name, tool); } });
	if (tools.size !== 4) throw new Error("Expected all four BRouter tools to be registered.");
	const geocodeStarts = [];
	globalThis.fetch = async () => {
		geocodeStarts.push(Date.now());
		return new Response(JSON.stringify([{ display_name: "Test place", lon: "8.68", lat: "50.11", type: "village", category: "place" }]), { status: 200, headers: { "content-type": "application/json" } });
	};
	await Promise.all([
		tools.get("brouter_geocode").execute("geocode-a", { query: "first" }, undefined, undefined, {}),
		tools.get("brouter_geocode").execute("geocode-b", { query: "second" }, undefined, undefined, {}),
	]);
	if (geocodeStarts.length !== 2 || geocodeStarts[1] - geocodeStarts[0] < 1_000) throw new Error("Nominatim scheduling was not serialized at the required rate.");
	globalThis.fetch = async () => new Response(JSON.stringify(feature), { status: 200, headers: { "content-type": "application/geo+json" } });
	const routeResult = await tools.get("brouter_route").execute("route", { waypoints: spec.waypoints, profile: "gravel" }, undefined, undefined, {});
	if (routeResult.details.routeSpecification.profile !== "cxb-gravel") throw new Error("Profile alias check failed.");

	let requests = 0;
	globalThis.fetch = async () => {
		requests += 1;
		return new Response(JSON.stringify(feature), { status: 200, headers: { "content-type": "application/geo+json" } });
	};
	const candidates = await tools.get("brouter_roundtrip_candidates").execute("candidate", { start: spec.waypoints[0], targetDistanceKm: 20, profile: "gravel", candidateCount: 1 }, undefined, undefined, {});
	if (requests !== 2 || candidates.details.candidates.length !== 1) throw new Error("Round-trip request-budget check failed.");

	globalThis.fetch = async () => new Response("<?xml version=\"1.0\"?><gpx><trk><trkseg><trkpt lat=\"50.1\" lon=\"8.6\"/></trkseg></trk></gpx>", { status: 200, headers: { "content-type": "application/gpx+xml" } });
	const download = await tools.get("brouter_download_gpx").execute("gpx", { waypoints: spec.waypoints, profile: "gravel", trackName: "Test: route" }, undefined, undefined, { cwd: process.cwd() });
	temporaryGpxDirectory = dirname(download.details.path);
	await mkdir(join(testDirectory, "courses"));
	const persistent = await tools.get("brouter_download_gpx").execute("persistent", { waypoints: spec.waypoints, profile: "gravel", trackName: "Retained", outputPath: "courses/retained-route" }, undefined, undefined, { cwd: testDirectory });
	await stat(persistent.details.path);
	let rejectedOverwrite = false;
	try {
		await tools.get("brouter_download_gpx").execute("overwrite", { waypoints: spec.waypoints, profile: "gravel", trackName: "Retained", outputPath: "courses/retained-route" }, undefined, undefined, { cwd: testDirectory });
	} catch (error) {
		rejectedOverwrite = String(error).includes("refusing to overwrite");
	}
	outsideDirectory = await mkdtemp(join(tmpdir(), "brouter-outside-"));
	await symlink(outsideDirectory, join(testDirectory, "courses", "escape"));
	let rejectedEscape = false;
	try {
		await tools.get("brouter_download_gpx").execute("escape", { waypoints: spec.waypoints, profile: "gravel", trackName: "Escape", outputPath: "courses/escape/route" }, undefined, undefined, { cwd: testDirectory });
	} catch (error) {
		rejectedEscape = String(error).includes("may not traverse symlinks");
	}
	let rejectedTraversal = false;
	try {
		await tools.get("brouter_download_gpx").execute("traversal", { waypoints: spec.waypoints, profile: "gravel", trackName: "Traversal", outputPath: "../route" }, undefined, undefined, { cwd: testDirectory });
	} catch (error) {
		rejectedTraversal = String(error).includes("must remain inside");
	}
	if (!rejectedOverwrite || !rejectedEscape || !rejectedTraversal) throw new Error("Persistent output overwrite, traversal, or symlink-escape protection failed.");
	globalThis.fetch = async () => new Response("<html>error</html>", { status: 200, headers: { "content-type": "text/html" } });
	let rejectedHtml = false;
	try {
		await tools.get("brouter_download_gpx").execute("bad-gpx", { waypoints: spec.waypoints, profile: "gravel", trackName: "bad" }, undefined, undefined, { cwd: process.cwd() });
	} catch (error) {
		rejectedHtml = String(error).includes("valid GPX");
	}
	if (!rejectedHtml) throw new Error("HTML GPX response was not rejected.");

	console.log("BRouter self-test passed.");
} finally {
	if (temporaryGpxDirectory) await rm(temporaryGpxDirectory, { recursive: true, force: true });
	if (outsideDirectory) await rm(outsideDirectory, { recursive: true, force: true });
	await rm(testDirectory, { recursive: true, force: true });
}
