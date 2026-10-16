import assert from "node:assert/strict";
import { test } from "node:test";
import { AirflowClient, API_BASE_URL, buildReadRequest, normalizeBaseUrl, parseConnectionCredentials, redactLog, SECRET_NAMES, type ReadRequest } from "../client.ts";

const PASSWORD = 'p@ss"word\\value';
const USER = "api-reader";
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

function fixture(options: { now?: () => number; respond?: (url: URL, init: RequestInit, index: number) => Response | Promise<Response> } = {}) {
  const secrets: string[] = [];
  const requests: Array<{ url: URL; init: RequestInit }> = [];
  const client = new AirflowClient({
    now: options.now,
    readSecret: async (name) => {
      secrets.push(name);
      return `http://${encodeURIComponent(USER)}:${encodeURIComponent(PASSWORD)}@lb-airflow-prod-api-server:8080/http`;
    },
    fetch: async (url, init = {}) => {
      const parsed = new URL(String(url));
      assert.equal(parsed.origin, API_BASE_URL);
      requests.push({ url: parsed, init });
      assert.equal(init.redirect, "error");
      if (options.respond) return options.respond(parsed, init, requests.length);
      if (parsed.pathname.endsWith("/auth/token")) {
        assert.equal(init.method, "POST");
        assert.deepEqual(JSON.parse(String(init.body)), { username: USER, password: PASSWORD });
        return json({ access_token: "opaque-test-token", expires_in: 3600 });
      }
      assert.equal(init.method, "GET");
      assert.equal(init.body, undefined);
      assert.equal(new Headers(init.headers).get("Authorization"), "Bearer opaque-test-token");
      if (parsed.pathname.endsWith("/version")) return json({ version: "3.3.1" });
      if (parsed.pathname.endsWith("/dags")) return json({ dags: [{ dag_id: "example", is_paused: false, conf: "never expose" }], total_entries: 1 });
      if (parsed.pathname.endsWith("/dagRuns")) return json({ dag_runs: [{ dag_id: "example", dag_run_id: "scheduled__2026-10-16T00:00:00+00:00", state: "failed", conf: { secret: "never expose" } }], total_entries: 1 });
      if (parsed.pathname.endsWith("/taskInstances")) return json({ task_instances: [{ task_id: "load", map_index: 2, try_number: 3, state: "failed", rendered_fields: "never expose" }], total_entries: 1 });
      if (parsed.pathname.includes("/logs/")) return json({ content: "Error: example", continuation_token: null });
      return json({ dag_id: "example", dag_run_id: "run", state: "failed", conf: "never expose" });
    },
  });
  return { client, requests, secrets };
}

const run = { dagId: "example", dagRunId: "scheduled__2026-10-16T00:00:00+00:00" };
const operations: ReadRequest[] = [
  { operation: "dags", pattern: "example" },
  { operation: "runs", dagId: "example", state: "failed" },
  { operation: "run", ...run },
  { operation: "tasks", ...run, state: "failed" },
  { operation: "logs", ...run, taskId: "load", tryNumber: 3, mapIndex: 2 },
];

test("base URL accepts root, ingress prefix and v2 suffix; rejects insecure or ambiguous URLs", () => {
  assert.equal(normalizeBaseUrl("https://example.test/"), "https://example.test");
  assert.equal(normalizeBaseUrl("https://example.test/airflow/api/v2/"), "https://example.test/airflow");
  for (const url of ["http://example.test", "file:///tmp/test", "https://u:p@example.test", "https://example.test?x=1", "https://example.test#fragment", "https://example.test/api/v1", "https://example.test/%2fother", "https://example.test/\\other", "not a URL"]) {
    assert.throws(() => normalizeBaseUrl(url));
  }
});

