import { snowflakePolicy } from "./policy.ts";

export const DEFAULT_ROLE = "CENTRAL_DATA_DATA_DEVELOPER";
export const FNOX_EXEC_TOOL = "mcp__fnox__exec";
const readOnlyStarts = new Set(["SELECT", "WITH", "SHOW", "DESCRIBE", "DESC", "EXPLAIN"]);
const forbiddenSql = /\b(?:INSERT|UPDATE|DELETE|MERGE|COPY|PUT|GET|REMOVE|CREATE|ALTER|DROP|TRUNCATE|UNDROP|GRANT|REVOKE|CALL|EXECUTE|USE|BEGIN|COMMIT|ROLLBACK)\b/i;
const systemFunction = /\bSYSTEM\s*\$/i;

/** Mask quoted values and comments, retaining statement boundaries and keywords. */
function structuralSql(sql: string): string {
  let output = "";
  let state: "normal" | "single" | "double" | "line-comment" | "block-comment" = "normal";
  for (let index = 0; index < sql.length; index += 1) {
    const character = sql[index];
    const next = sql[index + 1];
    if (state === "normal") {
      if (character === "'") state = "single";
      else if (character === '"') state = "double";
      else if (character === "-" && next === "-") {
        state = "line-comment";
        output += " ";
        index += 1;
      } else if (character === "/" && next === "*") {
        state = "block-comment";
        output += " ";
        index += 1;
      } else {
        output += character;
        continue;
      }
    } else if ((state === "single" || state === "double") && character === "\\") {
      output += "  ";
      index += 1;
      continue;
    } else if ((state === "single" && character === "'" && next === "'") ||
               (state === "double" && character === '"' && next === '"')) {
      output += "  ";
      index += 1;
      continue;
    } else if ((state === "single" && character === "'") || (state === "double" && character === '"')) {
      state = "normal";
    } else if (state === "line-comment" && (character === "\n" || character === "\r")) {
      state = "normal";
      output += character;
      continue;
    } else if (state === "block-comment" && character === "*" && next === "/") {
      state = "normal";
      output += "  ";
      index += 1;
      continue;
    }
    output += " ";
  }
  if (state === "single" || state === "double" || state === "block-comment") {
    throw new Error("Rejected by Snowflake policy: unterminated quote or block comment.");
  }
  return output;
}

export function validateQuery(sql: string): void {
  if (!sql.trim()) throw new Error("SQL must not be empty.");
  // CLI commands are interpreted before SQL; conservatively reject them even in quoted text.
  if (/^\s*!/m.test(sql)) throw new Error("Rejected by Snowflake policy: CLI directives are not allowed.");
  const structural = structuralSql(sql).trim().replace(/;\s*$/, "");
  if (structural.includes(";")) {
    throw new Error("Rejected by Snowflake policy: multiple SQL statements are not allowed.");
  }
  const firstKeyword = structural.match(/^[\s(]*([A-Z]+)/i)?.[1]?.toUpperCase();
  if (!firstKeyword || !readOnlyStarts.has(firstKeyword)) {
    throw new Error(`Rejected by Snowflake policy: only ${[...readOnlyStarts].join(", ")} statements are allowed.`);
  }
  if (forbiddenSql.test(structural)) {
    throw new Error("Rejected by Snowflake policy: the query contains a non-read-only SQL operation.");
  }
  if (systemFunction.test(structural)) {
    throw new Error("Rejected by Snowflake policy: SYSTEM$ functions are not allowed.");
  }
  const denied = snowflakePolicy.denyQueryRules.find(({ pattern }) => {
    pattern.lastIndex = 0;
    return pattern.test(sql);
  });
  if (denied) throw new Error(`Rejected by Snowflake policy: ${denied.description}.`);
  if (snowflakePolicy.allowQueryPatterns.length > 0 && !snowflakePolicy.allowQueryPatterns.some((pattern) => {
    pattern.lastIndex = 0;
    return pattern.test(sql);
  })) {
    throw new Error("Rejected by Snowflake policy: the query does not match an allow rule.");
  }
}

// Only this fixed script runs in the credential-bearing child. SQL and role are
// positional arguments, never interpolated into shell source or the TOML file.
const launcher = `set -eu
: "\${SNOWFLAKE_KEYFILE_PATH:?SNOWFLAKE_KEYFILE_PATH is missing or empty; check fnox and Proton login}"
: "\${SNOWFLAKE_KEYFILE_PASSWORD:?SNOWFLAKE_KEYFILE_PASSWORD is missing or empty; check fnox and Proton login}"
export SNOWFLAKE_PRIVATE_KEY_FILE="$SNOWFLAKE_KEYFILE_PATH"
export PRIVATE_KEY_PASSPHRASE="$SNOWFLAKE_KEYFILE_PASSWORD"
umask 077
config_dir=$(mktemp -d)
trap 'rm -rf "$config_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
export SNOWFLAKE_HOME="$config_dir"
cat > "$config_dir/config.toml" <<EOF
[cli]
ignore_new_version_warning = true
[cli.logs]
save_logs = false
[connections.pi]
authenticator = "SNOWFLAKE_JWT"
[connections.pi.session_parameters]
QUERY_TAG = "pi-snowflake"
STATEMENT_TIMEOUT_IN_SECONDS = $4
ABORT_DETACHED_QUERY = true
ROWS_PER_RESULTSET = $3
MULTI_STATEMENT_COUNT = 1
EOF
snow --config-file "$config_dir/config.toml" sql --connection pi --role "$2" --format JSON --enable-templating NONE --query "$1"
`;

export function buildCommand(sql: string, role: string, maxRows: number): string[] {
  return ["sh", "-c", launcher, "pi-snowflake", sql, role, String(maxRows + 1), String(snowflakePolicy.timeoutSeconds)];
}

export function resultText(content: unknown): string {
  if (!Array.isArray(content)) return "";
  return content.filter((block) => block?.type === "text" && typeof block.text === "string")
    .map((block) => block.text).join("\n");
}

export function parseRows(text: string): unknown[] {
  // fnox appends stderr after stdout; successful CLI warnings are not JSON data.
  const stdout = text.split("\n[stderr]\n", 1)[0].trim();
  let rows: unknown;
  try {
    rows = JSON.parse(stdout);
  } catch {
    throw new Error("Snowflake CLI did not return complete JSON. Output may exceed fnox's capture limit; use a smaller LIMIT or fewer columns.");
  }
  if (!Array.isArray(rows) || rows.some((row) => row === null || typeof row !== "object" || Array.isArray(row))) {
    throw new Error("Snowflake CLI returned an unexpected result shape; expected an array of rows.");
  }
  return rows;
}

export function boundedResult(metadata: Record<string, unknown>, rows: unknown[]) {
  const selectedRows: unknown[] = [];
  for (const row of rows) {
    selectedRows.push(row);
    const candidate = { ...metadata, returnedRowCount: selectedRows.length, outputTruncated: selectedRows.length < rows.length, rows: selectedRows };
    if (JSON.stringify(candidate, null, 2).length > snowflakePolicy.maxOutputCharacters) {
      selectedRows.pop();
      break;
    }
  }
  return { ...metadata, returnedRowCount: selectedRows.length, outputTruncated: selectedRows.length < rows.length, rows: selectedRows };
}
