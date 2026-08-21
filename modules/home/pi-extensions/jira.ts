import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const issueKeyPattern = /^[A-Z][A-Z0-9_]*-\d+$/;
const projectKeyPattern = /^[A-Z][A-Z0-9_]*$/;
const centralDataProjectKey = "CD";

// REQUIRE controls store their purpose and English/German requirement texts in
// language-specific custom fields. Keep the IDs in one place so the normal
// issue fields and the translated requirement text are returned together.
const requirementLanguageFields = {
  purpose: "customfield_10966",
  englishMust: "customfield_10953",
  englishShould: "customfield_10954",
  germanPurpose: "customfield_10955",
  germanMust: "customfield_10957",
  germanShould: "customfield_10956",
} as const;

const issueListFields = [
  "summary",
  "status",
  "issuetype",
  "priority",
  "assignee",
  "labels",
  "description",
  "parent",
  "customfield_10014",
];

function config() {
  const baseUrl = (
    process.env.JIRA_BASE_URL ??
    process.env.ATLASSIAN_BASE_URL ??
    "https://lichtblick.atlassian.net"
  ).replace(/\/+$/, "");
  const email =
    process.env.JIRA_EMAIL ??
    process.env.JIRA_USER_EMAIL ??
    process.env.ATLASSIAN_EMAIL ??
    process.env.ATLASSIAN_USER_EMAIL;
  const token = process.env.JIRA_API_TOKEN ?? process.env.ATLASSIAN_API_TOKEN;

  if (!email || !token) {
    throw new Error(
      "Jira credentials are missing. Set JIRA_EMAIL (or ATLASSIAN_EMAIL) and " +
        "JIRA_API_TOKEN (or ATLASSIAN_API_TOKEN).",
    );
  }

  return { baseUrl, authorization: `Basic ${Buffer.from(`${email}:${token}`).toString("base64")}` };
}

async function jiraRequest(path: string, method: string, body?: unknown, signal?: AbortSignal): Promise<any> {
  const { baseUrl, authorization } = config();
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      Authorization: authorization,
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    signal,
  });

  if (!response.ok) {
    const responseBody = await response.text();
    let message = responseBody;
    try {
      const error = JSON.parse(responseBody) as { errorMessages?: string[]; errors?: Record<string, string> };
      message = [
        ...(error.errorMessages ?? []),
        ...Object.entries(error.errors ?? {}).map(([field, value]) => `${field}: ${value}`),
      ].join("; ") || responseBody;
    } catch {
      // Keep the plain response body when Jira did not return JSON.
    }
    throw new Error(`Jira returned ${response.status}: ${message.slice(0, 500)}`);
  }

  if (response.status === 204) return undefined;
  return response.json();
}

function jiraGet(path: string, signal?: AbortSignal): Promise<any> {
  return jiraRequest(path, "GET", undefined, signal);
}

function normalizedIssueKey(value: string, name = "Jira issue key"): string {
  const key = value.trim().toUpperCase();
  if (!issueKeyPattern.test(key)) throw new Error(`Invalid ${name}. Use a key such as REQUIRE-124.`);
  return key;
}

function normalizedProjectKey(value: string): string {
  const key = value.trim().toUpperCase();
  if (!projectKeyPattern.test(key)) throw new Error("Invalid Jira project key. Use a key such as REQUIRE.");
  return key;
}

function requireCentralDataProject(projectKey: string): void {
  if (projectKey !== centralDataProjectKey) {
    throw new Error(`Jira issue creation and description updates are restricted to the ${centralDataProjectKey} (Central Data) project.`);
  }
}

type AdfNode = {
  type?: string;
  text?: string;
  attrs?: Record<string, unknown>;
  content?: AdfNode[];
};

