import assert from "node:assert/strict";
import { test } from "node:test";
import { request, type Exec } from "../client.ts";

function response(data: unknown) {
  return { code: 0, stdout: JSON.stringify(Buffer.from(JSON.stringify(data)).toString("base64")), stderr: "" };
}

test("transport sends data as base64, never as executable Lisp or shell input", async () => {
  const input = { operation: "create", title: '\"); (delete-file "danger") ;', body: 'Unicode: grüße\n%(error "no") ${title}' };
  const exec: Exec = async (command, args, options) => {
    assert.equal(command, "emacsclient");
    assert.ok(args.includes("--alternate-editor=false"));
    assert.ok(args.includes("--quiet"));
    assert.equal(options.timeout, 20_000);
    assert.equal(options.maxBuffer, 256 * 1024);
    const expression = args.at(-1)!;
    assert.ok(!expression.includes("delete-file"));
    const encoded = expression.match(/pi-vulpea-dispatch-json "([A-Za-z0-9+/=]+)"/)![1];
    assert.deepEqual(JSON.parse(Buffer.from(encoded, "base64").toString("utf8")), input);
    assert.ok(expression.includes("bridge.el"));
    return response({ ok: true, data: { created: true, title: "grüße" } });
  };
  assert.deepEqual(await request(exec, input), { created: true, title: "grüße" });
});

test("bridge errors and invalid transport fail closed, without automatic retries", async () => {
  for (const result of [
    { code: 1, stdout: "", stderr: "missing server" },
    { code: 0, stdout: "not JSON", stderr: "" },
    { ...response({ ok: true, data: {} }), killed: true },
    { ...response({ ok: true, data: {} }), truncated: true },
    response({ ok: false, error: "Target has unsaved edits" }),
  ]) {
    let calls = 0;
    await assert.rejects(request(async () => { calls++; return result; }, { operation: "status" }));
    assert.equal(calls, 1);
  }
});

test("abort before launch does not contact Emacs", async () => {
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(request(async () => { throw new Error("must not execute"); }, { operation: "status" }, controller.signal), /abort/i);
});

test("large responses cannot flood model context", async () => {
  await assert.rejects(request(async () => response({ ok: true, data: { content: "x".repeat(50_001) } }), { operation: "read" }), /50KB/);
});
