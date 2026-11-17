import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { type ExtensionAPI, withFileMutationQueue } from "@earendil-works/pi-coding-agent";
import { Type, type Static, type TSchema } from "typebox";
import { request, type Request } from "./client.ts";

const workflow = readFileSync(new URL("./workflow.md", import.meta.url), "utf8");
const namespace = { name: "vulpea", description: "Durable Org PARA resources, people, areas, projects and tasks through the running Emacs.", instructions: workflow };
const outputSchema = Type.Record(Type.String(), Type.Unknown());
const id = Type.String({ minLength: 1, maxLength: 128, description: "Exact active note ID returned by list/read." });
const revision = Type.String({ pattern: "^[a-f0-9]{64}$", description: "Latest whole-file revision from vulpea_read. Re-read after any write in this file." });
const tags = Type.Array(Type.String({ minLength: 1, maxLength: 100 }), { maxItems: 20 });
const peopleIds = Type.Optional(Type.Array(id, { maxItems: 20, description: "Existing people note IDs; adds stock @NameWithoutSpaces task tags." }));
const page = {
  offset: Type.Optional(Type.Integer({ minimum: 0, maximum: 1_000_000 })),
  limit: Type.Optional(Type.Integer({ minimum: 1, maximum: 100 })),
};
const enumOf = <T extends string>(values: T[]) => Type.Unsafe<T>({ type: "string", enum: values });

export default function vulpeaExtension(pi: ExtensionAPI) {
  const call = (input: Request, signal?: AbortSignal) => request(pi.exec.bind(pi), input, signal);

  function add<T extends TSchema>(name: string, description: string, parameters: T, operation: string, write = false) {
    pi.registerTool({
      name, label: name.replaceAll("_", " "), description, namespace,
      parameters, outputSchema,
      executionMode: "sequential",
      annotations: { readOnlyHint: !write, destructiveHint: write, idempotentHint: !write, openWorldHint: false },
      async execute(_toolCallId, params: Static<T>, signal, _onUpdate, ctx) {
        const input = { ...params, operation } as Request;
        if (operation === "delete" && !ctx.hasUI) {
          throw new Error("Resource deletion requires interactive confirmation; headless deletion is disabled.");
        }
        let data: Record<string, unknown>;
        if (write && (input.id || input.parentId)) {
          const target = await call({ operation: "read", id: input.id || input.parentId, limit: 1 }, signal);
          const status = await call({ operation: "status" }, signal);
          const note = target.note as { file: string };
          data = await withFileMutationQueue(resolve(status.vault as string, note.file), async () => {
            if (operation === "delete") {
              if (target.revision !== input.revision) throw new Error("File revision changed; read the resource again before deleting.");
              const approved = await ctx.ui.confirm("Move resource to trash?", JSON.stringify({
                note: target.note, revision: input.revision,
                warning: "Deletes the entire resource file, including all children and archived content. Existing links may become dangling. Areas and people notes are protected.",
              }, null, 2));
              if (!approved) throw new Error("Resource deletion cancelled; no changes made.");
            }
            signal?.throwIfAborted();
            return call(input, signal);
          });
        } else {
          data = await call(input, signal);
        }
        return { content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }], structuredContent: data, details: undefined };
      },
    });
  }

  add("vulpea_status", "Inspect the active Emacs PARA vault and configuration. Does not start Emacs or edit notes.", Type.Object({}), "status");
  add("vulpea_list", "List/search active indexed notes by title or alias. Resource means file-level reference, not a resource tag. parentId restricts results to the parent's FILE, not just its subtree. Archives excluded. Bounded pages (default 25, max 100).", Type.Object({
    kind: Type.Optional(enumOf(["all", "area", "project", "resource", "person", "task"])),
    query: Type.Optional(Type.String({ maxLength: 300 })),
    parentId: Type.Optional(id), ...page,
  }), "list");
  add("vulpea_read", "Read an indexed note's Org subtree or whole file. Includes unsaved flag and whole-file revision for subsequent writes. Paginate by character offset; default 12000, max 20000 chars.", Type.Object({
    id, offset: Type.Optional(Type.Integer({ minimum: 0, maximum: 10_000_000 })),
    limit: Type.Optional(Type.Integer({ minimum: 1, maximum: 20000 })),
  }), "read");
  add("vulpea_search", "Search literal text throughout the vault, including archives, with bounded line snippets. Does not evaluate Org content. Paginate results; default 25, max 100.", Type.Object({
    query: Type.String({ minLength: 1, maxLength: 300 }), ...page,
  }), "search");
  add("vulpea_create", "Create a standalone resource/person FILE (omit parentId and revision), or a project/task/heading/meeting under an existing parent. To store reference content inside an area, use kind=heading with its Notes heading ID, NOT kind=resource. No new areas. Projects use area Tasks; meetings use person Meetings; file-level task parents use Tasks. Supply parentId and revision for children. Literal Org body, no template evaluation. No approval prompt; refuses unsaved targets.", Type.Object({
    kind: enumOf(["resource", "person", "project", "task", "heading", "meeting"]),
    title: Type.String({ minLength: 1, maxLength: 300 }),
    body: Type.Optional(Type.String({ maxLength: 50000 })),
    parentId: Type.Optional(Type.String({ minLength: 1, maxLength: 128, description: "Required for project/task/heading/meeting; omit for standalone resource/person files. For area reference content use kind=heading and the Notes heading ID." })),
    revision: Type.Optional(revision),
    tags: Type.Optional(tags), peopleIds,
  }), "create", true);
  add("vulpea_update", "Update a read note using its exact ID and latest revision. append adds literal Org to its own body; replace edits one unique own-body fragment, not children or metadata; todo uses TODO/DONE/CANCELLED; tags uses addTags/removeTags/peopleIds; index gives an existing heading an ID using an exact relative outline path and returns that heading. archive requires all subtree tasks finished and moves it to same-file Archive tagged ARCHIVE. No deletes, arbitrary Elisp, or whole-file replacement. No approval prompt; revision and buffer-safety checks still apply.", Type.Object({
    id, revision,
    action: enumOf(["append", "replace", "todo", "tags", "index", "archive"]),
    outline: Type.Optional(Type.Array(Type.String({ minLength: 1, maxLength: 300 }), { minItems: 1, maxItems: 20, description: "For index: exact heading titles relative to the read note, e.g. [Notes, dbt triage]. Must be unique." })),
    text: Type.Optional(Type.String({ maxLength: 50000 })),
    oldText: Type.Optional(Type.String({ minLength: 1, maxLength: 50000 })),
    addTags: Type.Optional(tags), removeTags: Type.Optional(tags), peopleIds,
  }), "update", true);

  add("vulpea_delete", "Move a standalone resource FILE to trash, including all children/archive content. Requires an exact file-level ID, fresh revision, and interactive approval showing the target. Refuses areas, people, headings, unsaved/read-only/externally changed files. Links are not rewritten. No headless deletion or permanent-delete fallback.", Type.Object({
    id, revision,
  }), "delete", true);

  pi.on("before_agent_start", (event) => ({
    systemPrompt: `${event.systemPrompt}\n\n<pi-vulpea>\n${workflow}\n</pi-vulpea>`,
  }));
}
