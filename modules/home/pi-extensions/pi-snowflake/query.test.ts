import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import piSnowflake from "./index.ts";
import { snowflakePolicy } from "./policy.ts";
import { boundedResult, buildCommand, DEFAULT_ROLE, FNOX_EXEC_TOOL, parseRows, validateQuery } from "./query.ts";

for (const sql of [
  "select 1", "with a as (select 1) select * from a; -- final comment",
  "show tables", "describe table example", "explain select 1",
  "select 'DROP; SYSTEM$TEST()', \"DELETE\" from example /* UPDATE */",
  "select 'it\\'s fine; still quoted'",
]) {
  test(`allows ${sql}`, () => assert.doesNotThrow(() => validateQuery(sql)));
}
for (const sql of [
  "", "-- only a comment", "delete from example", "select 1; select 2",
  "with a as (select 1) delete from example", "select SYSTEM$WAIT(1)",
  "select 'unterminated", "select 1 /* unterminated", "select 1\n!source /tmp/query.sql",
  "select 1; -- comment\ndrop table example", "!set output_format=JSON",
]) {
  test(`rejects ${JSON.stringify(sql)}`, () => assert.throws(() => validateQuery(sql)));
}

test("organization deny and allow rules still apply", () => {
  snowflakePolicy.denyQueryRules.push({ description: "restricted", pattern: /restricted/g });
  snowflakePolicy.allowQueryPatterns.push(/approved/g);
  try {
    assert.throws(() => validateQuery("select * from restricted"), /restricted/);
    assert.throws(() => validateQuery("select 1"), /allow rule/);
    assert.doesNotThrow(() => validateQuery("select * from approved"));
    assert.doesNotThrow(() => validateQuery("select * from approved"));
  } finally {
    snowflakePolicy.denyQueryRules.pop();
    snowflakePolicy.allowQueryPatterns.pop();
  }
});

test("parses rows and tolerates fnox's appended stderr", () => {
  assert.deepEqual(parseRows('[{"A":1}]\n\n[stderr]\nwarning'), [{ A: 1 }]);
  assert.deepEqual(parseRows("[]"), []);
  for (const text of ['[{"A":', '{}', '[null]', '[1]', '[[1]]']) {
    assert.throws(() => parseRows(text));
  }
});

test("bounds serialized results, including the oversized-first-row case", () => {
  const rows = [{ A: 1 }, { A: "x".repeat(snowflakePolicy.maxOutputCharacters) }];
  const result = boundedResult({ role: DEFAULT_ROLE }, rows);
  assert.deepEqual(result.rows, [rows[0]]);
  assert.equal(result.outputTruncated, true);
  assert.equal(result.returnedRowCount, 1);
  assert.ok(JSON.stringify(result, null, 2).length <= snowflakePolicy.maxOutputCharacters);
  const oversized = boundedResult({}, rows.slice(1));
  assert.deepEqual(oversized.rows, []);
  assert.equal(oversized.outputTruncated, true);
  assert.equal(boundedResult({}, []).outputTruncated, false);
});

function registeredTool() {
  let tool: any;
  piSnowflake({ registerTool: (definition: unknown) => { tool = definition; } } as any);
  return tool;
}

function context(exec: (name: string, args: any, options: any) => Promise<unknown>) {
  return { executeTool: exec };
}

function success(rows: unknown[]) {
  return { content: [{ type: "text", text: "truncated display" }], structuredContent: {
    content: [{ type: "text", text: JSON.stringify(rows) }],
  } };
}

test("direct tool delegates to MCP, uses full structured content, and resets the role", async () => {
  const tool = registeredTool();
  assert.equal(tool.exposure, "direct");
  assert.deepEqual(tool.reachesTools({}), [FNOX_EXEC_TOOL]);
  assert.equal(tool.parameters.properties.binds, undefined);
  const roles: string[] = [];
  const ctx = context(async (name, args, options) => {
    assert.equal(name, FNOX_EXEC_TOOL);
    assert.ok(options.signal instanceof AbortSignal);
    assert.equal(args.command[4], "select 1");
    roles.push(args.command[5]);
    return success([{ A: 1 }, { A: 2 }]);
  });
  const first = await tool.execute("1", { sql: "select 1", role: " OTHER_ROLE ", maxRows: 1 }, undefined, undefined, ctx);
  const second = await tool.execute("2", { sql: "select 1" }, undefined, undefined, ctx);
  assert.deepEqual(roles, ["OTHER_ROLE", DEFAULT_ROLE]);
  assert.equal(first.isError, undefined);
  assert.equal(JSON.parse(first.content[0].text).rowLimitApplied, true);
  assert.deepEqual(JSON.parse(first.content[0].text).rows, [{ A: 1 }]);
  assert.equal(JSON.parse(second.content[0].text).returnedRowCount, 2);
});

