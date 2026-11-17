# pi-vulpea

A Pi extension for durable PARA knowledge and personal projects in the running
Emacs. Installed globally by `modules/home/pi.nix` on Pi-enabled hosts.

## Emacs wiring: none

Keep the existing Org/Vulpea/PARA configuration and Emacs server. The extension
loads `bridge.el` on demand through `emacsclient --eval`. Nothing is added to
`config.el`, the Emacs load path, startup hooks, or the note files themselves
until a write. Loading Pi does not connect to Emacs or read the vault.
There is no Emacs subprocess fallback, MCP server, npm runtime dependency, or
agent-facing arbitrary-Elisp tool.

The existing `org-directory` must be a synced Vulpea vault. Operations are
restricted to its canonical path, including when Proton Drive uses symlinks.
Do not change `org-directory` just to use this extension. On hosts without the
configured/running Emacs, tool calls fail with a connection/configuration error.

Optional process environment (not tool arguments):

- `PI_VULPEA_EMACSCLIENT`: emacsclient executable, default `emacsclient` on PATH.
- `PI_VULPEA_SOCKET`: named Emacs server socket; otherwise the normal default.

Apply the usual Home Manager/Darwin configuration, then restart Pi or `/reload`.
For a temporary local test before applying, launch Pi with:

```sh
pi -e ./modules/home/pi-extensions/pi-vulpea/index.ts
```

## Everyday requests

- "Find my dbt triage resource and add these verified reproduction steps."
- "Save these reusable OAuth findings as a resource and link the source."
- "Record today's discussion under Jane Doe and add a follow-up to my project."
- "Create a project under Central Data with this outcome and these tasks."
- "Show the open tasks for this project, mark this one done, and add the next action."
- "Find the decision we archived about delegated scopes."

`workflow.md` is included in each agent turn so future sessions retain the
workflow without needing conversational memory. It is also the tool namespace's
instructions. It describes resources, indexed headings inside area Notes, people,
meeting placement, task-person tags, projects, archive visibility, and boundaries
with Jira/GitLab. It does not inject the user's actual notes automatically.

## Tools

| Tool | Purpose |
| --- | --- |
| `vulpea_status` | Verify vault, database, indexing and relevant configuration |
| `vulpea_list` | Find active notes by title/alias and kind; `parentId` scopes to a file |
| `vulpea_read` | Read a whole file or a heading subtree, with revision and pagination |
| `vulpea_search` | Literal file-content search, including archives, with line snippets |
| `vulpea_create` | Resource/person file, or project/task/reference heading/meeting child |
| `vulpea_update` | Append, exact body-fragment replacement, TODO, tags, index a heading, archive |
| `vulpea_delete` | Move a standalone resource file to trash, with mandatory interactive approval |

Resources are active **file-level** reference notes, without needing a `resource`
tag. Areas are resources too. A heading with an ID inside an area is linkable and
indexed, but not a file-level resource. For `kind: "resource"` or `kind: "person"`,
omit `parentId` and `revision`: these create standalone files. To keep reference
content inside an area, use `kind: "heading"` with its Notes heading ID and latest
revision instead. To extend an existing resource, prefer `vulpea_update` rather
than creating a second copy. People get `people`, not automatically
`area`; meetings go under Meetings. `peopleIds` generates the package's `@Name`
tags for person agendas. Name/alias lookup follows the installed package. The Pi
project list checks direct tags, rather than treating a task's inherited project
tag as a project root.

Projects get `CATEGORY: Area > Project`, a TODO state, project tag, and ID under
the chosen area's Tasks heading. Tasks get IDs and can be FOCUS/WAITING/HOLD tagged.
Meetings are literal notes tagged MEETING; the bridge does not launch capture,
start clocks, or apply REFILE automatically. Only intentionally created container
headings get new IDs automatically. The explicit `index` action can give an existing
section/task an ID by exact relative outline, returning that heading for subsequent
edits. Existing notes are not mass-migrated or backfilled.

Current intentional limits: no implicit area creation, area/person deletion,
heading deletion, permanent deletion, whole-file archive, title/alias renaming,
arbitrary metadata edits, scheduling/deadlines, or
cross-file refile. Use stock Org commands for these. No background agent watches
or automatic conversation logging.

## Write safety

- Create/update operations need no approval prompt, including in print/headless
  mode. All vault, revision and buffer-safety checks still apply.
- Only `vulpea_delete` requires interactive approval, showing the resource title,
  file, revision and a warning that all children/archive content will go too.
  Headless deletion fails closed; denial never sends a delete request to Emacs.
  Areas, people and heading-level notes are protected. Trash failure never falls
  back to permanent deletion. Existing links are not rewritten.
- Deletion removes the file's active IDs/index entries and closes its clean visiting
  buffers. It is not atomic across filesystem, database and hooks: if post-trash
  cleanup fails, reconcile the index or restore from trash instead of retrying.
- Existing-note writes require a fresh whole-file SHA-256 revision returned by
  read. Editing a sibling invalidates it. Dirty, read-only or externally changed
  buffers are refused, never force-saved/reverted. Save/reconcile them in Emacs.
- Existing-file mutations participate in Pi's file mutation queue. Emacs evaluates
  a bridge request synchronously; revisions also protect separate Pi processes.
  New files have UUID names, with no overwrite; exact duplicate titles are refused.
- Text crosses the client boundary as base64 JSON, with no shell. Body text is
  inserted literally: even `%(...)` is never expanded as a capture template.
  File-local evaluation is disabled when visiting existing files via the bridge.
- Buffer edits use change groups. Normal save hooks and an explicit database
  refresh make writes visible to subsequent tools. Save/index failures
  are not a cross-file transaction; read/reconcile before retrying.
- Timeouts/aborts stop waiting, but cannot guarantee Emacs cancelled a write.
  Never retry blindly. Read the note or search for the proposed title first.
- Archive requires no open TODOs in the subtree. It moves to the same file's
  `* Archive :ARCHIVE:` and leaves active views/indexes. File search still finds it.
- Results are paginated, with a hard 50KB client limit. Reduce `limit` on large
  Unicode/metadata-heavy results. Avoid placing credentials or unnecessary
  personal details in notes or the model context.

This is a scoped API, not a sandbox against a malicious extension or unrestricted
shell access: Pi and Emacs run with the user's OS permissions. The model is
instructed not to bypass a refused bridge operation with raw file edits or Elisp.

## Validation

Bridge tests use real installed Org/Vulpea/PARA packages and a temporary vault
and database, not the user's notes. The deletion suite loads the conflict and
lifecycle suites as well; trash is simulated inside the temporary test directory:

```sh
emacs --batch -l modules/home/pi-extensions/pi-vulpea/test/delete-test.el \
  -f ert-run-tests-batch-and-exit
node --test modules/home/pi-extensions/pi-vulpea/test/client.test.ts
```

Registration tests use Pi's `jiti` and `typebox`. Point `NODE_PATH` at the
installed Pi package's `lib/node_modules` directory if not available locally:

```sh
NODE_PATH=/path/to/pi/lib/node_modules \
  node --test modules/home/pi-extensions/pi-vulpea/test/extension.test.mjs
```

No full Nix rebuild or real-vault write is needed to run these tests.
