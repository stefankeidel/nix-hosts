# Pi Snowflake

Registers `snowflake_query` with direct tool exposure. Queries run through
`ctx.executeTool("mcp__fnox__exec", ...)`, so nested calls remain visible to Pi's
permission hooks. The extension never retrieves secrets or reads credential
environment variables in Pi's process.

## Requirements

- A configured, enabled Pi MCP server named `fnox`, offering `exec`.
- `snow` (Snowflake CLI) on the MCP server's PATH, with `--enable-templating NONE` support.
- Proton Pass logged in, if used as the fnox provider.
- fnox supplies `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`,
  `SNOWFLAKE_KEYFILE_PATH` (`as_file = true` for a key stored in the vault),
  and `SNOWFLAKE_KEYFILE_PASSWORD` to the child. Database and warehouse can be
  supplied as `SNOWFLAKE_DATABASE` and `SNOWFLAKE_WAREHOUSE`.

Keep credentials exec-only and disable raw retrieval, for example:

```toml
env = "exec"

[mcp]
tools = ["exec"]
```

An explicit `[mcp].secrets` allowlist must include the required secrets. Restart
or reconnect the server after configuration or provider-login changes if an
older secret resolution remains cached. There is no fallback to `get_secret`,
Pi's environment, or direct shell execution.

## Execution

The tool accepts `sql`, optional `role`, and optional `maxRows`. The role defaults
to `CENTRAL_DATA_DATA_DEVELOPER` on every call; sessions are not reused.

A fixed child shell script maps the existing dbt key variables to
`SNOWFLAKE_PRIVATE_KEY_FILE` and `PRIVATE_KEY_PASSPHRASE`. SQL and role travel as
separate positional arguments, never as shell source. A private temporary CLI
configuration sets JWT authentication, a query tag, a server statement timeout,
and `ROWS_PER_RESULTSET = maxRows + 1`. It contains no credentials, disables CLI
file logging, ignores saved user connections, and is removed on exit.

ROWS_PER_RESULTSET limits returned rows, not query computation or warehouse
cost. Results are also capped locally by row count and serialized output length. `fetchedRowCount` describes CLI output, not the total
relation size. `rowLimitApplied` indicates discarded fetched rows;
`outputTruncated` indicates rows omitted by the character budget. For large or
wide results, specify a small SQL LIMIT and select only necessary columns. If
fnox's capture limit truncates JSON, the tool reports an error rather than
returning partial or misleading data.

The previous SDK-only `binds` argument is no longer supported. Snowflake CLI's
textual template variables are not equivalent to native parameter binding, so
all CLI templating is disabled. Query IDs and exact total row counts are not
reported by this JSON CLI transport. A local abort signal limits the MCP wait;
remote process termination depends on fnox's cancellation handling. A server-side
statement timeout additionally limits SQL execution, but not login time.

The SQL checks are conservative guardrails, not a security sandbox. They reject
mutations, multiple statements, SYSTEM$ functions, and CLI directive lines.
Read-only-looking SQL can still call side-effecting functions. Snowflake roles
and grants must enforce actual access restrictions. Generic fnox `exec` remains
an arbitrary-command capability; output redaction is not isolation.

## Development

```sh
npm ci
npm test
```

Runtime uses Pi's host-provided TypeBox; there are no bundled npm runtime
dependencies. The Nix package copies the extension sources without the former
Snowflake SDK dependency tree. `snow` is an external prerequisite on the MCP
server's PATH, not installed by this package.
