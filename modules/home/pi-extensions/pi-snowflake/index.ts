import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import snowflake from "snowflake-sdk";
import { Type } from "typebox";

import { snowflakePolicy } from "./policy.ts";

type BindValue = string | number | boolean | null;
type SnowflakeConnection = ReturnType<typeof snowflake.createConnection>;

const readOnlyStarts = new Set(["SELECT", "WITH", "SHOW", "DESCRIBE", "DESC", "EXPLAIN"]);
const forbiddenSql = /\b(?:INSERT|UPDATE|DELETE|MERGE|COPY|PUT|GET|REMOVE|CREATE|ALTER|DROP|TRUNCATE|UNDROP|GRANT|REVOKE|CALL|EXECUTE|USE|BEGIN|COMMIT|ROLLBACK)\b/i;
const systemFunction = /\bSYSTEM\s*\$/i;

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable ${name}.`);
  return value;
}

function connectionOptions() {
  return {
    account: requiredEnvironment("SNOWFLAKE_ACCOUNT"),
    username: requiredEnvironment("SNOWFLAKE_USER"),
    database: requiredEnvironment("SNOWFLAKE_DATABASE"),
    warehouse: process.env.SNOWFLAKE_WAREHOUSE?.trim() || "COMPUTE_WH",
    role: requiredEnvironment("SNOWFLAKE_ROLE"),
    authenticator: "SNOWFLAKE_JWT" as const,
    privateKeyPath: requiredEnvironment("SNOWFLAKE_KEYFILE_PATH"),
    privateKeyPass: requiredEnvironment("SNOWFLAKE_KEYFILE_PASSWORD"),
    clientSessionKeepAlive: false,
    jsTreatIntegerAsBigInt: true,
    application: "pi_snowflake",
  };
}

/**
 * Replace comments and quoted values with spaces while retaining SQL keywords
 * and semicolons. This avoids treating dangerous words inside strings as SQL.
 */
function structuralSql(sql: string): string {
  let output = "";
  let index = 0;
  let state: "normal" | "single" | "double" | "line-comment" | "block-comment" = "normal";

  while (index < sql.length) {
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
        index += 1;
        continue;
      }
    } else if (state === "single" && character === "'" && next === "'") {
      output += "  ";
      index += 2;
      continue;
    } else if (state === "double" && character === '"' && next === '"') {
      output += "  ";
      index += 2;
      continue;
    } else if (state === "single" && character === "'") {
      state = "normal";
    } else if (state === "double" && character === '"') {
      state = "normal";
    } else if (state === "line-comment" && (character === "\n" || character === "\r")) {
      state = "normal";
      output += character;
      index += 1;
      continue;
    } else if (state === "block-comment" && character === "*" && next === "/") {
      state = "normal";
      output += "  ";
      index += 2;
      continue;
    }

    output += " ";
    index += 1;
  }

  if (state === "single" || state === "double" || state === "block-comment") {
    throw new Error("Rejected by Snowflake policy: unterminated quote or block comment.");
  }
  return output;
}

export function validateQuery(sql: string): void {
  if (!sql.trim()) throw new Error("SQL must not be empty.");

  const structural = structuralSql(sql).trim();
  const withoutFinalSemicolon = structural.replace(/;\s*$/, "");
  if (withoutFinalSemicolon.includes(";")) {
    throw new Error("Rejected by Snowflake policy: multiple SQL statements are not allowed.");
  }

  const firstKeyword = withoutFinalSemicolon.match(/^[\s(]*([A-Z]+)/i)?.[1]?.toUpperCase();
  if (!firstKeyword || !readOnlyStarts.has(firstKeyword)) {
    throw new Error(
      `Rejected by Snowflake policy: only ${[...readOnlyStarts].join(", ")} statements are allowed.`,
    );
  }
  if (forbiddenSql.test(withoutFinalSemicolon)) {
    throw new Error("Rejected by Snowflake policy: the query contains a non-read-only SQL operation.");
  }
  if (systemFunction.test(withoutFinalSemicolon)) {
    throw new Error("Rejected by Snowflake policy: SYSTEM$ functions are not allowed.");
  }

  const denied = snowflakePolicy.denyQueryRules.find(({ pattern }) => {
    pattern.lastIndex = 0;
    return pattern.test(sql);
  });
  if (denied) throw new Error(`Rejected by Snowflake policy: ${denied.description}.`);

  if (snowflakePolicy.allowQueryPatterns.length > 0) {
    const allowed = snowflakePolicy.allowQueryPatterns.some((pattern) => {
      pattern.lastIndex = 0;
      return pattern.test(sql);
    });
    if (!allowed) throw new Error("Rejected by Snowflake policy: the query does not match an allow rule.");
  }
}

function serialize(value: unknown): string {
  return JSON.stringify(
    value,
    (_key, item) => {
      if (typeof item === "bigint") return item.toString();
      if (Buffer.isBuffer(item)) return `<binary: ${item.length} bytes>`;
      return item;
    },
    2,
  );
}

function boundedResult(metadata: Record<string, unknown>, rows: unknown[]) {
  const selectedRows: unknown[] = [];
  let result = { ...metadata, returnedRowCount: 0, outputTruncated: rows.length > 0, rows: selectedRows };

  for (const row of rows) {
    selectedRows.push(row);
    const candidate = {
      ...metadata,
      returnedRowCount: selectedRows.length,
      outputTruncated: selectedRows.length < rows.length,
      rows: selectedRows,
    };
    if (serialize(candidate).length > snowflakePolicy.maxOutputCharacters) {
      selectedRows.pop();
      break;
    }
    result = candidate;
  }

  return result;
}

function toolError(error: unknown) {
  let message = error instanceof Error ? error.message : String(error);
  const password = process.env.SNOWFLAKE_KEYFILE_PASSWORD;
  if (password) message = message.replaceAll(password, "[REDACTED]");
  return {
    content: [{ type: "text" as const, text: `Unable to query Snowflake: ${message}` }],
    isError: true,
  };
}

export default function piSnowflake(pi: ExtensionAPI) {
  let connectionPromise: Promise<SnowflakeConnection> | undefined;

  function connection(): Promise<SnowflakeConnection> {
    if (!connectionPromise) {
      connectionPromise = new Promise((resolve, reject) => {
        const candidate = snowflake.createConnection(connectionOptions());
        candidate.connect((error, establishedConnection) => {
          if (error) {
            connectionPromise = undefined;
            reject(error);
          } else {
            resolve(establishedConnection);
          }
        });
      });
    }
    return connectionPromise;
  }

  pi.on("session_shutdown", async () => {
    const pendingConnection = connectionPromise;
    connectionPromise = undefined;
    if (!pendingConnection) return;

    try {
      const activeConnection = await pendingConnection;
      await new Promise<void>((resolve) => activeConnection.destroy(() => resolve()));
    } catch {
      // A failed connection has nothing to clean up.
    }
  });

  pi.registerTool({
    name: "snowflake_query",
    label: "Query Snowflake",
    description:
      "Execute one policy-checked, read-only Snowflake query and inspect a bounded JSON result. Mutations, multiple statements, and SYSTEM$ functions are rejected.",
    parameters: Type.Object({
      sql: Type.String({ minLength: 1, description: "One read-only Snowflake SQL statement" }),
      binds: Type.Optional(
        Type.Array(
          Type.Union([Type.String(), Type.Number(), Type.Boolean(), Type.Null()]),
          { description: "Optional positional values for ? placeholders" },
        ),
      ),
      maxRows: Type.Optional(
        Type.Integer({
          minimum: 1,
          maximum: snowflakePolicy.maxRows,
          description: `Maximum rows to return; defaults to ${snowflakePolicy.maxRows}`,
        }),
      ),
    }),
    async execute(
      _toolCallId,
      { sql, binds = [], maxRows = snowflakePolicy.maxRows }: { sql: string; binds?: BindValue[]; maxRows?: number },
      signal,
    ) {
      try {
        validateQuery(sql);
        if (signal?.aborted) throw new Error("Query cancelled.");

        const activeConnection = await connection();
        const startedAt = Date.now();
        const execution = await new Promise<{ statement: any; rows: unknown[] }>((resolve, reject) => {
          let statement: any;
          let settled = false;
          const cancel = (reason: string) => {
            if (settled) return;
            settled = true;
            clearTimeout(timer);
            signal?.removeEventListener("abort", onAbort);
            statement?.cancel(() => undefined);
            reject(new Error(reason));
          };
          const timer = setTimeout(
            () => cancel(`Query exceeded the ${snowflakePolicy.timeoutSeconds}-second policy timeout.`),
            snowflakePolicy.timeoutSeconds * 1_000,
          );
          const onAbort = () => cancel("Query cancelled.");
          signal?.addEventListener("abort", onAbort, { once: true });
          if (signal?.aborted) {
            cancel("Query cancelled.");
            return;
          }

          statement = activeConnection.execute({
            sqlText: sql,
            binds,
            parameters: {
              MULTI_STATEMENT_COUNT: 1,
              QUERY_TAG: "pi-snowflake",
              STATEMENT_TIMEOUT_IN_SECONDS: snowflakePolicy.timeoutSeconds,
            },
            complete(error, completedStatement, rows) {
              clearTimeout(timer);
              signal?.removeEventListener("abort", onAbort);
              if (settled) return;
              settled = true;
              if (error) reject(error);
              else resolve({ statement: completedStatement, rows: rows ?? [] });
            },
          });
        });

        const allRows = execution.rows;
        const limitedRows = allRows.slice(0, maxRows);
        const metadata = {
          queryId: execution.statement.getStatementId?.() ?? null,
          durationMs: Date.now() - startedAt,
          totalRowCount: allRows.length,
          rowLimitApplied: allRows.length > limitedRows.length,
        };
        const result = boundedResult(metadata, limitedRows);
        return {
          content: [{ type: "text" as const, text: serialize(result) }],
          details: metadata,
        };
      } catch (error) {
        return toolError(error);
      }
    },
  });
}