/** Turn Jira's Atlassian Document Format into readable, model-friendly text. */
function adfText(node: AdfNode | undefined): string {
  if (!node) return "";
  if (node.type === "text") return node.text ?? "";
  if (node.type === "hardBreak") return "\n";
  if (node.type === "mention") return `@${String(node.attrs?.text ?? node.attrs?.id ?? "mention")}`;
  if (node.type === "emoji") return String(node.attrs?.text ?? node.attrs?.shortName ?? "");
  if (node.type === "inlineCard") return String(node.attrs?.url ?? "");

  const children = (node.content ?? []).map(adfText).join("");
  switch (node.type) {
    case "paragraph":
    case "heading":
    case "blockquote":
    case "codeBlock":
      return `${children}\n`;
    case "bulletList":
    case "orderedList":
      return children;
    case "listItem":
      return `- ${children.trim()}\n`;
    default:
      return children;
  }
}

function cleanAdf(value: unknown): string {
  if (typeof value === "string") return value;
  return adfText(value as AdfNode).trim();
}

/** Convert plain text to the minimal ADF document Jira Cloud accepts. */
function textToAdf(text: string) {
  return {
    type: "doc",
    version: 1,
    content: text.split(/\n{2,}/).map((paragraph) => ({
      type: "paragraph",
      content: [{ type: "text", text: paragraph }],
    })),
  };
}

function descriptionExcerpt(value: unknown, limit = 500): string | null {
  const text = cleanAdf(value);
  if (!text) return null;
  return text.length > limit ? `${text.slice(0, limit - 1)}…` : text;
}

function issueSummary(issue: Record<string, any>) {
  const fields = issue.fields ?? {};
  const description = cleanAdf(fields.description);
  return {
    key: issue.key,
    summary: fields.summary,
    status: fields.status?.name,
    issueType: fields.issuetype?.name,
    priority: fields.priority?.name ?? null,
    assignee: fields.assignee?.displayName ?? fields.assignee?.emailAddress ?? null,
    labels: fields.labels ?? [],
    parent: fields.parent?.key ?? null,
    epic: fields.customfield_10014 ?? null,
    hasDescription: Boolean(description),
    descriptionExcerpt: descriptionExcerpt(fields.description),
    updated: fields.updated ?? null,
    url: `${config().baseUrl}/browse/${issue.key}`,
  };
}

async function searchJira(jql: string, maxResults: number, signal?: AbortSignal, nextPageToken?: string) {
  // POST avoids URL-length limits and the endpoint is Jira's current JQL search API.
  const page = await jiraRequest(
    "/rest/api/3/search/jql",
    "POST",
    { jql, maxResults, fields: issueListFields, ...(nextPageToken ? { nextPageToken } : {}) },
    signal,
  );
  const issues = (page.issues ?? []).map(issueSummary);
  return {
    jql,
    total: page.total ?? issues.length,
    issues,
    nextPageToken: page.nextPageToken ?? null,
    truncated: page.isLast === false || Boolean(page.nextPageToken),
  };
}

function toolError(prefix: string, error: unknown) {
  return {
    content: [{ type: "text" as const, text: `${prefix}: ${error instanceof Error ? error.message : String(error)}` }],
    isError: true,
  };
}

/** Require an interactive user decision before every Jira mutation. */
async function confirmJiraWrite(ctx: ExtensionContext, action: string): Promise<void> {
  if (!ctx.hasUI) {
    throw new Error(`Cannot ${action}: Jira writes require an interactive user confirmation.`);
  }
  const confirmed = await ctx.ui.confirm("Confirm Jira write", action);
  if (!confirmed) throw new Error("Jira write cancelled by the user.");
}

const issueKeyParameters = Type.Object({
  issueKey: Type.String({
    description: "Jira issue key, for example REQUIRE-124",
    pattern: "^[A-Z][A-Z0-9_]*-[0-9]+$",
  }),
});

export type JiraReadInput = { issueKey: string };

