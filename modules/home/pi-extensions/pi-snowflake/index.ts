import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

import { snowflakePolicy } from "./policy.ts";
import {
  boundedResult,
  buildCommand,
  DEFAULT_ROLE,
  FNOX_EXEC_TOOL,
  parseRows,
  resultText,
  validateQuery,
} from "./query.ts";

export { validateQuery } from "./query.ts";

export default function piSnowflake(pi: ExtensionAPI) {
  pi.registerTool({
    name: "snowflake_query",
    label: "Query Snowflake",
    exposure: "direct",
    reachesTools: () => [FNOX_EXEC_TOOL],
    description:
      `Execute one policy-checked Snowflake query using Snowflake CLI through fnox MCP. Credentials stay in the child process, not Pi. Returns at most ${snowflakePolicy.maxRows} rows and ${snowflakePolicy.maxOutputCharacters} output characters. Omitted roles default to ${DEFAULT_ROLE} on every call. Mutations, multiple statements, CLI directives, and SYSTEM$ functions are rejected. CLI templating is disabled. Use SQL literals; positional binds are not supported.`,
    parameters: Type.Object({
      sql: Type.String({ minLength: 1, description: "One read-only Snowflake SQL statement" }),
      role: Type.Optional(Type.String({
        minLength: 1,
        description: `Primary Snowflake role for this query; defaults to ${DEFAULT_ROLE}`,
      })),
      maxRows: Type.Optional(Type.Integer({
        minimum: 1,
        maximum: snowflakePolicy.maxRows,
        description: `Maximum rows to return; defaults to ${snowflakePolicy.maxRows}`,
      })),
    }, { additionalProperties: false }),
    async execute(_toolCallId, { sql, role, maxRows = snowflakePolicy.maxRows }, signal, _onUpdate, ctx) {
      let timer: ReturnType<typeof setTimeout> | undefined;
      try {
        validateQuery(sql);
        if (signal?.aborted) throw new Error("Query cancelled.");
        const primaryRole = role === undefined ? DEFAULT_ROLE : role.trim();
        if (!primaryRole) throw new Error("Role must not be empty.");
        if (!Number.isInteger(maxRows) || maxRows < 1 || maxRows > snowflakePolicy.maxRows) {
          throw new Error(`maxRows must be between 1 and ${snowflakePolicy.maxRows}.`);
        }

        const timeout = new AbortController();
        timer = setTimeout(() => timeout.abort(), snowflakePolicy.timeoutSeconds * 1_000);
        const executionSignal = signal ? AbortSignal.any([signal, timeout.signal]) : timeout.signal;
        const startedAt = Date.now();
        const outcome = await ctx.executeTool(
          FNOX_EXEC_TOOL,
          { command: buildCommand(sql, primaryRole, maxRows) },
          { signal: executionSignal },
        );
        if (signal?.aborted) throw new Error("Query cancelled.");
        if (timeout.signal.aborted) {
          throw new Error(`Query exceeded the ${snowflakePolicy.timeoutSeconds}-second policy timeout.`);
        }
        // executeTool returns an AgentToolCallOutcome; the nested tool result carries
        // content and structuredContent. MCP's structured result retains full content,
        // unlike its truncated display text.
        const execution = outcome.result;
        const raw = execution.structuredContent as { content?: unknown; isError?: boolean } | undefined;
        const text = resultText(raw?.content ?? execution.content);
        if (outcome.isError || execution.isError || raw?.isError) {
          throw new Error(text || "fnox MCP exec failed. Ensure its server is enabled and Proton is logged in.");
        }
        const rows = parseRows(text);
        const metadata = {
          role: primaryRole,
          durationMs: Date.now() - startedAt,
          fetchedRowCount: rows.length,
          rowLimitApplied: rows.length > maxRows,
        };
        return {
          content: [{ type: "text", text: JSON.stringify(boundedResult(metadata, rows.slice(0, maxRows)), null, 2) }],
          details: metadata,
        };
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return {
          content: [{ type: "text", text: `Unable to query Snowflake: ${message}`.slice(0, snowflakePolicy.maxOutputCharacters) }],
          details: undefined,
          isError: true,
        };
      } finally {
        clearTimeout(timer);
      }
    },
  });
}