test("no Azure/network work until enable; one-time concurrent and repeated enable; shared token", async () => {
  const { client, requests, secrets } = fixture();
  assert.equal(secrets.length, 0);
  assert.equal(requests.length, 0);
  await assert.rejects(client.read(operations[0]), /airflow_enable/);
  assert.equal(requests.length, 0);
  assert.deepEqual(await Promise.all([client.enable(), client.enable(), client.enable()]), Array(3).fill({ version: "3.3.1" }));
  await client.enable();
  assert.deepEqual(secrets, [...SECRET_NAMES]);
  assert.equal(requests.length, 2);
  for (const op of operations) {
    const result = await client.read(op);
    assert.ok(!JSON.stringify(result).includes("never expose"));
  }
  assert.equal(requests.filter(({ init }) => init.method === "POST").length, 1);
  assert.ok(requests.every(({ url, init }) => init.method === "GET" || url.pathname === "/auth/token"));
  assert.equal(requests[2].url.searchParams.get("limit"), "25");
  assert.equal(requests.at(-1)!.url.searchParams.get("map_index"), "2");
  assert.equal(requests.at(-1)!.url.searchParams.get("full_content"), "false");
  assert.match(requests[3].url.pathname, /dagRuns$/);
  assert.equal(requests[3].url.searchParams.get("order_by"), "-run_after");
});

test("rejects unsupported operations, path traversal, wildcards and invalid bounds before network", async () => {
  const { client, requests } = fixture();
  await client.enable();
  for (const operation of ["trigger", "clear", "patch", "delete", "connections", "variables", "xcoms", "GET", "raw"]) {
    await assert.rejects(client.read({ operation, path: "/api/v2/connections", method: "POST" } as any), /read-only policy/);
  }
  for (const dagId of ["..", ".", "~", "a/clear", "%2e%2e", "%252f", "a\\b", "a?x=y", "a#z", "https://evil.test", "bad\nheader", ""]) {
    await assert.rejects(client.read({ operation: "runs", dagId }), /Invalid Airflow identifier/);
  }
  for (const invalid of [
    { operation: "dags", limit: 0 }, { operation: "dags", limit: 101 }, { operation: "dags", offset: -1 },
    { operation: "dags", offset: 1.5 }, { operation: "logs", ...run, taskId: "task", tryNumber: 0 },
    { operation: "logs", ...run, taskId: "task", tryNumber: 1, mapIndex: -2 },
    { operation: "logs", ...run, taskId: "task", tryNumber: 1, maxChars: 100000 },
    { operation: "logs", ...run, taskId: "task", tryNumber: 1, continuationToken: "bad\nvalue" },
  ]) await assert.rejects(client.read(invalid as ReadRequest));
  assert.equal(requests.length, 2);
  const encoded = buildReadRequest({ operation: "run", ...run });
  assert.ok(encoded.path.includes("scheduled__2026-10-16T00%3A00%3A00%2B00%3A00"));
});

test("Airflow connection parsing supports URI/JSON and never exposes malformed secret contents", () => {
  assert.deepEqual(parseConnectionCredentials(`http://${encodeURIComponent(USER)}:${encodeURIComponent(PASSWORD)}@internal:8080/http`), { username: USER, password: PASSWORD });
  assert.deepEqual(parseConnectionCredentials(JSON.stringify({ conn_type: "http", host: "internal", schema: "http", port: 8080, login: USER, password: PASSWORD })), { username: USER, password: PASSWORD });
  assert.deepEqual(parseConnectionCredentials("http://user%2Bname:p%2Bss%25word@internal:8080/http"), { username: "user+name", password: "p+ss%word" });
  for (const value of ["not-a-uri", "{bad-json", "http://internal", '{"login":"user"}', "http://user:%zz@internal/http", "ftp://user:secret@internal", '{"login":5,"password":"secret"}']) {
    assert.throws(() => parseConnectionCredentials(value), (error: Error) => !error.message.includes(value) && /connection URI or JSON/.test(error.message));
  }
});

test("invalid connection causes no network access; retry reads corrected secret; connection host cannot redirect credentials", async () => {
  let connection = "invalid";
  let fetches = 0;
  const client = new AirflowClient({
    readSecret: async () => connection,
    fetch: async (url) => {
      fetches++;
      assert.equal(new URL(String(url)).origin, API_BASE_URL);
      return json(String(url).endsWith("/auth/token") ? { access_token: "dummy" } : { version: "3.3.1" });
    },
  });
  await assert.rejects(client.enable(), /connection URI or JSON/);
  assert.equal(fetches, 0);
  await assert.rejects(client.read(operations[0]), /airflow_enable/);
  connection = "http://user:pass@attacker.example:8080/http?base_url=https://attacker.example";
  await client.enable();
  assert.equal(fetches, 2);
});

