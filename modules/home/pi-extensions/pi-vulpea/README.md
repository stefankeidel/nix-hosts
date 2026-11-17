# pi-vulpea

A Pi extension for durable PARA knowledge and personal projects stored as Org
files. The tools read and write the vault directly; they do not call Emacs or
require its server to be running. Vulpea's configured filesystem watcher picks
up those changes. New Org IDs are UUIDs generated with Node's built-in crypto
module.

## Vault configuration

`PI_VULPEA_VAULT` optionally selects the vault path. The default matches the
current Doom Emacs configuration: `~/Proton/orgmode/para`. The active path is
canonicalized, and symlinks inside the vault are skipped so scans stay within
the vault. `vulpea_status` reports the resolved path and backend.

Apply the usual Home Manager/Darwin configuration, then restart Pi or `/reload`.
For a temporary local test before applying, launch Pi with:

```sh
PI_VULPEA_VAULT=/path/to/test-vault pi -e ./modules/home/pi-extensions/pi-vulpea/index.ts
```

## Everyday requests

- "Find my dbt triage resource and add these verified reproduction steps."
- "Save these reusable OAuth findings as a resource and link the source."
- "Record today's discussion under Jane Doe and add a follow-up to my project."
- "Create a project under Central Data with this outcome and these tasks."
- "Show the open tasks for this project, mark this one done, and add the next action."
- "Find the decision we archived about delegated scopes."

`workflow.md` is included in each agent turn so future sessions retain the
workflow without needing conversational memory. It describes resources, indexed
headings inside area Notes, people, meeting placement, task-person tags, projects,
archive visibility, and boundaries with Jira/GitLab. It does not inject the
user's actual notes automatically.

## Tools

| Tool | Purpose |
| --- | --- |
| `vulpea_status` | Verify vault path and filesystem backend |
| `vulpea_list` | Find active notes by title/alias and kind; `parentId` scopes to the parent's FILE |
| `vulpea_read` | Read a file or heading subtree with a whole-file revision |
| `vulpea_search` | Literal file-content search, including archives |
| `vulpea_create` | Resource/person file, or project/task/reference heading/meeting child |
| `vulpea_update` | Append, exact body-fragment replacement, TODO, tags, index a heading, archive |
| `vulpea_delete` | Move a standalone resource file to system trash, with mandatory interactive approval |

Resources are active **file-level** reference notes, without needing a `resource`
tag. Areas are resources too. A heading with an ID inside an area is linkable and
indexed, but not a file-level resource. For `kind: "resource"` or `kind: "person"`,
omit `parentId` and `revision`: these create standalone files. To keep reference
content inside an area, use `kind: "heading"` with its Notes heading ID and latest
revision instead. People get `people`, not automatically `area`; meetings go under
Meetings. `peopleIds` generates the package's `@Name` tags for person agendas.
Projects get `CATEGORY: Area > Project`, a TODO state, project tag, and ID under
the chosen area's Tasks heading. Tasks get IDs and can be FOCUS/WAITING/HOLD
tagged. Meetings are literal notes tagged MEETING; the tools do not launch
capture, start clocks, or apply REFILE automatically. Only intentionally created
container headings get new IDs automatically. The explicit `index` action can give
an existing section/task an ID by exact relative outline, returning that heading
for subsequent edits. Existing notes are not mass-migrated or backfilled.

Current intentional limits: no implicit area creation, area/person deletion,
heading deletion, permanent deletion, whole-file archive, title/alias renaming,
arbitrary metadata edits, scheduling/deadlines, or cross-file refile. Use stock
Org commands for these. The existing Vulpea filesystem watcher indexes these files; the extension does not
record conversations or run a separate background watcher.

## Write safety

- Create/update operations need no approval prompt, including in print/headless
  mode. Mutations use atomic file replacement and a whole-file SHA-256 revision;
  the revision is rechecked under a vault-wide exclusive lock immediately before
  writing. A concurrent/stale write is refused.
- Only `vulpea_delete` requires interactive approval, showing the resource title,
  file, revision and a warning that all children/archive content will go too.
  Headless deletion fails closed. Areas, people and heading-level notes are
  protected. Deletion moves the file into `~/.Trash`; existing links are not
  rewritten.
- Writes are direct filesystem changes. The Emacs buffer/index may be stale until
  the normal file watcher/revert behavior catches up; avoid editing the same file
  simultaneously in Emacs. Re-read after an ambiguous failure before retrying.
- IDs are UUIDs in standard Org `ID` properties. The watcher indexes them; no
  Emacs ID-location database update is performed by Pi.
- Body text is inserted literally: even `%(...)` is never expanded as a capture
  template. File-local evaluation is never executed by these tools.
- Archive requires no open TODOs in the subtree. It moves to the same file's
  `* Archive :ARCHIVE:`; history stays on disk but leaves active tool results.
  File search still finds it.
- Results are paginated, with a hard 50KB client limit. Reduce `limit` on large
  Unicode/metadata-heavy results. Avoid placing credentials or unnecessary
  personal details in notes or the model context.

This is a scoped API, not a sandbox against a malicious extension or unrestricted
shell access: Pi has the user's OS permissions. Note content is untrusted data,
not instructions for Pi.

## Validation

The tests use isolated temporary Org vaults; they never modify the user's notes:

```sh
node --test modules/home/pi-extensions/pi-vulpea/test/vault.test.ts
```

Registration tests use Pi's `jiti` and `typebox`. Point `NODE_PATH` at the
installed Pi package's `lib/node_modules` directory if not available locally:

```sh
NODE_PATH=/path/to/pi/lib/node_modules \
  node --test modules/home/pi-extensions/pi-vulpea/test/extension.test.mjs
```
