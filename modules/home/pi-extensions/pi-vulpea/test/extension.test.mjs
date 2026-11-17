import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

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
  const root = mkdtempSync(join(tmpdir(), "pi-vulpea-extension-"));
  const previous = process.env.PI_VULPEA_VAULT;
  process.env.PI_VULPEA_VAULT = root;
  const tools = new Map(); const handlers = new Map();
  extension({ registerTool(tool) { tools.set(tool.name, tool); }, on(name, handler) { handlers.set(name, handler); } });
  async function call(name, params, ctx = { hasUI: false, ui: { confirm: async () => false } }) {
    const tool = tools.get(name);
    assert.ok(Value.Check(tool.parameters, params), "Parameters must satisfy schema");
    return tool.execute("unit", params, undefined, undefined, ctx);
  }
  function cleanup() {
    rmSync(root, { recursive: true, force: true });
    if (previous === undefined) delete process.env.PI_VULPEA_VAULT; else process.env.PI_VULPEA_VAULT = previous;
  }
  return { root, tools, handlers, call, cleanup };
}

test("registration is inert and permanent guidance covers PARA conventions", () => {
  const h = harness();
  try {
    assert.equal(h.tools.size, 7);
    const prompt = h.handlers.get("before_agent_start")({ systemPrompt: "original" }).systemPrompt;
    assert.ok(prompt.startsWith("original"));
    for (const text of ["people", "@FirstLast", "FILE-LEVEL", "No resource tag", "untrusted", "Jira/GitLab"])
      assert.ok(prompt.includes(text), text);
    for (const name of ["vulpea_status", "vulpea_list", "vulpea_read", "vulpea_search"])
      assert.equal(h.tools.get(name).annotations.readOnlyHint, true);
    for (const name of ["vulpea_create", "vulpea_update", "vulpea_delete"])
      assert.equal(h.tools.get(name).annotations.destructiveHint, true);
  } finally { h.cleanup(); }
});

test("filesystem status, create, and update work without Emacs or approval", async () => {
  const h = harness();
  try {
    const status = await h.call("vulpea_status", {});
    assert.equal(status.structuredContent.backend, "filesystem");
    const created = await h.call("vulpea_create", { kind: "resource", title: "OAuth" });
    const id = created.structuredContent.note.id;
    const result = await h.call("vulpea_update", { id, revision: created.structuredContent.revision, action: "append", text: "A reusable finding" });
    assert.match(result.structuredContent.content, /A reusable finding/);
    assert.deepEqual(JSON.parse(result.content[0].text), result.structuredContent);
  } finally { h.cleanup(); }
});

test("headless deletion is blocked before any file operation", async () => {
  const h = harness();
  try {
    await assert.rejects(h.call("vulpea_delete", { id: "test-id", revision: "a".repeat(64) }), /interactive/);
  } finally { h.cleanup(); }
});

test("declining deletion performs no mutation", async () => {
  const h = harness();
  try {
    const created = await h.call("vulpea_create", { kind: "resource", title: "OAuth resource" });
    const id = created.structuredContent.note.id;
    await assert.rejects(h.call("vulpea_delete", { id, revision: created.structuredContent.revision },
      { hasUI: true, ui: { confirm: async (_title, body) => {
        assert.match(body, /OAuth resource/); assert.match(body, /children/); return false;
      } } }), /cancelled/);
    const stillThere = await h.call("vulpea_read", { id });
    assert.equal(stillThere.structuredContent.note.id, id);
  } finally { h.cleanup(); }
});