test("token refresh uses expiry hints and is single-flight", async () => {
  let now = 1_000_000;
  let authCount = 0;
  const { client } = fixture({ now: () => now, respond: (url) => {
    if (url.pathname.endsWith("/auth/token")) { authCount++; return json({ access_token: `header.${Buffer.from(JSON.stringify({ exp: now / 1000 + 60 })).toString("base64url")}.signature` }); }
    return json(url.pathname.endsWith("/version") ? { version: "3.3.1" } : { dags: [], total_entries: 0 });
  } });
  await client.enable();
  now += 31_000;
  await Promise.all([client.read(operations[0]), client.read(operations[0])]);
  assert.equal(authCount, 2);
});

test("401 renews once, concurrent 401s do not invalidate a replacement; 403 does not retry", async () => {
  let authCount = 0;
  let forbidden = false;
  let failAll = false;
  const { client, secrets } = fixture({ respond: (url, init) => {
    if (url.pathname.endsWith("/auth/token")) return json({ access_token: `token-${++authCount}` });
    if (url.pathname.endsWith("/version")) return json({ version: "3.3.1" });
    if (forbidden) return json({ password: PASSWORD }, 403);
    if (failAll || new Headers(init.headers).get("Authorization") === "Bearer token-1") return json({ secret: PASSWORD }, 401);
    return json({ dags: [], total_entries: 0 });
  } });
  await client.enable();
  await Promise.all([client.read(operations[0]), client.read(operations[0])]);
  assert.equal(authCount, 2);
  assert.equal(secrets.length, 1);
  forbidden = true;
  await assert.rejects(client.read(operations[0]), /HTTP 403/);
  assert.equal(authCount, 2);
  forbidden = false;
  failAll = true;
  await assert.rejects(client.read(operations[0]), /HTTP 401/);
  assert.equal(authCount, 3);
});

test("auth errors, invalid token, wrong API version and non-JSON SSO response stay disabled and do not expose response bodies", async () => {
  for (const mode of ["auth-error", "missing-token", "wrong-version", "sso", "invalid-json"] as const) {
    const { client } = fixture({ respond: (url) => {
      if (url.pathname.endsWith("/auth/token")) return mode === "auth-error" ? json({ sensitive: PASSWORD }, 401) : json(mode === "missing-token" ? {} : { access_token: "token" });
      if (mode === "sso") return new Response(`<html>${PASSWORD}</html>`, { headers: { "content-type": "text/html" } });
      if (mode === "invalid-json") return new Response(PASSWORD, { headers: { "content-type": "application/json" } });
      return json({ version: "2.10.5", sensitive: PASSWORD });
    } });
    await assert.rejects(client.enable(), (error: Error) => !error.message.includes(PASSWORD));
    await assert.rejects(client.read(operations[0]), /airflow_enable/);
  }
});

test("fetch errors suppress URLs and credentials and redirects are forbidden", async () => {
  const { client } = fixture({ respond: () => { throw new Error(`https://${USER}:${PASSWORD}@example.test/?token=secret`); } });
  await assert.rejects(client.enable(), (error: Error) => /Redirects are never followed/.test(error.message) && !error.message.includes(PASSWORD) && !error.message.includes(USER));
});

