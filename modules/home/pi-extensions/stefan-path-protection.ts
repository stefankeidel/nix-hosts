/**
 * Stefan's filesystem boundary for Pi tool calls.
 *
 * Paths are canonicalised before checking so `..` and existing symlinks cannot
 * escape an allowed root. This intentionally protects only agent tool calls;
 * it is not an OS sandbox for arbitrary programs.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { lstat, realpath } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { dirname, relative, resolve, sep } from "node:path";

type Access = "read" | "write";

type AccessRequest = {
	access: Access;
	reason?: string;
	target: string;
};

type SessionPermission = {
	access: Access;
	target: string;
};

const home = homedir();
const codeRoot = resolve(home, "code");
const piRoot = resolve(home, ".pi");
const agentsRoot = resolve(home, ".agents");
const nixStore = "/nix/store";
const temporaryRoots = [...new Set([tmpdir(), "/tmp", "/var/tmp"])].map((path) => resolve(path));

function isWithin(path: string, root: string): boolean {
	const pathRelative = relative(root, path);
	return pathRelative === "" || (!pathRelative.startsWith(`..${sep}`) && pathRelative !== "..");
}

async function canonicalPath(path: string, cwd: string): Promise<string> {
	const absolute = resolve(cwd, path.replace(/^@/, ""));
	let candidate = absolute;
	const missingParts: string[] = [];

	// realpath() also resolves symlinks. For a new target, resolve its nearest
	// existing ancestor and append the missing components afterwards.
	while (true) {
		try {
			await lstat(candidate);
			return resolve(await realpath(candidate), ...missingParts.reverse());
		} catch (error: unknown) {
			if (!(error instanceof Error) || !("code" in error) || error.code !== "ENOENT") throw error;
			const parent = dirname(candidate);
			if (parent === candidate) return absolute;
			missingParts.push(candidate.slice(parent.length + (parent.endsWith(sep) ? 0 : 1)));
			candidate = parent;
		}
	}
}

function projectHasProtectedComponent(path: string, projectRoot: string): boolean {
	if (!isWithin(path, projectRoot)) return false;
	return relative(projectRoot, path).split(sep).some((part) => part === "node_modules" || part === ".venv");
}

async function accessRequest(path: string, access: Access, cwd: string): Promise<AccessRequest> {
	const target = await canonicalPath(path, cwd);
	const projectRoot = await canonicalPath(cwd, cwd);

	if (access === "write") {
		if (projectHasProtectedComponent(target, projectRoot)) {
			return {
				target,
				reason: `Direct write to protected dependency environment: ${path}. Use its package manager instead.`,
			};
		}
		if (isWithin(target, projectRoot) || isWithin(target, piRoot) || temporaryRoots.some((root) => isWithin(target, root))) {
			return { target };
		}
		return {
			target,
			reason: `Write outside the current project, ~/.pi, or a temporary directory: ${path}`,
		};
	}

	if (isWithin(target, codeRoot) || isWithin(target, nixStore) || isWithin(target, piRoot) || isWithin(target, agentsRoot) || temporaryRoots.some((root) => isWithin(target, root))) {
		return { target };
	}
	return {
		target,
		reason: `Read outside ~/code, /nix/store, ~/.pi, ~/.agents, or a temporary directory: ${path}`,
	};
}

function bashIsClearlyUnsafe(command: string): boolean {
	// Only reject syntax that can dynamically hide a path. Dollar signs and
	// backticks inside single quotes are literals (common in awk and Nix), while
	// static redirections are checked separately below.
	let quote: "single" | "double" | undefined;
	for (let index = 0; index < command.length; index += 1) {
		const character = command[index];
		if (character === "\\" && quote !== "single") {
			index += 1;
			continue;
		}
		if (character === "'" && quote !== "double") {
			quote = quote === "single" ? undefined : "single";
			continue;
		}
		if (character === '"' && quote !== "single") {
			quote = quote === "double" ? undefined : "double";
			continue;
		}
		if (quote !== "single" && (character === "$" || character === "`")) return true;
		if (quote === undefined && (character === "<" || character === ">") && command[index + 1] === "(") return true;
	}
	return false;
}

function bashRedirectionPaths(command: string): { read: string[]; write: string[] } {
	const paths = { read: [] as string[], write: [] as string[] };
	const redirection = /\d*(<<-?|<<<|>>?|<)\s*("[^"]*"|'[^']*'|[^\s;|&<>]+)/g;

	for (const match of command.matchAll(redirection)) {
		const operator = match[1];
		const rawTarget = match[2];
		if (!operator || !rawTarget || operator.startsWith("<<") || /^&\d+$/.test(rawTarget)) continue;
		const target = rawTarget.replace(/^(?:"([\s\S]*)"|'([\s\S]*)')$/, "$1$2");
		paths[operator === "<" ? "read" : "write"].push(target);
	}
	return paths;
}

function bashPaths(command: string): string[] {
	// This is deliberately conservative: tokens that look like paths are
	// checked; shell syntax itself is rejected above.
	return command
		.trim()
		.split(/\s+/)
		.filter(
			(word) =>
				word === "." ||
				word === ".." ||
				word.startsWith("/") ||
				word.startsWith("~/") ||
				word.startsWith("./") ||
				word.startsWith("../") ||
				word.includes("/"),
		)
		.map((word) => (word.startsWith("~/") ? resolve(home, word.slice(2)) : word));
}

export default function stefanPathProtection(pi: ExtensionAPI) {
	const sessionPermissions: SessionPermission[] = [];

	let allowAllForSession = false;

	function hasSessionPermission(request: AccessRequest): boolean {
		return allowAllForSession || sessionPermissions.some(
			(permission) =>
				isWithin(request.target, permission.target) &&
				(permission.access === request.access || permission.access === "write"),
		);
	}

	pi.on("tool_call", async (event, ctx) => {
		const requestPermission = async (path: string, access: Access): Promise<string | undefined> => {
			const request = await accessRequest(path, access, ctx.cwd);
			if (!request.reason || hasSessionPermission(request)) return undefined;

			if (!ctx.hasUI) return `Blocked ${request.reason} (no UI available to request permission)`;

			const choice = await ctx.ui.select(
				`Filesystem permission requested\n\n${access.toUpperCase()}: ${request.target}\n\n${request.reason}`,
				[
					"Yes for this call",
					"Allow this path and everything under it for this session",
					"Allow all paths for this session",
					"No",
				],
			);
			if (choice === "Yes for this call") return undefined;
			if (choice === "Allow this path and everything under it for this session") {
				sessionPermissions.push({ access, target: request.target });
				return undefined;
			}
			if (choice === "Allow all paths for this session") {
				allowAllForSession = true;
				return undefined;
			}
			return `Blocked by user: ${request.reason}`;
		};

		const notifyAndBlock = (reason: string) => {
			if (ctx.hasUI) ctx.ui.notify(reason, "warning");
			return { block: true, reason };
		};

		if (event.toolName === "write" || event.toolName === "edit") {
			const reason = await requestPermission(String(event.input.path ?? ""), "write");
			return reason ? notifyAndBlock(reason) : undefined;
		}

		if (["read", "grep", "find", "ls"].includes(event.toolName)) {
			const reason = await requestPermission(String(event.input.path ?? "."), "read");
			return reason ? notifyAndBlock(reason) : undefined;
		}

		if (event.toolName === "bash") {
			const command = String(event.input.command ?? "").trim();
			if (!command || bashIsClearlyUnsafe(command)) {
				return notifyAndBlock("Blocked bash command: avoid evaluated variable, command, or process expansion so paths can be checked.");
			}

			const words = command.split(/\s+/);
			const mutatesPaths = /(?:^|(?:&&|\|\||[;|])\s*)(?:rm|mv|cp|mkdir|touch|chmod|chown|ln|install)(?:\s|$)/.test(command);
			const paths = new Set(bashPaths(command));
			const redirectedPaths = bashRedirectionPaths(command);
			if (mutatesPaths) {
				// Treat every non-option operand of a mutating command as a target.
				// This catches simple relative names such as `rm -rf node_modules`.
				for (const operand of words.slice(1)) {
					if (operand && !operand.startsWith("-")) paths.add(operand);
				}
			}

			for (const path of new Set([...paths, ...redirectedPaths.read])) {
				if (path === "/dev/null") continue;
				const reason = await requestPermission(path, mutatesPaths ? "write" : "read");
				if (reason) return notifyAndBlock(reason);
			}
			for (const path of new Set(redirectedPaths.write)) {
				if (path === "/dev/null") continue;
				const reason = await requestPermission(path, "write");
				if (reason) return notifyAndBlock(reason);
			}
		}

		return undefined;
	});
}
