import { execFile } from "node:child_process";

export const VAULT_NAME = "kvlbeu2tdadataappsecp01";
// External TLS ingress from platform/.gitlab-ci.yml, not the cluster-internal connection host.
export const API_BASE_URL = "https://airflow.lichtblick.app";
export const SECRET_NAMES = ["airflow-connection-airflow-api-server"] as const;
type SecretName = typeof SECRET_NAMES[number];
type SecretReader = (name: SecretName, signal?: AbortSignal) => Promise<string>;
type Json = Record<string, any>;

/** No shell, no credentials in argv, and no raw CLI errors in tool results. */
export const readAzureSecret: SecretReader = (name, signal) => new Promise((resolve, reject) => {
  execFile("az", [
    "keyvault", "secret", "show", "--vault-name", VAULT_NAME, "--name", name,
    "--query", "value", "--output", "json", "--only-show-errors",
  ], { encoding: "utf8", timeout: 45_000, maxBuffer: 64 * 1024, signal }, (error, stdout) => {
    if (error) {
      reject(new Error(`Unable to read ${name} from Azure Key Vault. Check az login, vault permissions, and network access.`));
      return;
    }
    try {
      const value = JSON.parse(stdout);
      if (typeof value !== "string" || !value.trim()) throw new Error();
      resolve(value);
    } catch {
      reject(new Error(`Azure Key Vault returned no usable value for ${name}.`));
    }
  });
});

/** Airflow Key Vault connections may be JSON or percent-encoded Airflow connection URIs. */
export function parseConnectionCredentials(value: string): { username: string; password: string } {
  try {
    let username: unknown;
    let password: unknown;
    if (value.trimStart().startsWith("{")) {
      const connection = JSON.parse(value);
      username = connection.login;
      password = connection.password;
    } else {
      const connection = new URL(value.trim());
      if (!["http:", "https:"].includes(connection.protocol)) throw new Error();
      username = decodeURIComponent(connection.username);
      password = decodeURIComponent(connection.password);
    }
    if (typeof username !== "string" || typeof password !== "string" || !username.trim() || !password.trim() || username.length > 8192 || password.length > 8192) throw new Error();
    // Deliberately do not use host/schema/port or extras: those address the in-cluster service.
    return { username, password };
  } catch {
    throw new Error("Airflow connection secret must contain a valid connection URI or JSON with nonempty login and password. No secret contents were exposed.");
  }
}

export function normalizeBaseUrl(value: string): string {
  let url: URL;
  try { url = new URL(value.trim()); } catch { throw new Error("Airflow base URL is invalid."); }
  if (url.protocol !== "https:") {
    throw new Error("Airflow base URL must use HTTPS. Refusing to send credentials or tokens over HTTP; configure a secure endpoint or tunnel first.");
  }
  if (url.username || url.password || url.search || url.hash || /[%\\]/.test(value)) {
    throw new Error("Airflow base URL must not contain credentials, query parameters, fragments, or encoded paths.");
  }
  // Accept either the application root (including an ingress prefix) or /api/v2.
  url.pathname = url.pathname.replace(/\/+$/, "").replace(/\/api\/v2$/, "");
  if (/\/api\/v\d+(?:\/|$)/.test(url.pathname)) throw new Error("Only the Airflow 3 /api/v2 API is supported.");
  return url.href.replace(/\/$/, "");
}