test("log redaction and local/API pagination preserve every redacted character", async () => {
  const raw = `failure ${PASSWORD} ${USER} opaque-test-token\npassword=abc Bearer abc123\n` + "x".repeat(1500);
  const { client, requests } = fixture({ respond: (url) => {
    if (url.pathname.endsWith("/auth/token")) return json({ access_token: "opaque-test-token" });
    if (url.pathname.endsWith("/version")) return json({ version: "3.3.1" });
    return json({ content: raw, continuation_token: "next-api-page" });
  } });
  await client.enable();
  let charOffset = 0;
  let combined = "";
  while (true) {
    const result = await client.read({ operation: "logs", ...run, taskId: "load", tryNumber: 1, continuationToken: "current-page", maxChars: 500, charOffset });
    assert.equal(result.continuationToken, "next-api-page");
    combined += result.content;
    if (!result.pageTruncated) break;
    assert.match(result.pagination, /SAME/);
    charOffset = result.nextCharOffset;
  }
  assert.ok(combined.endsWith("x".repeat(1500)));
  for (const secret of [PASSWORD, USER, "opaque-test-token", "abc123", "password=abc"]) assert.ok(!combined.includes(secret));
  assert.ok(requests.slice(2).every(({ url }) => url.searchParams.get("token") === "current-page"));
  assert.equal(redactLog('Bearer abc Basic YWJj password="a b" https://u:pw@test/path?sig=xyz&x=1'), 'Bearer [REDACTED] Basic [REDACTED] password=[REDACTED] https://[REDACTED]@test/path?sig=[REDACTED]&x=1');
});

test("structured log arrays are retained and credentials with JSON metacharacters are redacted from metadata", async () => {
  const { client } = fixture({ respond: (url) => {
    if (url.pathname.endsWith("/auth/token")) return json({ access_token: "token" });
    if (url.pathname.endsWith("/version")) return json({ version: "3.3.1" });
    if (url.pathname.includes("/logs/")) return json({ content: [{ event: `Failed ${PASSWORD}`, level: "error" }], continuation_token: null });
    return json({ dag_id: "example", state: PASSWORD, conf: "hidden" });
  } });
  await client.enable();
  const logs = await client.read(operations[4]);
  assert.ok(logs.content.includes("error"));
  assert.ok(!logs.content.includes(PASSWORD));
  assert.ok(!logs.content.includes(JSON.stringify(PASSWORD).slice(1, -1)));
  assert.equal(JSON.parse(logs.content).event, "Failed [REDACTED]");
  assert.deepEqual(await client.read({ operation: "run", ...run }), { dag_id: "example", state: "[REDACTED]" });
});

test("bounded downloads reject oversized content without exposing it", async () => {
  const { client } = fixture({ respond: (url) => {
    if (url.pathname.endsWith("/auth/token")) return json({ access_token: "token" });
    if (url.pathname.endsWith("/version")) return json({ version: "3.3.1" });
    return json({ content: "x".repeat(4 * 1024 * 1024 + 1) });
  } });
  await client.enable();
  await assert.rejects(client.read(operations[4]), /download limit/);
});

test("output-shortened collections provide a non-skipping nextOffset", async () => {
  const { client } = fixture({ respond: (url) => {
    if (url.pathname.endsWith("/auth/token")) return json({ access_token: "token" });
    if (url.pathname.endsWith("/version")) return json({ version: "3.3.1" });
    return json({ dags: Array.from({ length: 100 }, (_, i) => ({ dag_id: `dag-${i}`, description: "x".repeat(2000) })), total_entries: 500 });
  } });
  await client.enable();
  const data = await client.read({ operation: "dags", limit: 100, offset: 10 });
  assert.ok(data.outputTruncated);
  assert.equal(data.nextOffset, 10 + data.items.length);
  assert.ok(JSON.stringify(data).length < 25_000);
});

test("cancellation, disposal, and an in-flight setup cannot resurrect credentials", async () => {
  const { client, requests } = fixture();
  await client.enable();
  const aborted = AbortSignal.abort();
  await assert.rejects(client.read(operations[0], aborted), /cancelled/);
  assert.equal(requests.length, 2);
  client.dispose();
  await assert.rejects(client.enable(), /cancelled/);
  await assert.rejects(client.read(operations[0]), /cancelled/);
  const finish: Array<(value: string) => void> = [];
  const pending = new AirflowClient({ readSecret: () => new Promise((resolve) => { finish.push(resolve); }) });
  const enabling = pending.enable();
  pending.dispose();
  for (const resolve of finish) resolve("test");
  await assert.rejects(enabling, /cancelled/);
});
