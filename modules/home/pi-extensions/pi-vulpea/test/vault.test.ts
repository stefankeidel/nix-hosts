import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readdirSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { request } from "../vault.ts";

function vault(run: (call: (input: Record<string, unknown>) => Promise<Record<string, unknown>>, root: string) => Promise<void>) {
  return async () => {
    const temp = mkdtempSync(join(tmpdir(), "pi-vulpea-"));
    const root = join(temp, "vault"); mkdirSync(root);
    const old = process.env.PI_VULPEA_VAULT; const oldHome = process.env.HOME;
    process.env.PI_VULPEA_VAULT = root; process.env.HOME = temp;
    try { await run(request, root); }
    finally {
      if (old === undefined) delete process.env.PI_VULPEA_VAULT; else process.env.PI_VULPEA_VAULT = old;
      if (oldHome === undefined) delete process.env.HOME; else process.env.HOME = oldHome;
      rmSync(temp, { recursive: true, force: true });
    }
  };
}

test("filesystem status and literal search need no Emacs client", vault(async (call, root) => {
  assert.equal((await call({ operation: "status" })).vault, realpathSync(root));
  mkdirSync(join(root, "resource"));
  writeFileSync(join(root, "resource", "a.org"), ":PROPERTIES:\n:ID: area-id\n:END:\n#+title: A reference\n\nverified phrase\n");
  const result = await call({ operation: "search", query: "VERIFIED" });
  assert.equal((result.items as any[])[0].file, "resource/a.org");
}));

test("creates standalone resources and people with UUIDs and expected containers", vault(async (call) => {
  const resource = await call({ operation: "create", kind: "resource", title: "A reference", body: "Facts." });
  const resourceNote = resource.note as any;
  assert.match(resourceNote.id, /^[0-9a-f-]{36}$/);
  assert.equal(resourceNote.title, "A reference");
  const person = await call({ operation: "create", kind: "person", title: "Jane Doe" });
  const personNote = person.note as any;
  assert.ok(personNote.buckets.includes("person"));
  assert.match(person.content as string, /^:PROPERTIES:/);
  assert.match(person.content as string, /^\* Meetings/m);
  assert.match(person.content as string, /^\* Tasks/m);
}));

test("creates projects/tasks, reads and updates with whole-file revision checks", vault(async (call, root) => {
  mkdirSync(join(root, "areas"));
  writeFileSync(join(root, "areas", "area.org"), ":PROPERTIES:\n:ID: area-id\n:END:\n#+title: Central Data\n#+filetags: :area:\n\n* Notes\n:PROPERTIES:\n:ID: notes-id\n:END:\n\n* Tasks\n:PROPERTIES:\n:ID: tasks-id\n:END:\n");
  const area = await call({ operation: "read", id: "area-id" });
  const project = await call({ operation: "create", kind: "project", title: "Improve model", parentId: "area-id", revision: area.revision });
  const projectNote = project.note as any;
  assert.equal(projectNote.todo, "TODO");
  assert.ok(projectNote.tags.includes("project"));
  assert.ok(project.content && String(project.content).includes(":CATEGORY: Central Data > Improve model"));
  const projectRead = await call({ operation: "read", id: projectNote.id });
  const task = await call({ operation: "create", kind: "task", title: "Verify output", parentId: projectNote.id, revision: projectRead.revision });
  const taskNote = task.note as any;
  assert.equal(taskNote.todo, "TODO");
  await call({ operation: "update", id: taskNote.id, revision: task.revision, action: "todo", text: "DONE" });
  const latest = await call({ operation: "read", id: taskNote.id });
  assert.equal((latest.note as any).todo, "DONE");
  await assert.rejects(call({ operation: "update", id: taskNote.id, revision: task.revision, action: "todo", text: "TODO" }), /revision changed/);
  assert.equal(((await call({ operation: "list", kind: "project" })).items as any[]).length, 1);
  assert.ok((await call({ operation: "search", query: "Verify output" })).items);
}));

test("indexes an existing heading and archives only finished subtrees", vault(async (call, root) => {
  mkdirSync(join(root, "areas"));
  writeFileSync(join(root, "areas", "area.org"), ":PROPERTIES:\n:ID: area-id\n:END:\n#+title: Area\n#+filetags: :area:\n\n* Notes\n** Finding\nEvidence.\n");
  const area = await call({ operation: "read", id: "area-id" });
  const indexed = await call({ operation: "update", id: "area-id", revision: area.revision, action: "index", outline: ["Notes", "Finding"] });
  const id = (indexed.note as any).id;
  assert.ok(id);
  const read = await call({ operation: "read", id });
  assert.equal((read.note as any).title, "Finding");
  await call({ operation: "update", id, revision: read.revision, action: "archive" });
  assert.equal(((await call({ operation: "list", kind: "all" })).items as any[]).some(n => n.id === id), false);
  assert.equal(((await call({ operation: "search", query: "Evidence" })).items as any[]).length, 1);
}));

test("moves only standalone resources into the system trash", vault(async (call, root) => {
  const created = await call({ operation: "create", kind: "resource", title: "Disposable" });
  const id = (created.note as any).id;
  const deleted = await call({ operation: "delete", id, revision: created.revision });
  assert.equal(deleted.deleted, true);
  assert.equal(deleted.destination, "trash");
  assert.ok(readdirSync(join(root, "..", ".Trash")).some(name => name.startsWith(`${id}.org`)));
  assert.equal(((await call({ operation: "list", kind: "resource" })).items as any[]).length, 0);
  assert.equal(((await call({ operation: "search", query: "Disposable" })).items as any[]).length, 0);
}));

test("refuses resource directories that escape the vault through symlinks", vault(async (call, root) => {
  const outside = join(root, "..", "outside"); mkdirSync(outside);
  symlinkSync(outside, join(root, "resource"), "dir");
  await assert.rejects(call({ operation: "create", kind: "resource", title: "Outside" }), /inside the active vault/);
  assert.deepEqual(readdirSync(outside), []);
}));

test("refuses invalid targets, stale revisions, duplicate titles, and external path traversal", vault(async (call, root) => {
  await assert.rejects(call({ operation: "create", kind: "area", title: "No" }), /Unsupported creation kind/);
  await assert.rejects(call({ operation: "create", kind: "resource", title: "Bad\n#+filetags: :area:" }), /Title/);
  const created = await call({ operation: "create", kind: "resource", title: "Keep" });
  await assert.rejects(call({ operation: "create", kind: "resource", title: "Keep" }), /already exists/);
  const id = (created.note as any).id;
  const path = join(root, "resource", `${id}.org`);
  writeFileSync(path, "external edit\n", { flag: "a" });
  await assert.rejects(call({ operation: "update", id, revision: created.revision, action: "append", text: "stale" }), /revision changed/);
}));