/** Jira read and carefully scoped work-planning operations. */
export default function jiraRead(pi: ExtensionAPI) {
  pi.registerTool({
    name: "jira_read_issue",
    label: "Read Jira issue",
    description: "Read a Jira issue. Comments are omitted by default; request a bounded number only when their discussion is needed.",
    parameters: Type.Intersect([
      issueKeyParameters,
      Type.Object({
        includeComments: Type.Optional(Type.Boolean({ description: "Include comments; defaults to false" })),
        commentLimit: Type.Optional(Type.Integer({ minimum: 1, maximum: 100, description: "Newest comments to return when includeComments is true; defaults to 10" })),
      }),
    ]),
    async execute(_toolCallId, { issueKey, includeComments = false, commentLimit = 10 }: JiraReadInput & { includeComments?: boolean; commentLimit?: number }, signal) {
      let normalizedKey: string;
      try {
        normalizedKey = normalizedIssueKey(issueKey);
        const requestedFields = [
          "summary", "description", "project", "issuetype", "status", "priority", "labels", "comment",
          "reporter", "assignee", "created", "updated", ...Object.values(requirementLanguageFields),
        ].join(",");
        const issue = await jiraGet(
          `/rest/api/3/issue/${encodeURIComponent(normalizedKey)}?fields=${encodeURIComponent(requestedFields)}`,
          signal,
        );

        const fields = issue.fields ?? {};
        const commentPage = includeComments
          ? await jiraGet(
            `/rest/api/3/issue/${encodeURIComponent(normalizedKey)}/comment?orderBy=-created&maxResults=${commentLimit}`,
            signal,
          ) as { comments?: Array<Record<string, unknown>>; total?: number }
          : undefined;
        const comments = commentPage?.comments ?? [];
        const totalCommentCount = commentPage?.total ?? fields.comment?.total ?? 0;
        const requirementText = Object.fromEntries(
          Object.entries(requirementLanguageFields).map(([name, fieldId]) => [name, cleanAdf(fields[fieldId])]),
        );
        const result = {
          key: issue.key ?? normalizedKey,
          summary: fields.summary,
          description: cleanAdf(fields.description),
          project: fields.project?.key ?? fields.project?.name,
          issueType: fields.issuetype?.name,
          status: fields.status?.name,
          priority: fields.priority?.name,
          labels: fields.labels ?? [],
          reporter: fields.reporter?.displayName ?? fields.reporter?.emailAddress,
          assignee: fields.assignee?.displayName ?? fields.assignee?.emailAddress ?? null,
          created: fields.created,
          updated: fields.updated,
          requirementText,
          totalCommentCount,
          comments: comments.map((comment) => ({
            id: comment.id,
            author: (comment.author as Record<string, unknown> | undefined)?.displayName ??
              (comment.author as Record<string, unknown> | undefined)?.emailAddress,
            created: comment.created,
            updated: comment.updated,
            body: descriptionExcerpt(comment.body, 2_000) ?? "",
          })),
        };
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
          details: { issueKey: normalizedKey, commentCount: comments.length, totalCommentCount },
        };
      } catch (error) {
        return toolError(`Unable to read ${normalizedKey ?? issueKey.trim()}`, error);
      }
    },
  });

  pi.registerTool({
    name: "list_open_project_issues",
    label: "List open Jira project issues",
    description: "List open Jira issues in a project, ordered by most recently updated.",
    parameters: Type.Object({
      projectKey: Type.String({ description: "Jira project key, for example REQUIRE" }),
      maxResults: Type.Optional(Type.Integer({ minimum: 1, maximum: 100, description: "Maximum issues to return; defaults to 100" })),
      nextPageToken: Type.Optional(Type.String({ description: "Pagination cursor from an earlier list result" })),
    }),
    async execute(_toolCallId, { projectKey, maxResults = 100, nextPageToken }: { projectKey: string; maxResults?: number; nextPageToken?: string }, signal) {
      try {
        const key = normalizedProjectKey(projectKey);
        const result = await searchJira(`project = ${key} AND statusCategory != Done ORDER BY updated DESC`, maxResults, signal, nextPageToken);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }], details: { projectKey: key } };
      } catch (error) {
        return toolError("Unable to list open Jira project issues", error);
      }
    },
  });

  pi.registerTool({
    name: "search_issues",
    label: "Search Jira issues",
    description: "Search Jira issues by text, project, and/or epic. Set epicKey to return issues linked to that epic.",
    parameters: Type.Object({
      projectKey: Type.Optional(Type.String({ description: "Optional Jira project key" })),
      epicKey: Type.Optional(Type.String({ description: "Optional epic issue key; filters to issues in that epic" })),
      text: Type.Optional(Type.String({ description: "Optional words to search in Jira's text index" })),
      openOnly: Type.Optional(Type.Boolean({ description: "Only return issues not in the Done status category; defaults to false" })),
      maxResults: Type.Optional(Type.Integer({ minimum: 1, maximum: 100, description: "Maximum issues to return; defaults to 50" })),
      nextPageToken: Type.Optional(Type.String({ description: "Pagination cursor from an earlier search result" })),
    }),
    async execute(_toolCallId, input: { projectKey?: string; epicKey?: string; text?: string; openOnly?: boolean; maxResults?: number; nextPageToken?: string }, signal) {
      try {
        const clauses: string[] = [];
        if (input.projectKey) clauses.push(`project = ${normalizedProjectKey(input.projectKey)}`);
        if (input.epicKey) {
          // customfield_10014 is the Epic Link field used when creating issues in this Jira instance.
          clauses.push(`cf[10014] = ${normalizedIssueKey(input.epicKey, "epic key")}`);
        }
        if (input.text?.trim()) clauses.push(`text ~ "${input.text.trim().replace(/[\\"]/g, "\\$&")}"`);
        if (input.openOnly) clauses.push("statusCategory != Done");
        const result = await searchJira(
          `${clauses.length ? clauses.join(" AND ") : "ORDER BY updated DESC"}${clauses.length ? " ORDER BY updated DESC" : ""}`,
          input.maxResults ?? 50,
          signal,
          input.nextPageToken,
        );
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }], details: { jqlClauses: clauses } };
      } catch (error) {
        return toolError("Unable to search Jira issues", error);
      }
    },
  });

  pi.registerTool({
    name: "search_issues_jql",
    label: "Search Jira issues with JQL",
    description: "Run a read-only JQL search and return compact issue cards. Results are capped at 100 and support cursor pagination.",
    parameters: Type.Object({
      jql: Type.String({ minLength: 1, description: "Read-only Jira Query Language expression" }),
      maxResults: Type.Optional(Type.Integer({ minimum: 1, maximum: 100, description: "Maximum issues to return; defaults to 50" })),
      nextPageToken: Type.Optional(Type.String({ description: "Pagination cursor from an earlier search result" })),
    }),
    async execute(_toolCallId, { jql, maxResults = 50, nextPageToken }: { jql: string; maxResults?: number; nextPageToken?: string }, signal) {
      try {
        if (!jql.trim()) throw new Error("JQL must not be empty.");
        const result = await searchJira(jql.trim(), maxResults, signal, nextPageToken);
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }], details: { jql: jql.trim() } };
      } catch (error) {
        return toolError("Unable to search Jira issues with JQL", error);
      }
    },
  });

  pi.registerTool({
    name: "get_issue_summaries",
    label: "Get Jira issue summaries",
    description: "Fetch up to 20 Jira issues in one call. Use compact for issue cards or planning for full descriptions, requirement fields, links, and subtasks. Comments are never included.",
    parameters: Type.Object({
      issueKeys: Type.Array(Type.String({ pattern: "^[A-Z][A-Z0-9_]*-[0-9]+$" }), { minItems: 1, maxItems: 20, description: "One to 20 Jira issue keys" }),
      detailLevel: Type.Optional(Type.Union([Type.Literal("compact"), Type.Literal("planning")], { description: "compact by default; planning includes full planning fields" })),
    }),
    async execute(_toolCallId, { issueKeys, detailLevel = "compact" }: { issueKeys: string[]; detailLevel?: "compact" | "planning" }, signal) {
      try {
        const keys = [...new Set(issueKeys.map((key) => normalizedIssueKey(key)))];
        const fields = detailLevel === "planning"
          ? [...issueListFields, "project", "reporter", "issuelinks", "subtasks", ...Object.values(requirementLanguageFields)].join(",")
          : issueListFields.join(",");
        const results = await Promise.all(keys.map(async (key) => {
          try {
            const issue = await jiraGet(
              `/rest/api/3/issue/${encodeURIComponent(key)}?fields=${encodeURIComponent(fields)}`,
              signal,
            );
            if (detailLevel === "compact") return issueSummary(issue);
            const issueFields = issue.fields ?? {};
            return {
              ...issueSummary(issue),
              description: cleanAdf(issueFields.description),
              project: issueFields.project?.key ?? null,
              reporter: issueFields.reporter?.displayName ?? issueFields.reporter?.emailAddress ?? null,
              requirementText: Object.fromEntries(
                Object.entries(requirementLanguageFields).map(([name, fieldId]) => [name, cleanAdf(issueFields[fieldId])]),
              ),
              links: (issueFields.issuelinks ?? []).map((link: Record<string, any>) => ({
                type: link.type?.name ?? null,
                inward: link.inwardIssue?.key ?? null,
                outward: link.outwardIssue?.key ?? null,
              })),
              subtasks: (issueFields.subtasks ?? []).map((subtask: Record<string, any>) => ({
                key: subtask.key,
                summary: subtask.fields?.summary ?? null,
                status: subtask.fields?.status?.name ?? null,
              })),
            };
          } catch (error) {
            return { key, error: error instanceof Error ? error.message : String(error) };
          }
        }));
        return { content: [{ type: "text", text: JSON.stringify({ detailLevel, issues: results }, null, 2) }], details: { issueCount: keys.length, detailLevel } };
      } catch (error) {
        return toolError("Unable to get Jira issue summaries", error);
      }
    },
  });

  pi.registerTool({
    name: "search_issue_comments",
    label: "Search Jira issue comments",
    description: "Search up to the 100 newest comments of one Jira issue. Use this instead of loading comments with the issue when looking for a prior decision.",
    parameters: Type.Intersect([
      issueKeyParameters,
      Type.Object({
        text: Type.Optional(Type.String({ description: "Optional case-insensitive text to match in comment bodies" })),
        maxResults: Type.Optional(Type.Integer({ minimum: 1, maximum: 100, description: "Maximum matching comments to return; defaults to 20" })),
      }),
    ]),
    async execute(_toolCallId, { issueKey, text, maxResults = 20 }: { issueKey: string; text?: string; maxResults?: number }, signal) {
      try {
        const key = normalizedIssueKey(issueKey);
        const page = await jiraGet(
          `/rest/api/3/issue/${encodeURIComponent(key)}/comment?orderBy=-created&maxResults=100`,
          signal,
        ) as { comments?: Array<Record<string, any>>; total?: number };
        const needle = text?.trim().toLowerCase();
        const comments = (page.comments ?? [])
          .map((comment) => ({
            id: comment.id,
            author: comment.author?.displayName ?? comment.author?.emailAddress ?? null,
            created: comment.created,
            updated: comment.updated,
            body: cleanAdf(comment.body),
          }))
          .filter((comment) => !needle || comment.body.toLowerCase().includes(needle))
          .slice(0, maxResults)
          .map((comment) => ({ ...comment, body: descriptionExcerpt(comment.body, 1_000) ?? "" }));
        return {
          content: [{ type: "text", text: JSON.stringify({ key, totalCommentCount: page.total ?? 0, searchedNewestComments: page.comments?.length ?? 0, truncated: (page.total ?? 0) > (page.comments?.length ?? 0), comments }, null, 2) }],
          details: { issueKey: key, commentCount: comments.length },
        };
      } catch (error) {
        return toolError("Unable to search Jira comments", error);
      }
    },
  });

  pi.registerTool({
    name: "add_comment",
    label: "Add Jira comment",
    description: "Post a plain-text comment to an existing Jira issue.",
    parameters: Type.Intersect([issueKeyParameters, Type.Object({ body: Type.String({ minLength: 1, description: "Comment text" }) })]),
    async execute(_toolCallId, { issueKey, body }: { issueKey: string; body: string }, signal, _onUpdate, ctx) {
      try {
        const key = normalizedIssueKey(issueKey);
        await confirmJiraWrite(ctx, `Post a comment to ${key}?`);
        const comment = await jiraRequest(`/rest/api/3/issue/${encodeURIComponent(key)}/comment`, "POST", { body: textToAdf(body) }, signal);
        return { content: [{ type: "text", text: `Comment added to ${key}.` }], details: { issueKey: key, commentId: comment.id } };
      } catch (error) {
        return toolError("Unable to add Jira comment", error);
      }
    },
  });

  pi.registerTool({
    name: "create_issue",
    label: "Create Jira issue",
    description: "Create a Jira issue in the CD (Central Data) project only. The optional epicKey links the new issue to an epic.",
    parameters: Type.Object({
      projectKey: Type.String({ description: "Jira project key, for example REQUIRE" }),
      summary: Type.String({ minLength: 1, description: "Issue summary/title" }),
      issueType: Type.String({ minLength: 1, description: "Issue type name, for example Task, Story, Bug, or Epic" }),
      description: Type.Optional(Type.String({ description: "Optional plain-text issue description" })),
      labels: Type.Optional(Type.Array(Type.String(), { description: "Optional labels" })),
      epicKey: Type.Optional(Type.String({ description: "Optional epic key to link the issue to" })),
      parentKey: Type.Optional(Type.String({ description: "Optional parent key; required for sub-tasks" })),
    }),
    async execute(_toolCallId, input: { projectKey: string; summary: string; issueType: string; description?: string; labels?: string[]; epicKey?: string; parentKey?: string }, signal, _onUpdate, ctx) {
      try {
        const projectKey = normalizedProjectKey(input.projectKey);
        requireCentralDataProject(projectKey);
        const fields: Record<string, unknown> = {
          project: { key: projectKey },
          summary: input.summary.trim(),
          issuetype: { name: input.issueType.trim() },
        };
        if (!input.summary.trim() || !input.issueType.trim()) throw new Error("Issue summary and issue type must not be empty.");
        if (input.description !== undefined) fields.description = textToAdf(input.description);
        if (input.labels?.length) fields.labels = input.labels;
        if (input.epicKey) fields.customfield_10014 = normalizedIssueKey(input.epicKey, "epic key");
        if (input.parentKey) fields.parent = { key: normalizedIssueKey(input.parentKey, "parent key") };
        await confirmJiraWrite(ctx, `Create ${input.issueType.trim()} "${input.summary.trim()}" in ${projectKey}?`);
        const issue = await jiraRequest("/rest/api/3/issue", "POST", { fields }, signal);
        return {
          content: [{ type: "text", text: JSON.stringify({ key: issue.key, url: `${config().baseUrl}/browse/${issue.key}` }, null, 2) }],
          details: { issueKey: issue.key },
        };
      } catch (error) {
        return toolError("Unable to create Jira issue", error);
      }
    },
  });

  pi.registerTool({
    name: "update_issue_description",
    label: "Update Jira issue description",
    description: "Replace an issue's entire description in the CD (Central Data) project only. Read the issue first if existing content must be preserved.",
    parameters: Type.Intersect([issueKeyParameters, Type.Object({ description: Type.String({ description: "Full replacement description in plain text" }) })]),
    async execute(_toolCallId, { issueKey, description }: { issueKey: string; description: string }, signal, _onUpdate, ctx) {
      try {
        const key = normalizedIssueKey(issueKey);
        // Do not infer ownership from the issue-key prefix; Jira's project field is authoritative.
        const issue = await jiraGet(
          `/rest/api/3/issue/${encodeURIComponent(key)}?fields=project`,
          signal,
        );
        requireCentralDataProject(issue.fields?.project?.key);
        await confirmJiraWrite(ctx, `Replace the entire description of ${key}?`);
        await jiraRequest(
          `/rest/api/3/issue/${encodeURIComponent(key)}`,
          "PUT",
          { fields: { description: description ? textToAdf(description) : null } },
          signal,
        );
        return { content: [{ type: "text", text: `Description of ${key} updated.` }], details: { issueKey: key } };
      } catch (error) {
        return toolError("Unable to update Jira issue description", error);
      }
    },
  });
}
