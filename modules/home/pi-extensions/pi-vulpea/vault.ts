import { randomUUID, createHash } from "node:crypto";
import { existsSync, mkdirSync, openSync, closeSync, readFileSync, readdirSync, renameSync, unlinkSync, writeFileSync, statSync, realpathSync, copyFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, extname, isAbsolute, join, relative, resolve, sep } from "node:path";

export type Request = { operation: string; [key: string]: unknown };
type Node = { id: string; title: string; file: string; level: number; start: number; end: number; bodyStart: number; bodyEnd: number; tags: string[]; todo?: string; aliases: string[]; archived: boolean };
type Document = { path: string; text: string; lines: string[]; nodes: Node[] };

const areaTag = "area";
const projectTag = "project";
const peopleTag = "people";
const agendaTag = "AGENDA";
const archiveTag = "ARCHIVE";
const todoStates = ["TODO", "DONE", "CANCELLED"];

function root(): string {
  const configured = process.env.PI_VULPEA_VAULT || "~/Proton/orgmode/para";
  const expanded = resolve(configured.startsWith("~/") ? join(homedir(), configured.slice(2)) : configured);
  if (!existsSync(expanded) || !statSync(expanded).isDirectory()) throw new Error(`Org vault does not exist: ${expanded} (set PI_VULPEA_VAULT)`);
  return realpathSync(expanded);
}
function inside(base: string, path: string): boolean {
  const rel = relative(base, path);
  return rel === "" || (rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel));
}
function filesUnder(dir: string, base: string): string[] {
  let found: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isSymbolicLink()) continue;
    if (entry.isDirectory()) found = found.concat(filesUnder(path, base));
    else if (entry.isFile() && extname(entry.name).toLowerCase() === ".org") {
      const real = realpathSync(path);
      if (inside(base, real)) found.push(real);
    }
  }
  return found;
}
function fileHash(text: string): string { return createHash("sha256").update(text, "utf8").digest("hex"); }
function propsEnd(lines: string[], start: number, limit: number): number {
  if (lines[start]?.trim() !== ":PROPERTIES:") return start;
  for (let i = start + 1; i < limit; i++) if (lines[i]?.trim() === ":END:") return i + 1;
  throw new Error("Unterminated Org properties drawer");
}
function props(lines: string[], start: number, limit: number): Map<string, string> {
  const out = new Map<string, string>();
  if (lines[start]?.trim() !== ":PROPERTIES:") return out;
  for (let i = start + 1; i < limit && lines[i]?.trim() !== ":END:"; i++) {
    const m = lines[i]?.match(/^\s*:([^:]+):\s*(.*?)\s*$/);
    if (m) out.set(m[1].toUpperCase(), m[2]);
  }
  return out;
}
function parseTags(raw: string | undefined): string[] {
  if (!raw) return [];
  const m = raw.match(/(?:^|\s):([A-Za-z0-9_@#%:]+):\s*$/);
  return m ? m[1].split(":").filter(Boolean) : [];
}
function headingBits(line: string): { level: number; title: string; todo?: string; tags: string[] } | undefined {
  const m = line.match(/^(\*+)\s+(.*?)\s*$/);
  if (!m) return;
  let rest = m[2];
  let tags: string[] = [];
  const tagMatch = rest.match(/\s+:([A-Za-z0-9_@#%:]+):\s*$/);
  if (tagMatch) { tags = tagMatch[1].split(":").filter(Boolean); rest = rest.slice(0, tagMatch.index).trimEnd(); }
  let todo: string | undefined;
  const todoMatch = rest.match(/^(TODO|DONE|CANCELLED)\s+/);
  if (todoMatch) { todo = todoMatch[1]; rest = rest.slice(todoMatch[0].length); }
  return { level: m[1].length, title: rest, todo, tags };
}
function textOffsets(lines: string[]): number[] {
  const offsets: number[] = []; let n = 0;
  for (const line of lines) { offsets.push(n); n += line.length + 1; }
  return offsets;
}
function parseDocument(path: string, text: string): Document {
  const lines = text.split("\n");
  const offsets = textOffsets(lines);
  const relFile = relative(root(), path);
  const doc: Document = { path, text, lines, nodes: [] };
  const propertyLimit = Math.min(lines.length, 100);
  const fileProps = props(lines, 0, propertyLimit);
  const fileTagsLine = lines.find((line, i) => i < propertyLimit && /^#\+filetags\s*:/i.test(line));
  const fileTags = parseTags(fileTagsLine?.replace(/^#\+filetags\s*:/i, ""));
  const fileTitleLine = lines.find((line, i) => i < propertyLimit && /^#\+title\s*:/i.test(line));
  const fileTitle = fileTitleLine?.replace(/^#\+title\s*:/i, "").trim() || basename(path, ".org");
  const fileNode: Node = {
    id: fileProps.get("ID") || "", title: fileTitle, file: relFile, level: 0, start: 0, end: text.length,
    bodyStart: 0, bodyEnd: text.length, tags: fileTags, aliases: [], archived: false,
  };
  const aliases = fileProps.get("ROAM_ALIASES") || fileProps.get("ALIASES") || "";
  fileNode.aliases = aliases.split(/[;,]/).map(s => s.trim()).filter(Boolean);
  const fileDrawerEnd = propsEnd(lines, 0, propertyLimit);
  let bodyLine = fileDrawerEnd;
  while (bodyLine < lines.length && (/^\s*$/.test(lines[bodyLine]) || /^#\+/i.test(lines[bodyLine]))) bodyLine++;
  fileNode.bodyStart = offsets[bodyLine] ?? text.length;
  const headingStarts: number[] = [];
  for (let i = 0; i < lines.length; i++) if (headingBits(lines[i])) headingStarts.push(i);
  fileNode.bodyEnd = headingStarts.length ? offsets[headingStarts[0]] : text.length;
  doc.nodes.push(fileNode);
  const stack: Node[] = [];
  for (let j = 0; j < headingStarts.length; j++) {
    const lineNo = headingStarts[j]; const bits = headingBits(lines[lineNo])!;
    const nextLine = headingStarts[j + 1] ?? lines.length;
    const endLine = (() => { for (let k = j + 1; k < headingStarts.length; k++) if (headingBits(lines[headingStarts[k]])!.level <= bits.level) return headingStarts[k]; return lines.length; })();
    const drawerEnd = propsEnd(lines, lineNo + 1, endLine);
    const p = props(lines, lineNo + 1, endLine);
    while (stack.length && stack.at(-1)!.level >= bits.level) stack.pop();
    const parent = stack.at(-1);
    const ancestorArchived = Boolean(parent?.archived);
    const ownArchived = bits.tags.includes(archiveTag) || p.has("ARCHIVE_TIME");
    const aliasText = p.get("ROAM_ALIASES") || p.get("ALIASES") || "";
    const node: Node = {
      id: p.get("ID") || "", title: bits.title, file: relFile, level: bits.level,
      start: offsets[lineNo], end: offsets[endLine] ?? text.length,
      bodyStart: offsets[drawerEnd] ?? text.length, bodyEnd: offsets[nextLine] ?? text.length,
      tags: bits.tags, todo: bits.todo, aliases: aliasText.split(/[;,]/).map(s => s.trim()).filter(Boolean),
      archived: ancestorArchived || ownArchived,
    };
    doc.nodes.push(node); stack.push(node);
  }
  return doc;
}
function documents(base = root()): Document[] {
  return filesUnder(base, base).sort().map(path => parseDocument(path, readFileSync(path, "utf8")));
}
function indexed(base = root()): { docs: Document[]; nodes: Node[] } {
  const docs = documents(base);
  const nodes = docs.flatMap(d => d.nodes).filter(n => n.id);
  const seen = new Set<string>();
  for (const n of nodes) { if (seen.has(n.id)) throw new Error(`Duplicate Org ID in vault: ${n.id}`); seen.add(n.id); }
  return { docs, nodes };
}
function findNode(id: unknown): { doc: Document; node: Node } {
  if (typeof id !== "string" || !id) throw new Error("An exact note ID is required");
  const { docs } = indexed();
  for (const doc of docs) {
    const node = doc.nodes.find(n => n.id === id && !n.archived);
    if (node) return { doc, node };
  }
  throw new Error(`No active note with ID ${id}`);
}
function buckets(n: Node): string[] {
  const result: string[] = [];
  if (n.level === 0 && n.tags.includes(areaTag)) result.push("area");
  if (n.level === 0 && n.tags.includes(peopleTag)) result.push("person");
  if (n.level === 0 && !n.tags.includes(areaTag) && !n.tags.includes(peopleTag)) result.push("resource");
  if (n.tags.includes(projectTag)) result.push("project");
  return result;
}
function summary(n: Node): Record<string, unknown> {
  return { id: n.id, title: n.title, file: n.file, level: n.level, tags: n.tags, todo: n.todo ?? null, aliases: n.aliases, buckets: buckets(n) };
}
function safeNumber(x: unknown, fallback: number, max: number): number {
  const n = x === undefined ? fallback : x;
  if (typeof n !== "number" || !Number.isInteger(n) || n < 0 || n > max) throw new Error("Invalid pagination value");
  return n;
}
function validateTitle(title: unknown): asserts title is string {
  if (typeof title !== "string" || title.length < 1 || title.length > 300 || /[\n\r\t]/.test(title) || /^[ *#:]/.test(title) || /\s:[^\s]+:$/.test(title)) throw new Error("Title must be a plain, non-empty single line (max 300 characters)");
}
function validateTags(value: unknown): string[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.some(t => typeof t !== "string" || !/^[A-Za-z0-9_@#%]+$/.test(t))) throw new Error("Invalid Org tags");
  const tags = [...new Set(value as string[])];
  if (tags.includes(agendaTag) || tags.includes(archiveTag)) throw new Error("Agenda and archive tags are managed by the workflow");
  return tags;
}
function validateBody(text: unknown, level: number): asserts text is string {
  if (typeof text !== "string" || text.length > 50000) throw new Error("Body must be a string of at most 50000 characters");
  for (const m of text.matchAll(/^(\*+) /gm)) if (m[1].length <= level) throw new Error(`Body headings must be deeper than their target (level ${level})`);
  if (/^#\+(title|filetags|todo|seq_todo|property):|Local Variables:/im.test(text)) throw new Error("Use structured fields, not document settings or local variables, in body text");
}
function insertProperty(text: string, id: string, category?: string): string {
  const fields = [`:ID: ${id}`, ...(category ? [`:CATEGORY: ${category}`] : [])];
  return `:PROPERTIES:\n${fields.join("\n")}\n:END:\n${text}`;
}
function formattedTags(tags: string[]): string { return tags.length ? ` :${tags.join(":")}:` : ""; }
function fileText(title: string, id: string, tags: string[], body: string): string {
  const filetags = tags.length ? `#+filetags: :${tags.join(":")}:\n` : "";
  return `:PROPERTIES:\n:ID: ${id}\n:END:\n#+title: ${title}\n${filetags}\n${body}${body.endsWith("\n") || !body ? "" : "\n"}`;
}
function nodeText(title: string, level: number, id: string, tags: string[], body: string, todo?: string, category?: string): string {
  const line = `${"*".repeat(level)} ${todo ? `${todo} ` : ""}${title}${formattedTags(tags)}`;
  const props = insertProperty("", id, category).trimEnd();
  return `${line}\n${props}\n\n${body}${body.endsWith("\n") || !body ? "" : "\n"}`;
}
function ensureId(text: string, node: Node): string {
  if (node.id) return text;
  const id = randomUUID();
  if (node.level === 0) return insertProperty(text, id);
  const lineStart = node.start;
  const afterLine = text.indexOf("\n", lineStart) + 1;
  if (text.startsWith(":PROPERTIES:", afterLine)) return text;
  return text.slice(0, afterLine) + `:PROPERTIES:\n:ID: ${id}\n:END:\n` + text.slice(afterLine);
}
function lock<T>(base: string, f: () => T): T {
  const lockPath = join(base, ".pi-vulpea-write.lock");
  let fd: number;
  try { fd = openSync(lockPath, "wx", 0o600); }
  catch { throw new Error("Another filesystem write is active, or a stale .pi-vulpea-write.lock exists; inspect before retrying"); }
  try { return f(); } finally { closeSync(fd); try { unlinkSync(lockPath); } catch { /* preserve original result */ } }
}
function writeAtomic(path: string, text: string): void {
  const temp = join(dirname(path), `.${basename(path)}.${randomUUID()}.tmp`);
  const mode = existsSync(path) ? statSync(path).mode & 0o777 : 0o600;
  try { writeFileSync(temp, text, { encoding: "utf8", mode }); renameSync(temp, path); }
  catch (e) { try { unlinkSync(temp); } catch { /* no temp */ } throw e; }
}
function checkedWrite(doc: Document, revision: unknown, mutate: (text: string) => { text: string; resultId?: string; data?: Record<string, unknown> }): Record<string, unknown> {
  if (typeof revision !== "string" || revision !== fileHash(doc.text)) throw new Error("File revision changed; read the target again before writing");
  const base = root();
  return lock(base, () => {
    const currentPath = realpathSync(doc.path);
    if (!inside(base, currentPath) || currentPath !== doc.path) throw new Error("Target path changed or escaped the active vault");
    const current = readFileSync(currentPath, "utf8");
    if (fileHash(current) !== revision) throw new Error("File revision changed; read the target again before writing");
    const changed = mutate(current);
    writeAtomic(currentPath, changed.text);
    return changed.data ?? readOperation({ id: changed.resultId || doc.nodes[0]?.id, limit: 4000 });
  });
}
function parseWithPath(doc: Document, text: string): Document { return parseDocument(doc.path, text); }
function charSlice(s: string, start: number, end: number): string { return Array.from(s).slice(start, end).join(""); }
function chars(s: string): number { return Array.from(s).length; }
function readOperation(input: Request): Record<string, unknown> {
  const { doc, node } = findNode(input.id);
  const offset = safeNumber(input.offset, 0, 10_000_000); const limit = safeNumber(input.limit, 12000, 20000);
  const content = node.level === 0 ? doc.text : doc.text.slice(node.start, node.end);
  const total = chars(content); const part = charSlice(content, Math.min(offset, total), Math.min(offset + limit, total));
  return { note: summary(node), revision: fileHash(doc.text), unsaved: false, content: part, totalChars: total, nextOffset: offset + chars(part) < total ? offset + chars(part) : null };
}
function listOperation(input: Request): Record<string, unknown> {
  const kind = input.kind ?? "all"; const query = typeof input.query === "string" ? input.query.toLocaleLowerCase() : "";
  if (typeof kind !== "string" || !["all", "area", "project", "resource", "person", "task"].includes(kind)) throw new Error("Unknown note kind");
  const docs = documents(); const parent = input.parentId ? findNode(input.parentId) : undefined;
  const matched = docs.flatMap(d => d.nodes).filter(n => !n.archived && n.id)
    .filter(n => kind === "all" || (kind === "area" && buckets(n).includes("area")) || (kind === "project" && n.tags.includes(projectTag)) || (kind === "resource" && n.level === 0 && !n.tags.includes(areaTag) && !n.tags.includes(peopleTag)) || (kind === "person" && n.level === 0 && n.tags.includes(peopleTag)) || (kind === "task" && Boolean(n.todo)))
    .filter(n => !parent || n.file === parent.node.file)
    .filter(n => `${n.title} ${n.aliases.join(" ")}`.toLocaleLowerCase().includes(query))
    .sort((a,b) => `${a.title}${a.id}`.localeCompare(`${b.title}${b.id}`));
  const offset = safeNumber(input.offset, 0, 1_000_000); const limit = Math.max(1, safeNumber(input.limit, 25, 100));
  const items = matched.slice(offset, offset + limit).map(summary);
  return { items, total: matched.length, nextOffset: offset + items.length < matched.length ? offset + items.length : null };
}
function searchOperation(input: Request): Record<string, unknown> {
  if (typeof input.query !== "string" || !input.query.length || input.query.length > 300) throw new Error("A literal query of 1-300 characters is required");
  const query = input.query.toLocaleLowerCase(); const offset = safeNumber(input.offset, 0, 1_000_000); const limit = Math.max(1, safeNumber(input.limit, 25, 100));
  const hits: Record<string, unknown>[] = []; let seen = 0; let more = false;
  outer: for (const path of filesUnder(root(), root()).sort()) {
    const text = readFileSync(path, "utf8"); const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) if (lines[i].toLocaleLowerCase().includes(query)) {
      if (seen++ < offset) continue;
      if (hits.length >= limit) { more = true; break outer; }
      const at = lines[i].toLocaleLowerCase().indexOf(query);
      const snippet = lines[i].slice(Math.max(0, at - 150), Math.min(lines[i].length, at + query.length + 150));
      hits.push({ file: relative(root(), path), line: i + 1, snippet: snippet.slice(0, 300), unsaved: false });
    }
  }
  return { items: hits, nextOffset: more ? offset + hits.length : null };
}
function createOperation(input: Request): Record<string, unknown> {
  const kind = input.kind; const title = input.title; validateTitle(title);
  const body = input.body ?? ""; const tags = validateTags(input.tags); const peopleIds = input.peopleIds ?? [];
  if (typeof body !== "string" || !Array.isArray(peopleIds)) throw new Error("Invalid body or peopleIds");
  const { docs, nodes } = indexed();
  const extraPeople = (peopleIds as unknown[]).map(id => {
    const p = nodes.find(n => n.id === id && n.level === 0 && n.tags.includes(peopleTag));
    if (!p) throw new Error(`Person ID does not identify a people note: ${String(id)}`);
    return p.title.replace(/[^\p{L}\p{N}]/gu, "");
  });
  const allTags = [...new Set([...tags, ...extraPeople.map(n => `@${n}`)])];
  if (allTags.some(t => [areaTag, projectTag, peopleTag].includes(t))) throw new Error("Use the creation kind, not manual PARA classification tags");
  const parentId = input.parentId;
  if (kind === "resource" || kind === "person") {
    if (parentId || input.revision) throw new Error("Resources and people are standalone files; omit parentId and revision. For area reference content use kind=heading under Notes.");
    validateBody(body, 0);
    if (kind === "person") allTags.push(peopleTag);
    return lock(root(), () => {
      if (documents().some(d => d.nodes[0]?.title === title)) throw new Error("A note with this exact title already exists; inspect it before creating another");
      const id = randomUUID(); const base = root(); const targetDir = join(base, kind);
      mkdirSync(targetDir, { recursive: true });
      const realDir = realpathSync(targetDir);
      if (!inside(base, realDir) || realDir !== targetDir) throw new Error("Resource/person directory must be a real directory inside the active vault");
      const path = join(realDir, `${id}.org`);
      const file = fileText(title, id, [...new Set(allTags)], body);
      if (existsSync(path)) throw new Error("Refusing to overwrite an existing note");
      if (kind === "person") {
        const meetingsId = randomUUID(); const tasksId = randomUUID();
        writeAtomic(path, `${file.trimEnd()}\n\n${nodeText("Meetings", 1, meetingsId, [], "")}\n${nodeText("Tasks", 1, tasksId, [], "")}`);
      } else writeAtomic(path, file);
      const doc = parseDocument(path, readFileSync(path, "utf8")); const node = doc.nodes[0];
      return { created: true, note: summary(node), revision: fileHash(doc.text), unsaved: false, content: charSlice(doc.text, 0, 4000), totalChars: chars(doc.text), nextOffset: chars(doc.text) > 4000 ? 4000 : null };
    });
  }
  if (!["project", "task", "heading", "meeting"].includes(String(kind))) throw new Error("Unsupported creation kind (area creation is intentionally not exposed)");
  if (typeof parentId !== "string" || !parentId || typeof input.revision !== "string") throw new Error("Existing parentId and its revision are required");
  const { doc, node: parent } = findNode(parentId);
  if (fileHash(doc.text) !== input.revision) throw new Error("File revision changed; read the target again before writing");
  if (kind === "project" && !buckets(parent).includes("area")) throw new Error("Projects must be created under an existing area");
  if (kind === "meeting" && !(parent.level === 0 && parent.tags.includes(peopleTag))) throw new Error("Meetings must be created under a file-level people note");
  if (allTags.includes(projectTag)) throw new Error("Use kind project rather than setting its tag manually");
  if (doc.nodes.some(n => n.title === title && !n.archived)) throw new Error("A note with this exact title already exists in the target file");
  return checkedWrite(doc, input.revision, current => {
    let text = current; let reParsed = parseWithPath(doc, text); let currentParent = reParsed.nodes.find(n => n.id === parentId)!;
    let targetLevel = currentParent.level + 1; let containerName: string | undefined;
    if (kind === "project" || kind === "meeting" || (kind === "task" && currentParent.level === 0)) containerName = kind === "meeting" ? "Meetings" : "Tasks";
    if (containerName) {
      let container = reParsed.nodes.find(n => n.level === 1 && n.title === containerName && !n.archived);
      if (!container) {
        const cid = randomUUID();
        const addition = `${text.endsWith("\n") ? "" : "\n"}\n${nodeText(containerName, 1, cid, [], "")}`;
        text += addition; reParsed = parseWithPath(doc, text); container = reParsed.nodes.find(n => n.id === cid)!;
      }
      currentParent = container; targetLevel = container.level + 1;
    }
    validateBody(body, targetLevel);
    const id = randomUUID(); const nodeTags = [...allTags, ...(kind === "project" ? [projectTag] : []), ...(kind === "meeting" ? ["MEETING"] : [])];
    const todo = kind === "project" || kind === "task" ? "TODO" : undefined;
    const category = kind === "project" ? `${parent.title} > ${title}` : undefined;
    const insertion = nodeText(title, targetLevel, id, nodeTags, body, todo, category);
    const at = currentParent.level === 0 ? text.length : currentParent.end;
    const prefix = at > 0 && text[at - 1] !== "\n" ? "\n" : "";
    text = text.slice(0, at) + prefix + (prefix ? "\n" : "\n") + insertion + "\n" + text.slice(at);
    return { text, resultId: id };
  });
}
function updateOperation(input: Request): Record<string, unknown> {
  const { doc, node } = findNode(input.id); const action = input.action;
  if (typeof input.revision !== "string" || input.revision !== fileHash(doc.text)) throw new Error("File revision changed; read the target again before writing");
  return checkedWrite(doc, input.revision, current => {
    let text = current; let resultId = node.id; const parsed = parseWithPath(doc, text); const n = parsed.nodes.find(x => x.id === node.id)!;
    const bodyText = text.slice(n.bodyStart, n.bodyEnd);
    if (action === "append") {
      const addition = input.text ?? ""; validateBody(addition, n.level);
      const boundary = n.bodyEnd;
      const updated = `${text.slice(0, boundary)}${boundary > n.bodyStart && !text.slice(0, boundary).endsWith("\n\n") ? "\n" : ""}\n${addition}${addition && !String(addition).endsWith("\n") ? "\n" : ""}${text.slice(boundary)}`;
      text = updated;
    } else if (action === "replace") {
      const old = input.oldText; const replacement = input.text ?? ""; validateBody(replacement, n.level);
      if (typeof old !== "string" || !old || /^\*+ |^#\+|^:ID:/m.test(old)) throw new Error("oldText must be a non-empty body fragment, not metadata or headings");
      const i = bodyText.indexOf(old); if (i < 0) throw new Error("oldText not found in the node's own body");
      if (bodyText.indexOf(old, i + old.length) >= 0) throw new Error("oldText is not unique");
      const start = n.bodyStart + i; text = text.slice(0, start) + replacement + text.slice(start + old.length);
    } else if (action === "todo") {
      if (!n.level) throw new Error("TODO states belong to headings");
      if (typeof input.text !== "string" || !todoStates.includes(input.text)) throw new Error("Unsupported TODO state");
      const lineEnd = text.indexOf("\n", n.start); const line = text.slice(n.start, lineEnd < 0 ? undefined : lineEnd);
      const bits = headingBits(line)!;
      let rest = line.slice(bits.level + 1).replace(/^(TODO|DONE|CANCELLED)\s+/, "");
      text = text.slice(0, n.start) + `${"*".repeat(n.level)} ${input.text} ${rest}` + text.slice(lineEnd < 0 ? text.length : lineEnd);
    } else if (action === "tags") {
      const add = validateTags(input.addTags); const remove = validateTags(input.removeTags);
      if ([areaTag, projectTag, peopleTag].some(t => add.includes(t) || remove.includes(t))) throw new Error("Area, project, and people classification cannot be changed by a tag edit");
      const peopleIds = input.peopleIds ?? [];
      if (!Array.isArray(peopleIds)) throw new Error("Invalid peopleIds");
      const { nodes } = indexed();
      const peopleTags = (peopleIds as unknown[]).map(id => {
        const p = nodes.find(x => x.id === id && x.level === 0 && x.tags.includes(peopleTag));
        if (!p) throw new Error(`Person ID does not identify a people note: ${String(id)}`);
        return `@${p.title.replace(/[^\p{L}\p{N}]/gu, "")}`;
      });
      let updated = [...new Set([...n.tags.filter(t => !remove.includes(t)), ...add, ...peopleTags])];
      if (n.level === 0) {
        const line = /^#\+filetags\s*:.*(?:\n|$)/im.exec(text);
        if (line) text = text.slice(0, line.index) + (updated.length ? `#+filetags: :${updated.join(":")}:\n` : "") + text.slice(line.index + line[0].length);
        else if (updated.length) { const titleMatch = /^#\+title\s*:.*(?:\n|$)/im.exec(text); const at = titleMatch ? titleMatch.index + titleMatch[0].length : 0; text = text.slice(0, at) + `#+filetags: :${updated.join(":")}:\n` + text.slice(at); }
      } else {
        const lineEnd = text.indexOf("\n", n.start); const line = text.slice(n.start, lineEnd < 0 ? undefined : lineEnd); const bits = headingBits(line)!;
        const base = line.replace(/\s+:[A-Za-z0-9_@#%:]+:\s*$/, "");
        const newLine = base + formattedTags(updated);
        text = text.slice(0, n.start) + newLine + text.slice(lineEnd < 0 ? text.length : lineEnd);
      }
    } else if (action === "index") {
      if (!Array.isArray(input.outline) || !input.outline.length || input.outline.some(x => typeof x !== "string" || !x)) throw new Error("index requires a non-empty relative heading outline");
      const start = n.level === 0 ? 0 : n.start; const end = n.level === 0 ? text.length : n.end;
      const wanted = input.outline as string[];
      const matches = parsed.nodes.filter(x => x.level > 0 && x.start >= start && x.start < end && !x.archived && (() => {
        const chain = parsed.nodes.filter(a => a.level > 0 && a.start <= x.start && a.end >= x.end && (n.level === 0 || a.start > n.start)).sort((a,b) => a.level - b.level).map(a => a.title);
        return chain.length === wanted.length && chain.every((v,i) => v === wanted[i]);
      })());
      if (matches.length !== 1) throw new Error("Heading outline must identify exactly one existing heading");
      const target = matches[0]; if (target.id) resultId = target.id;
      else { const after = text.indexOf("\n", target.start) + 1; text = text.slice(0, after) + `:PROPERTIES:\n:ID: ${randomUUID()}\n:END:\n` + text.slice(after); const reparsed = parseWithPath(doc, text); resultId = reparsed.nodes.find(x => x.start === target.start)?.id || ""; }
    } else if (action === "archive") {
      if (!n.level) throw new Error("Whole-file archiving is intentionally not exposed");
      const open = parsed.nodes.filter(x => x.start >= n.start && x.start < n.end && x.todo === "TODO");
      if (open.length) throw new Error("Complete or cancel open work before archiving");
      let archive = parsed.nodes.find(x => x.level === 1 && x.title === "Archive" && x.tags.includes(archiveTag));
      if (!archive) { const id = randomUUID(); text += `${text.endsWith("\n") ? "" : "\n"}\n${nodeText("Archive", 1, id, [archiveTag], "")}`; }
      const refreshed = parseWithPath(doc, text); archive = refreshed.nodes.find(x => x.level === 1 && x.title === "Archive" && x.tags.includes(archiveTag))!;
      const refreshedNode = refreshed.nodes.find(x => x.id === n.id)!;
      const archivedText = text.slice(refreshedNode.start, refreshedNode.end);
      const insertion = archive.end;
      const sourceStart = refreshedNode.start; const sourceEnd = refreshedNode.end;
      const without = text.slice(0, sourceStart) + text.slice(sourceEnd);
      const adjustedInsertion = insertion > sourceEnd ? insertion - (sourceEnd - sourceStart) : insertion;
      text = without.slice(0, adjustedInsertion) + (without.slice(0, adjustedInsertion).endsWith("\n") ? "\n" : "\n\n") + archivedText + without.slice(adjustedInsertion);
      return { text, data: { archived: true, id: n.id, file: n.file, destination: "* Archive :ARCHIVE:", search: "Archive is retained in the Org file, excluded from active index" } };
    } else throw new Error("Unsupported update action");
    return { text, resultId };
  });
}
function moveToTrash(path: string): string {
  const trash = join(homedir(), ".Trash"); mkdirSync(trash, { recursive: true });
  const base = basename(path); let target = join(trash, base);
  if (existsSync(target)) target = join(trash, `${base}.${new Date().toISOString().replace(/[:.]/g, "-")}.${randomUUID().slice(0,8)}`);
  try { renameSync(path, target); }
  catch (e: any) {
    if (e?.code !== "EXDEV") throw e;
    const tmp = `${target}.${randomUUID()}.tmp`; copyFileSync(path, tmp); renameSync(tmp, target); unlinkSync(path);
  }
  return target;
}
function deleteOperation(input: Request): Record<string, unknown> {
  const { doc, node } = findNode(input.id);
  if (node.level !== 0 || !buckets(node).includes("resource")) throw new Error("Only standalone resource files can be deleted; areas, people and headings are protected");
  if (typeof input.revision !== "string" || input.revision !== fileHash(doc.text)) throw new Error("File revision changed; read the resource again before deleting");
  return lock(root(), () => {
    if (fileHash(readFileSync(doc.path, "utf8")) !== input.revision) throw new Error("File revision changed; read the resource again before deleting");
    moveToTrash(doc.path);
    return { deleted: true, destination: "trash", note: summary(node), warning: "Existing links were not rewritten. Restore from the system trash if needed." };
  });
}
export async function request(input: Request, signal?: AbortSignal): Promise<Record<string, unknown>> {
  signal?.throwIfAborted();
  const base = root();
  let result: Record<string, unknown>;
  switch (input.operation) {
    case "status": result = { vault: base, backend: "filesystem", idFormat: "UUID" }; break;
    case "list": result = listOperation(input); break;
    case "read": result = readOperation(input); break;
    case "search": result = searchOperation(input); break;
    case "create": result = createOperation(input); break;
    case "update": result = updateOperation(input); break;
    case "delete": result = deleteOperation(input); break;
    default: throw new Error("Unknown operation");
  }
  if (Buffer.byteLength(JSON.stringify(result), "utf8") > 50_000) {
    throw new Error("Vulpea response exceeds 50KB; read/list with a smaller limit. If this followed a write, read the target before retrying the write.");
  }
  return result;
}
