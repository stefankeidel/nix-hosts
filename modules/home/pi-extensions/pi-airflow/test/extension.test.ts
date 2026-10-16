import assert from "node:assert/strict";
import { test } from "node:test";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Value } from "typebox/value";
import { registerAirflow } from "../index.ts";
import { SECRET_NAMES, type ClientOptions } from "../client.ts";

function harness(options: ClientOptions = {}) {
  const tools = new Map<string, any>();
  const events = new Map<string, Function>();
  let active = ["read", "bash", "codemode"];
  const pi = {
    registerTool(tool: any) { tools.set(tool.name, tool); if (tool.exposure === undefined) active.push(tool.name); },
    on(name: string, handler: Function) { events.set(name, handler); },
    getActiveTools() { return active; },
    setActiveTools(value: string[]) { active = value; },
  };
  const secrets: string[] = [];
  const requests: Array<{ path: string; method?: string }> = [];
  registerAirflow(pi as unknown as ExtensionAPI, {
    readSecret: async (name) => { secrets.push(name); assert.equal(name, SECRET_NAMES[0]); return "http://test-user:test-credential@lb-airflow-prod-api-server:8080/http"; },
    fetch: async (url, init) => {
      const path = new URL(String(url)).pathname;
      requests.push({ path, method: init?.method });
      const data = path.endsWith("/auth/token") ? { access_token: "test-access-token" } :
        path.endsWith("/version") ? { version: "3.3.1" } :
        path.endsWith("/logs/1") ? { content: "Example task failure", continuation_token: null } :
        path.endsWith("/taskInstances") ? { task_instances: [{ task_id: "load", try_number: 1, map_index: -1 }], total_entries: 1 } :
        path.endsWith("/dagRuns") ? { dag_runs: [{ dag_run_id: "scheduled__example", state: "failed" }], total_entries: 1 } :
        path.endsWith("/dags") ? { dags: [{ dag_id: "example" }], total_entries: 1 } : { dag_run_id: "scheduled__example", state: "failed" };
      return new Response(JSON.stringify(data), { headers: { "Content-Type": "application/json" } });
    },
    ...options,
  });
  async function call(name: string, params = {}) {
    const tool = tools.get(name);
    assert.ok(tool && tool.exposure !== "hidden", `${name} must be visible`);
    assert.ok(Value.Check(tool.parameters, params), `${name} arguments must satisfy the tool schema`);
    const result = await tool.execute("test-call", params, undefined, undefined, {});
    assert.ok(Value.Check(tool.outputSchema, result.structuredContent));
    assert.deepEqual(JSON.parse(result.content[0].text), result.structuredContent);
    return result;
  }
  return { tools, events, secrets, requests, call, get active() { return active; } };
}

test("initial load and session_start do no IO; only loader is callable until enable succeeds", async () => {
  const h = harness();
  h.events.get("session_start")!({ reason: "startup" });
  assert.equal(h.secrets.length, 0);
  assert.equal(h.requests.length, 0);
  assert.equal(h.tools.size, 6);
  assert.deepEqual([...h.tools.values()].filter((t) => t.exposure !== "hidden").map((t) => t.name), ["airflow_enable"]);
  const status = await h.call("airflow_enable");
  assert.equal(status.structuredContent.enabled, true);
  assert.ok(!JSON.stringify(status).includes("test-credential"));
  assert.ok(!JSON.stringify(status).includes("test-access-token"));
  assert.equal(h.secrets.length, 1);
  assert.ok(h.active.includes("bash"));
  assert.ok(h.active.includes("airflow_get_task_logs"));
  assert.ok([...h.tools.values()].every((t) => t.annotations.readOnlyHint && t.annotations.destructiveHint === false));
  await h.call("airflow_enable");
  assert.equal(h.requests.length, 2);
});

test("tool-level end-to-end discovery, runs, tasks, logs, read-only transport and structured results", async () => {
  const h = harness();
  await h.call("airflow_enable");
  assert.equal((await h.call("airflow_list_dags")).structuredContent.items[0].dag_id, "example");
  assert.equal((await h.call("airflow_list_dag_runs", { dagId: "example" })).structuredContent.items[0].state, "failed");
  const run = { dagId: "example", dagRunId: "scheduled__example" };
  assert.equal((await h.call("airflow_get_dag_run", run)).structuredContent.state, "failed");
  const task = (await h.call("airflow_list_task_instances", run)).structuredContent.items[0];
  const log = await h.call("airflow_get_task_logs", { ...run, taskId: task.task_id, tryNumber: task.try_number, mapIndex: task.map_index });
  assert.equal(log.structuredContent.content, "Example task failure");
  assert.deepEqual(h.requests.filter((r) => r.method !== "GET"), [{ path: "/auth/token", method: "POST" }]);
  assert.ok(![...h.tools.keys()].some((name) => /trigger|clear|delete|pause|retry|patch|raw/.test(name)));
});

test("shutdown and session changes clear credentials, hide readers, and preserve unrelated tools", async () => {
  const h = harness();
  await h.call("airflow_enable");
  h.events.get("session_shutdown")!({});
  assert.equal(h.tools.get("airflow_get_task_logs").exposure, "hidden");
  assert.ok(!h.active.includes("airflow_get_task_logs"));
  assert.ok(h.active.includes("bash"));
  await assert.rejects(h.call("airflow_enable"), /cancelled/);
  h.events.get("session_start")!({ reason: "new" });
  await h.call("airflow_enable");
  assert.equal(h.secrets.length, 2);
});

test("failed setup never exposes the read tools", async () => {
  const h = harness({ readSecret: async () => { throw new Error("Azure CLI login unavailable"); } });
  await assert.rejects(h.call("airflow_enable"), /Azure CLI/);
  assert.equal(h.tools.get("airflow_get_task_logs").exposure, "hidden");
  assert.ok(!h.active.includes("airflow_get_task_logs"));
});