test("rejects invalid SQL, invalid limits, empty roles, and pre-cancellation before MCP", async () => {
  const tool = registeredTool();
  let calls = 0;
  const ctx = context(async () => { calls += 1; return success([]); });
  for (const input of [
    { sql: "delete from x" }, { sql: "select 1", role: " " },
    { sql: "select 1", maxRows: 0 }, { sql: "select 1", maxRows: 501 },
    { sql: "select 1", maxRows: 1.5 },
  ]) {
    assert.equal((await tool.execute("1", input, undefined, undefined, ctx)).isError, true);
  }
  const aborted = AbortSignal.abort();
  assert.equal((await tool.execute("1", { sql: "select 1" }, aborted, undefined, ctx)).isError, true);
  assert.equal(calls, 0);
});

test("propagates MCP errors and malformed JSON without returning rows", async () => {
  const tool = registeredTool();
  for (const response of [
    { content: [{ type: "text", text: "Unknown tool" }], isError: true },
    { structuredContent: { content: [{ type: "text", text: "Proton logged out" }], isError: true } },
    { content: [{ type: "text", text: "truncated JSON" }] },
  ]) {
    const result = await tool.execute("1", { sql: "select 1" }, undefined, undefined, context(async () => response));
    assert.equal(result.isError, true);
    assert.match(result.content[0].text, /Unknown tool|Proton logged out|complete JSON/);
  }
});

test("passes cancellation to nested execution", async () => {
  const controller = new AbortController();
  const result = await registeredTool().execute("1", { sql: "select 1" }, controller.signal, undefined, context(async (_name, _args, options) => {
    controller.abort();
    assert.equal(options.signal.aborted, true);
    return success([]);
  }));
  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /cancelled/);
});

test("policy deadline aborts the nested call and reports a timeout", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const pending = registeredTool().execute("1", { sql: "select 1" }, undefined, undefined, context(async (_name, _args, options) => {
    return new Promise((resolve) => options.signal.addEventListener("abort", () => resolve(success([])), { once: true }));
  }));
  t.mock.timers.tick(snowflakePolicy.timeoutSeconds * 1_000);
  const result = await pending;
  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /60-second policy timeout/);
});

test("launcher maps credentials only in child, isolates CLI config, and does not evaluate SQL or role", () => {
  const directory = mkdtempSync(join(tmpdir(), "pi-snowflake-test-"));
  const sql = "select '$(touch SHOULD_NOT_EXIST)'";
  const role = "ROLE_WITH_$(touch SHOULD_NOT_EXIST)";
  try {
    writeFileSync(join(directory, "snow"), `#!${process.execPath}
const fs = require('node:fs');
const assert = require('node:assert/strict');
const path = require('node:path');
assert.equal(process.env.SNOWFLAKE_PRIVATE_KEY_FILE, '/dummy/key.p8');
assert.equal(process.env.PRIVATE_KEY_PASSPHRASE, 'dummy-passphrase');
const args = process.argv.slice(2);
assert.equal(args[args.indexOf('--query') + 1], ${JSON.stringify(sql)});
assert.equal(args[args.indexOf('--role') + 1], ${JSON.stringify(role)});
assert.equal(args[args.indexOf('--enable-templating') + 1], 'NONE');
const config = args[1];
assert.equal(path.dirname(config), process.env.SNOWFLAKE_HOME);
assert.equal(fs.statSync(config).mode & 0o777, 0o600);
const text = fs.readFileSync(config, 'utf8');
assert.ok(text.includes('ROWS_PER_RESULTSET = 11'));
assert.ok(text.includes('STATEMENT_TIMEOUT_IN_SECONDS = 60'));
assert.ok(text.includes('MULTI_STATEMENT_COUNT = 1'));
assert.ok(!text.includes('dummy-passphrase'));
fs.writeFileSync(${JSON.stringify(join(directory, "config-path"))}, config);
console.log('[{"OK":true}]');
`, { mode: 0o700 });
    const command = buildCommand(sql, role, 10);
    const env = { PATH: directory + ":/usr/bin:/bin", SNOWFLAKE_KEYFILE_PATH: "/dummy/key.p8", SNOWFLAKE_KEYFILE_PASSWORD: "dummy-passphrase" };
    const result = spawnSync(command[0], command.slice(1), { cwd: directory, env, encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(parseRows(result.stdout), [{ OK: true }]);
    const configPath = readFileSync(join(directory, "config-path"), "utf8");
    assert.throws(() => readFileSync(configPath), /ENOENT/);
    assert.throws(() => readFileSync(join(directory, "SHOULD_NOT_EXIST")), /ENOENT/);
    const missing = spawnSync(command[0], command.slice(1), { env: { PATH: env.PATH }, encoding: "utf8" });
    assert.notEqual(missing.status, 0);
    assert.match(missing.stderr, /SNOWFLAKE_KEYFILE_PATH is missing/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