function segment(value: string): string {
  if (typeof value !== "string" || !value || value.length > 1024 || /[/%\\?#\x00-\x20\x7f]/.test(value) || [".", "..", "~"].includes(value)) {
    throw new Error("Invalid Airflow identifier: path separators, escapes, wildcards, and control characters are not allowed.");
  }
  return encodeURIComponent(value);
}

function integer(value: number, min: number, max: number): number {
  if (!Number.isSafeInteger(value) || value < min || value > max) throw new Error(`Expected an integer between ${min} and ${max}.`);
  return value;
}

function text(value: string, max = 1024): string {
  if (typeof value !== "string" || value.length > max || /[\x00-\x1f\x7f]/.test(value)) throw new Error("Invalid Airflow filter or continuation token.");
  return value;
}

type Page = { limit?: number; offset?: number };
type Run = { dagId: string; dagRunId: string };
export type ReadRequest =
  | { operation: "dags"; pattern?: string } & Page
  | { operation: "runs"; dagId: string; state?: string } & Page
  | { operation: "run" } & Run
  | { operation: "tasks"; state?: string } & Run & Page
  | { operation: "logs"; taskId: string; tryNumber: number; mapIndex?: number; continuationToken?: string; charOffset?: number; maxChars?: number } & Run;

/** Closed operation set: there is intentionally no caller-supplied URL, method, or arbitrary query object. */
export function buildReadRequest(input: ReadRequest): { path: string; query: URLSearchParams } {
  const query = new URLSearchParams();
  let path: string;
  switch (input.operation) {
    case "dags":
      path = "/api/v2/dags";
      if (input.pattern) query.set("dag_id_pattern", text(input.pattern));
      break;
    case "runs":
      path = `/api/v2/dags/${segment(input.dagId)}/dagRuns`;
      query.set("order_by", "-run_after");
      if (input.state) query.set("state", text(input.state, 64));
      break;
    case "run":
      path = `/api/v2/dags/${segment(input.dagId)}/dagRuns/${segment(input.dagRunId)}`;
      break;
    case "tasks":
      path = `/api/v2/dags/${segment(input.dagId)}/dagRuns/${segment(input.dagRunId)}/taskInstances`;
      if (input.state) query.set("state", text(input.state, 64));
      break;
    case "logs":
      path = `/api/v2/dags/${segment(input.dagId)}/dagRuns/${segment(input.dagRunId)}/taskInstances/${segment(input.taskId)}/logs/${integer(input.tryNumber, 1, 1_000_000)}`;
      query.set("map_index", String(integer(input.mapIndex ?? -1, -1, 1_000_000_000)));
      query.set("full_content", "false");
      if (input.continuationToken) query.set("token", text(input.continuationToken, 16_384));
      integer(input.charOffset ?? 0, 0, Number.MAX_SAFE_INTEGER);
      integer(input.maxChars ?? 12_000, 500, 20_000);
      break;
    default:
      throw new Error("Rejected by Airflow read-only policy: unsupported operation.");
  }
  if (input.operation === "dags" || input.operation === "runs" || input.operation === "tasks") {
    query.set("limit", String(integer(input.limit ?? 25, 1, 100)));
    query.set("offset", String(integer(input.offset ?? 0, 0, 1_000_000_000)));
  }
  return { path, query };
}

class SafeError extends Error {}

async function boundedJson(response: Response, maxBytes: number): Promise<Json> {
  if (!response.headers.get("content-type")?.toLowerCase().includes("application/json")) {
    await response.body?.cancel();
    throw new SafeError("Airflow returned non-JSON content (possibly an SSO login page). No response body was exposed.");
  }
  const reader = response.body?.getReader();
  if (!reader) throw new SafeError("Airflow returned an empty response.");
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) throw new SafeError("Airflow response exceeded the safe download limit. Narrow the request.");
      chunks.push(value);
    }
  } finally {
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
  try {
    const result = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (!result || typeof result !== "object" || Array.isArray(result)) throw new Error();
    return result;
  } catch {
    throw new SafeError("Airflow returned invalid JSON. No response body was exposed.");
  }
}

function pick(value: Json, fields: readonly string[]): Json {
  return Object.fromEntries(fields.filter((key) => key in value).flatMap((key) => {
    const item = value[key];
    // Do not expose nested arbitrary metadata (conf, rendered fields, connections, XComs, etc.).
    if (typeof item === "string") return [[key, item.slice(0, 2000)]];
    if (item === null || typeof item === "number" || typeof item === "boolean") return [[key, item]];
    return [];
  }));
}

const dagFields = ["dag_id", "dag_display_name", "is_paused", "is_stale", "has_import_errors", "last_parsed_time", "next_dagrun", "description"];
const runFields = ["dag_id", "dag_run_id", "state", "run_type", "logical_date", "run_after", "start_date", "end_date", "data_interval_start", "data_interval_end"];
const taskFields = ["dag_id", "dag_run_id", "task_id", "task_display_name", "state", "try_number", "map_index", "start_date", "end_date", "duration", "operator"];

