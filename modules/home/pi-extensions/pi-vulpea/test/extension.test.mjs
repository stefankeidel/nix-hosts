import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

// NODE_PATH can point at Pi's packaged node_modules; no vendored runtime dependencies.
const require = createRequire(import.meta.url);
const { createJiti } = require("jiti");
const jiti = createJiti(import.meta.url, {
  alias: {
    "@earendil-works/pi-coding-agent": require.resolve.paths("@earendil-works/pi-coding-agent")
      .map((path) => join(path, "@earendil-works/pi-coding-agent/dist/index.js")).find(existsSync),
    "typebox": require.resolve("typebox"),
  },
});
const { default: extension } = await jiti.import("../index.ts");
const { Value } = require("typebox/value");

function harness() {
  const tools = new Map();
  const handlers = new Map();
  const calls = [];
  extension({
    registerTool(tool) { tools.set(tool.name, tool); },
    on(name, handler) { handlers.set(name, handler); },
    async exec(command, args, options) {
      const encoded = args.at(-1).match(/pi-vulpea-dispatch-json "([A-Za-z0-9+/=]+)"/)[1];
      const input = JSON.parse(Buffer.from(encoded, "base64").toString("utf8"));
      calls.push({ command, input, options });
      const data = input.operation === "status" ? { vault: "/tmp/pi-vulpea-unit-vault/" } :
        input.operation === "read" ? { note: { file: "area.org", id: input.id }, revision: "a".repeat(64) } : { updated: true };
      return { code: 0, stderr: "", stdout: JSON.stringify(Buffer.from(JSON.stringify({ ok: true, data })).toString("base64")) };
    },
  });
  async function call(name, params, ctx) {
    const tool = tools.get(name);
    assert.ok(Value.Check(tool.parameters, params), "Parameters must satisfy schema");
    return tool.execute("unit", params, undefined, undefined, ctx);
  }
  return { tools, handlers, calls, call };
}

test("registration has no Emacs IO and permanent guidance covers the actual PARA model", () => {
  const h = harness();
  assert.equal(h.calls.length, 0);
  assert.equal(h.tools.size, 6);
  const prompt = h.handlers.get("before_agent_start")({ systemPrompt: "original" }).systemPrompt;
  assert.ok(prompt.startsWith("original"));
  for (const text of ["people", "@FirstLast", "FILE-LEVEL", "No resource tag", "unsaved", "untrusted", "Jira/GitLab"])
    assert.ok(prompt.includes(text), text);
  for (const name of ["vulpea_status", "vulpea_list", "vulpea_read", "vulpea_search"])
    assert.equal(h.tools.get(name).annotations.readOnlyHint, true);
  for (const name of ["vulpea_create", "vulpea_update"])
    assert.equal(h.tools.get(name).annotations.destructiveHint, true);
});

test("read calls need no UI and return structured data", async () => {
  const h = harness();
  const result = await h.call("vulpea_status", {}, { hasUI: false });
  assert.equal(result.structuredContent.vault, "/tmp/pi-vulpea-unit-vault/");
  assert.deepEqual(JSON.parse(result.content[0].text), result.structuredContent);
});

test("denied and headless mutations never contact Emacs", async () => {
  const h = harness();
  const params = { kind: "resource", title: "OAuth" };
  await assert.rejects(h.call("vulpea_create", params, { hasUI: false }), /interactive/);
  await assert.rejects(h.call("vulpea_create", params, { hasUI: true, ui: { confirm: async () => false } }), /cancelled/);
  assert.equal(h.calls.length, 0);
});

test("approved existing-note writes preflight and queue the actual file", async () => {
  const h = harness();
  const params = { id: "test-id", revision: "a".repeat(64), action: "append", text: "A reusable finding" };
  let preview;
  const result = await h.call("vulpea_update", params, { hasUI: true, ui: { confirm: async (_title, body) => { preview = body; return true; } } });
  assert.ok(preview.includes(params.text));
  assert.deepEqual(h.calls.map((call) => call.input.operation), ["read", "status", "update"]);
  assert.equal(h.calls.at(-1).input.revision, params.revision);
  assert.equal(result.structuredContent.updated, true);
});
