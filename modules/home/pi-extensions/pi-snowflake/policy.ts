export type QueryRule = {
  description: string;
  pattern: RegExp;
};

/**
 * Policy for SQL submitted through pi.
 *
 * The built-in structural checks in index.ts always reject multiple statements
 * and non-read-only SQL. Add organization-specific rules here. Deny rules win;
 * when allowQueryPatterns is non-empty, a query must also match one of them.
 * Patterns are tested against the original SQL, including object names.
 */
export const snowflakePolicy = {
  maxRows: 500,
  maxOutputCharacters: 100_000,
  timeoutSeconds: 60,

  allowQueryPatterns: [] as RegExp[],

  denyQueryRules: [
    // Examples:
    // { description: "PII schemas are off limits", pattern: /\bPROD\.PII\b/i },
    // { description: "Only approved databases may be queried", pattern: /\bUNAPPROVED_DB\b/i },
  ] as QueryRule[],
};
