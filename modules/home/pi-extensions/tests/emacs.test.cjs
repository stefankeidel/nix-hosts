// Run with NODE_PATH pointing at Pi's lib/node_modules (which supplies jiti and typebox).
const { test, before } = require("node:test");
const assert = require("node:assert/strict");
const { createJiti } = require("jiti");
let register, encodeRequest, decodeResponse;
before(async () => {
  ({ default: register, encodeRequest, decodeResponse } = await createJiti(__filename).import("../emacs.ts"));
});

function fixture(attached = true) {
  const previous = { ...process.env };
  if (attached) {
    process.env.PI_EMACS_SOCKET = "/tmp/emacs exact socket";
    process.env.PI_EMACS_SESSION = 'session"test';
    process.env.PI_EMACS_CLIENT = "/test/emacsclient";
  } else {
    delete process.env.PI_EMACS_SOCKET;
    delete process.env.PI_EMACS_SESSION;
  }
  const tools = new Map();
  const calls = [];
  const response = { code: 0, stdout: JSON.stringify(Buffer.from(JSON.stringify({ ok: true, result: { value: "42" } })).toString("base64")), stderr: "" };
  const pi = {
    registerTool(tool) { tools.set(tool.name, tool); },
    on() {},
    async exec(...args) { calls.push(args); return response; },
  };
  try { register(pi); } finally { process.env = previous; }
  return { tools, calls, response };
}

const context = (allowed = true, hasUI = true) => ({ hasUI, ui: { confirm: async () => allowed } });

test("does not register tools outside Emacs", () => {
  assert.equal(fixture(false).tools.size, 0);
});

test("request transports arbitrary text as data, not Elisp syntax", () => {
  const request = { code: '\") (kill-emacs) ;\n\\', session: "test" };
  const encoded = encodeRequest(request);
  assert.match(encoded, /^\(stefan-pi-request "[A-Za-z0-9+/=]+"\)$/);
  assert.deepEqual(JSON.parse(Buffer.from(encoded.split('"')[1], "base64").toString()), request);
});

test("decodes response and rejects Emacs errors", () => {
  assert.deepEqual(decodeResponse(JSON.stringify(Buffer.from('{"ok":true,"result":{"value":"42"}}').toString("base64"))), { value: "42" });
  assert.throws(() => decodeResponse(JSON.stringify(Buffer.from('{"ok":false,"error":"dead source"}').toString("base64"))), /dead source/);
  assert.throws(() => decodeResponse('"invalid!"'), /Invalid response/);
});

test("context uses exact socket and disables fallback Emacs startup", async () => {
  const f = fixture();
  await f.tools.get("emacs_context").execute("id", {});
  assert.equal(f.calls[0][0], "/test/emacsclient");
  assert.deepEqual(f.calls[0][1].slice(0, 4), ["--socket-name", "/tmp/emacs exact socket", "--alternate-editor=", "--eval"]);
});

test("eval requires approval and fails closed without UI", async () => {
  const f = fixture();
  const tool = f.tools.get("emacs_eval");
  await assert.rejects(tool.execute("id", { code: "(+ 1 2)" }, undefined, undefined, context(false)), /declined/);
  await assert.rejects(tool.execute("id", { code: "(+ 1 2)" }, undefined, undefined, context(true, false)), /interactive confirmation/);
  assert.equal(f.calls.length, 0);
  await tool.execute("id", { code: "(+ 1 2)" }, undefined, undefined, context());
  assert.equal(f.calls.length, 1);
});

test("cancelled eval never reaches Emacs", async () => {
  const f = fixture();
  await assert.rejects(f.tools.get("emacs_eval").execute("id", { code: "t" }, AbortSignal.abort(), undefined, context()));
  assert.equal(f.calls.length, 0);
});

test("real emacsclient round trip", { skip: !process.env.PI_EMACS_TEST_SOCKET }, async () => {
  const { execFile } = require("node:child_process");
  const { promisify } = require("node:util");
  const previous = { ...process.env };
  const tools = new Map();
  process.env.PI_EMACS_SOCKET = process.env.PI_EMACS_TEST_SOCKET;
  process.env.PI_EMACS_SESSION = "smoke";
  process.env.PI_EMACS_CLIENT = "emacsclient";
  try {
    register({
      registerTool(tool) { tools.set(tool.name, tool); },
      on() {},
      async exec(command, args, options) {
        const result = await promisify(execFile)(command, args, options);
        return { ...result, code: 0 };
      },
    });
  } finally { process.env = previous; }
  const result = await tools.get("emacs_eval").execute("id", { code: '(insert "live unsaved text") (+ 20 22)' }, undefined, undefined, context());
  assert.equal(JSON.parse(result.content[0].text).value, "42");
  const source = await tools.get("emacs_context").execute("id", {});
  assert.equal(JSON.parse(source.content[0].text).excerpt, "live unsaved text");
  assert.equal(JSON.parse(source.content[0].text).modified, true);
});

test("client failures and output limits are errors", async () => {
  for (const failure of [{ code: 1, stderr: "socket unavailable" }, { killed: true }, { truncated: true }]) {
    const f = fixture();
    Object.assign(f.response, failure);
    await assert.rejects(f.tools.get("emacs_context").execute("id", {}), /Emacs bridge failed/);
  }
});
