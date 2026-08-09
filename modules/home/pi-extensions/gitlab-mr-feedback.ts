import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { DEFAULT_MAX_BYTES, DEFAULT_MAX_LINES, truncateHead } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

type MergeRequest = {
	iid?: number;
	id?: number;
	title?: string;
	web_url?: string;
	author?: { username?: string; name?: string };
	updated_at?: string;
};

type DiscussionNote = {
	id?: number;
	body?: string;
	author?: { username?: string; name?: string };
	created_at?: string;
	resolved?: boolean;
	position?: {
		new_path?: string;
		new_line?: number;
		old_path?: string;
		old_line?: number;
	} | null;
};

type Discussion = {
	id?: string;
	resolved?: boolean;
	resolvable?: boolean;
	notes?: DiscussionNote[];
};

const toolParameters = Type.Object({
	action: StringEnum(["inspect", "reply", "resolve"] as const, {
		description: "inspect open-MR feedback, reply to a discussion, or resolve a discussion",
	}),
	discussion_id: Type.Optional(Type.String({ description: "Discussion ID returned by inspect; required for reply and resolve" })),
	message: Type.Optional(Type.String({ description: "Reply text; required for reply" })),
});

function commandError(command: string, stderr: string, code: number | null): Error {
	return new Error(`${command} failed (${code ?? "terminated"}): ${stderr.trim() || "no error output"}`);
}

function parseJson<T>(value: string, description: string): T {
	try {
		return JSON.parse(value) as T;
	} catch {
		throw new Error(`Could not parse ${description} from glab.`);
	}
}

function summarizeDiscussions(discussions: Discussion[]): string {
	if (discussions.length === 0) {
		return "No unresolved discussions were found.";
	}

	return discussions.map((discussion, index) => {
		const notes = discussion.notes ?? [];
		const latest = notes.at(-1);
		const position = latest?.position;
		const location = position
			? ` at ${position.new_path ?? position.old_path ?? "unknown file"}:${position.new_line ?? position.old_line ?? "?"}`
			: "";
		const author = latest?.author?.username ?? latest?.author?.name ?? "unknown author";
		const body = latest?.body?.trim() || "(empty note)";
		return [
			`### ${index + 1}. Discussion ${discussion.id ?? "unknown"}${location}`,
			`- Resolvable: ${discussion.resolvable ? "yes" : "no"}; resolved: ${discussion.resolved ? "yes" : "no"}`,
			`- Latest feedback from ${author}: ${body}`,
			notes.length > 1 ? `- Thread contains ${notes.length} notes.` : "",
		].filter(Boolean).join("\n");
	}).join("\n\n");
}

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "gitlab_mr_feedback",
		label: "GitLab MR Feedback",
		description: "Inspect unresolved GitLab merge-request discussions for the current git branch, reply to a specific discussion, or resolve one after the feedback has been addressed.",
		promptSnippet: "Inspect and manage unresolved GitLab MR feedback for the current branch",
		promptGuidelines: [
			"Use gitlab_mr_feedback with action inspect before acting on GitLab merge-request feedback for the current branch.",
			"After gitlab_mr_feedback inspect, triage feedback into green/yellow/red and obtain user approval before changing code or posting replies.",
			"Use gitlab_mr_feedback reply and resolve only after the requested change is complete and the user has approved posting to GitLab. Include that Copilot generated the reply when applicable.",
		],
		parameters: toolParameters,

		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			if (params.action === "inspect") {
				onUpdate?.({ content: [{ type: "text", text: "Finding the open merge request and its unresolved discussions…" }] });

				const branchResult = await pi.exec("git", ["symbolic-ref", "--quiet", "--short", "HEAD"], {
					cwd: ctx.cwd,
					signal,
					timeout: 5_000,
				});
				if (branchResult.code !== 0) {
					throw new Error("Cannot inspect MR feedback from a detached HEAD or non-git working tree.");
				}
				const branch = branchResult.stdout.trim();

				const mrResult = await pi.exec("glab", [
					"mr", "list", "--source-branch", branch, "--output", "json", "--per-page", "100",
				], { cwd: ctx.cwd, signal, timeout: 15_000 });
				if (mrResult.code !== 0) {
					throw commandError("glab mr list", mrResult.stderr, mrResult.code);
				}
				const mergeRequests = parseJson<MergeRequest[]>(mrResult.stdout, "merge-request list");
				if (mergeRequests.length === 0) {
					return {
						content: [{ type: "text", text: `No open GitLab merge request was found for branch \`${branch}\`.` }],
						details: { branch, mergeRequests: [] },
					};
				}

				const feedback = await Promise.all(mergeRequests.map(async (mr) => {
					const iid = mr.iid ?? mr.id;
					if (!iid) {
						throw new Error("glab returned a merge request without an IID.");
					}
					const notesResult = await pi.exec("glab", [
						"mr", "note", "list", String(iid), "--state", "unresolved", "--output", "json",
					], { cwd: ctx.cwd, signal, timeout: 15_000 });
					if (notesResult.code !== 0) {
						throw commandError(`glab mr note list ${iid}`, notesResult.stderr, notesResult.code);
					}
					const discussions = parseJson<Discussion[]>(notesResult.stdout, `unresolved discussions for MR !${iid}`);
					return { mr, iid, discussions };
				}));

				const output = [
					`# Open GitLab MR feedback for branch \`${branch}\``,
					...feedback.map(({ mr, iid, discussions }) => [
						`## !${iid}: ${mr.title ?? "(untitled)"}`,
						mr.web_url ? `URL: ${mr.web_url}` : "",
						summarizeDiscussions(discussions),
					].filter(Boolean).join("\n\n")),
					"\nNext: assess each unresolved thread against the current code, triage it (green/yellow/red), and ask the user for approval before making changes.",
				].join("\n\n");
				const truncated = truncateHead(output, { maxBytes: DEFAULT_MAX_BYTES, maxLines: DEFAULT_MAX_LINES });
				const text = truncated.truncated
					? `${truncated.content}\n\n[Feedback output truncated.]`
					: truncated.content;

				return {
					content: [{ type: "text", text }],
					details: {
						branch,
						mergeRequests: feedback.map(({ mr, iid, discussions }) => ({
							iid,
							title: mr.title,
							url: mr.web_url,
							unresolvedDiscussionIds: discussions.map((discussion) => discussion.id),
						})),
					},
				};
			}

			if (!params.discussion_id?.trim()) {
				throw new Error(`discussion_id is required for ${params.action}. Run inspect first and use an ID it returns.`);
			}

			if (params.action === "reply") {
				if (!params.message?.trim()) {
					throw new Error("message is required for reply.");
				}
				const result = await pi.exec("glab", [
					"mr", "note", "create", "--reply", params.discussion_id, "--message", params.message,
				], { cwd: ctx.cwd, signal, timeout: 15_000 });
				if (result.code !== 0) {
					throw commandError("glab mr note create", result.stderr, result.code);
				}
				return {
					content: [{ type: "text", text: `Replied to GitLab discussion ${params.discussion_id}.` }],
					details: { action: "reply", discussionId: params.discussion_id },
				};
			}

			const result = await pi.exec("glab", ["mr", "note", "resolve", params.discussion_id], {
				cwd: ctx.cwd,
				signal,
				timeout: 15_000,
			});
			if (result.code !== 0) {
				throw commandError("glab mr note resolve", result.stderr, result.code);
			}
			return {
				content: [{ type: "text", text: `Resolved GitLab discussion ${params.discussion_id}.` }],
				details: { action: "resolve", discussionId: params.discussion_id },
			};
		},
	});
}