/** Best effort only; Airflow must also mask secrets at source. */
export function redactLog(value: string): string {
  return value
    .replace(/\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+/gi, "$1 [REDACTED]")
    .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g, "[REDACTED_JWT]")
    .replace(/((?:password|passwd|secret|access_token|refresh_token|api[_-]?key|authorization)["']?\s*[:=]\s*)(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s,;]+)/gi, "$1[REDACTED]")
    .replace(/(https?:\/\/)[^\s/@:]+:[^\s/@]+@/gi, "$1[REDACTED]@")
    .replace(/([?&](?:sig|token|api[_-]?key|password)=)[^\s&#"']+/gi, "$1[REDACTED]")
    .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "");
}

type Token = { value: string; expiresAt: number };
type Credentials = { root: string; username: string; password: string };
export type ClientOptions = { readSecret?: SecretReader; fetch?: typeof fetch; now?: () => number };

export class AirflowClient {
  private readonly readSecret: SecretReader;
  private readonly fetcher: typeof fetch;
  private readonly now: () => number;
  private readonly lifetime = new AbortController();
  private credentials?: Credentials;
  private setupPromise?: Promise<{ version: string }>;
  private tokenPromise?: Promise<Token>;
  private token?: Token;
  private enabled = false;

  constructor(options: ClientOptions = {}) {
    this.readSecret = options.readSecret ?? readAzureSecret;
    this.fetcher = options.fetch ?? globalThis.fetch;
    this.now = options.now ?? Date.now;
  }

  dispose(): void {
    this.lifetime.abort();
    this.enabled = false;
    this.credentials = undefined;
    this.token = undefined;
    this.setupPromise = undefined;
    this.tokenPromise = undefined;
  }

  private check(signal?: AbortSignal): void {
    if (this.lifetime.signal.aborted || signal?.aborted) throw new SafeError("Airflow request cancelled.");
  }

  async enable(signal?: AbortSignal): Promise<{ version: string }> {
    this.check(signal);
    if (!this.setupPromise) {
      this.setupPromise = this.setup(signal).catch((error) => {
        this.setupPromise = undefined;
        throw error;
      });
    }
    return this.setupPromise;
  }

  private async setup(signal?: AbortSignal): Promise<{ version: string }> {
    // Single-flight setup; nothing is saved to disk or returned to the model.
    if (!this.credentials) {
      const combined = signal ? AbortSignal.any([signal, this.lifetime.signal]) : this.lifetime.signal;
      const connection = await this.readSecret(SECRET_NAMES[0], combined);
      this.check(signal);
      const { username, password } = parseConnectionCredentials(connection);
      const root = normalizeBaseUrl(API_BASE_URL);
      this.credentials = { root, username, password };
    }
    const version = await this.get("/api/v2/version", new URLSearchParams(), signal);
    if (typeof version.version !== "string" || !/^3\./.test(version.version)) {
      throw new SafeError("Expected an Airflow 3 API version response. Tools remain disabled.");
    }
    this.check(signal);
    this.enabled = true;
    return { version: this.redactKnown(version.version.slice(0, 100)) };
  }

  private async request(path: string, token: string | undefined, query: URLSearchParams, signal?: AbortSignal): Promise<Response> {
    this.check(signal);
    if (!this.credentials) throw new SafeError("Call airflow_enable first.");
    if (token === undefined && path !== "/auth/token") throw new SafeError("Rejected non-authentication POST.");
    const signals = [this.lifetime.signal, AbortSignal.timeout(30_000), ...(signal ? [signal] : [])];
    try {
      // Only token issuance can POST. This function is private; every other path is a fixed GET.
      return await this.fetcher(`${this.credentials.root}${path}${query.size ? `?${query}` : ""}`, {
        method: token === undefined ? "POST" : "GET",
        redirect: "error",
        headers: token === undefined
          ? { "Content-Type": "application/json", Accept: "application/json" }
          : { Authorization: `Bearer ${token}`, Accept: "application/json" },
        body: token === undefined ? JSON.stringify({ username: this.credentials.username, password: this.credentials.password }) : undefined,
        signal: AbortSignal.any(signals),
      });
    } catch {
      this.check(signal);
      throw new SafeError("Airflow network request failed or timed out. Check VPN/private-network access, TLS, and whether the endpoint redirects to SSO. Redirects are never followed.");
    }
  }

  private async accessToken(signal?: AbortSignal): Promise<Token> {
    this.check(signal);
    if (this.token && this.token.expiresAt > this.now() + 30_000) return this.token;
    if (!this.tokenPromise) {
      this.tokenPromise = this.authenticate(signal).finally(() => { this.tokenPromise = undefined; });
    }
    return this.tokenPromise;
  }

  private async authenticate(signal?: AbortSignal): Promise<Token> {
    const response = await this.request("/auth/token", undefined, new URLSearchParams(), signal);
    if (!response.ok) {
      await response.body?.cancel();
      throw new SafeError(`Airflow token authentication failed (HTTP ${response.status}). Check the vault credentials and API auth manager.`);
    }
    const data = await boundedJson(response, 64 * 1024);
    if (typeof data.access_token !== "string" || !data.access_token || data.access_token.length > 32_768 || /\s/.test(data.access_token)) {
      throw new SafeError("Airflow authentication returned no usable access token.");
    }
    let expiresAt = this.now() + 5 * 60_000;
    if (typeof data.expires_in === "number" && Number.isFinite(data.expires_in) && data.expires_in > 0) {
      expiresAt = Math.min(expiresAt, this.now() + data.expires_in * 1000);
    }
    // JWT payload is only an expiry hint, not a claim that we have verified the signature.
    try {
      const claims = JSON.parse(Buffer.from(data.access_token.split(".")[1], "base64url").toString("utf8"));
      if (typeof claims.exp === "number" && Number.isFinite(claims.exp)) expiresAt = Math.min(expiresAt, claims.exp * 1000);
    } catch { /* Opaque tokens are refreshed conservatively. */ }
    this.check(signal);
    this.token = { value: data.access_token, expiresAt };
    return this.token;
  }

  private async get(path: string, query: URLSearchParams, signal?: AbortSignal): Promise<Json> {
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const token = await this.accessToken(signal);
      const response = await this.request(path, token.value, query, signal);
      if (response.status === 401 && attempt === 0) {
        await response.body?.cancel();
        // Do not invalidate a replacement obtained by a concurrent request.
        if (this.token === token) this.token = undefined;
        continue;
      }
      if (!response.ok) {
        await response.body?.cancel();
        throw new SafeError(`Airflow read failed (HTTP ${response.status}). ${response.status === 403 ? "The API account lacks read permission." : "No response body was exposed."}`);
      }
      try {
        const result = await boundedJson(response, 4 * 1024 * 1024);
        this.check(signal);
        return result;
      } catch (error) {
        if (error instanceof SafeError) throw error;
        this.check(signal);
        throw new SafeError("Unable to read the Airflow response; the connection may have timed out.");
      }
    }
    throw new SafeError("Airflow authentication retry exhausted.");
  }

  private redactKnown(value: string): string {
    for (const secret of [this.credentials?.password, this.credentials?.username, this.token?.value]) {
      if (secret) value = value.replaceAll(secret, "[REDACTED]");
    }
    return value;
  }

  private sanitize(value: any, logs = false): any {
    if (typeof value === "string") return logs ? redactLog(this.redactKnown(value)) : this.redactKnown(value);
    if (Array.isArray(value)) return value.map((item) => this.sanitize(item, logs));
    if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([key, item]) =>
      [this.redactKnown(key), this.sanitize(item, logs)]));
    return value;
  }

  async read(input: ReadRequest, signal?: AbortSignal): Promise<Json> {
    this.check(signal);
    if (!this.enabled) throw new SafeError("Call airflow_enable before using Airflow read tools.");
    const { path, query } = buildReadRequest(input);
    const data = await this.get(path, query, signal);
    let result: Json;
    if (input.operation === "logs") {
      if (typeof data.content !== "string" && !Array.isArray(data.content)) throw new SafeError("Unexpected Airflow log response format.");
      // Structured messages must be redacted BEFORE JSON escaping, not after.
      const safeContent = this.sanitize(data.content, true);
      const content = typeof safeContent === "string" ? safeContent : safeContent.map((entry: unknown) =>
        typeof entry === "string" ? entry : JSON.stringify(entry)).join("\n");
      const offset = input.charOffset ?? 0;
      const chunk = content.slice(offset, offset + (input.maxChars ?? 12_000));
      const truncated = offset + chunk.length < content.length;
      result = {
        content: chunk, charOffset: offset, nextCharOffset: truncated ? offset + chunk.length : null,
        pageTruncated: truncated,
        continuationToken: typeof data.continuation_token === "string" ? this.redactKnown(text(data.continuation_token, 16_384)) : null,
        pagination: truncated ? "Repeat with the SAME continuationToken input and nextCharOffset to finish this API page. Only then use the returned continuationToken with charOffset=0." : "For the next API page, pass the returned continuationToken with charOffset=0. A token alone does not prove more logs exist; stop if no progress is made.",
      };
    } else if (input.operation === "run") {
      result = pick(data, runFields);
    } else {
      const key = input.operation === "dags" ? "dags" : input.operation === "runs" ? "dag_runs" : "task_instances";
      const fields = input.operation === "dags" ? dagFields : input.operation === "runs" ? runFields : taskFields;
      if (!Array.isArray(data[key])) throw new SafeError("Unexpected Airflow collection response format.");
      const items: Json[] = [];
      for (const item of data[key].slice(0, input.limit ?? 25)) {
        if (!item || typeof item !== "object") throw new SafeError("Unexpected Airflow collection item.");
        const candidate = pick(item, fields);
        if (JSON.stringify([...items, candidate]).length > 24_000) break;
        items.push(candidate);
      }
      const offset = input.offset ?? 0;
      const total = typeof data.total_entries === "number" ? data.total_entries : null;
      const more = items.length < data[key].length || (total !== null && offset + items.length < total);
      result = { items, totalEntries: total, offset, nextOffset: more && items.length ? offset + items.length : null, outputTruncated: items.length < data[key].length };
    }
    // Redact values before JSON escaping so quotes/backslashes in secrets cannot bypass masking.
    // Rebuilding also ensures both model-facing and structured output are sanitized.
    return input.operation === "logs" ? result : this.sanitize(result);
  }
}
