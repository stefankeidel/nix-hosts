/**
 * Extensions Command
 *
 * Provides /extensions, which lists extensions loaded in the current Pi session.
 */

import type { ExtensionAPI, SourceInfo } from "@earendil-works/pi-coding-agent";

type Extension = {
	path: string;
	sourceInfo?: SourceInfo;
};

function commandLineExtensionPaths(): string[] {
	const paths: string[] = [];

	for (let index = 0; index < process.argv.length; index += 1) {
		const arg = process.argv[index];
		if (arg === "--extension" || arg === "-e") {
			const path = process.argv[index + 1];
			if (path) paths.push(path);
			index += 1;
		} else if (arg.startsWith("--extension=")) {
			paths.push(arg.slice("--extension=".length));
		}
	}

	return paths;
}

export default function extensionsExtension(pi: ExtensionAPI) {
	pi.registerCommand("extensions", {
		description: "List loaded extensions",
		handler: async (_args, ctx) => {
			const extensions = new Map<string, Extension>();

			for (const path of commandLineExtensionPaths()) {
				extensions.set(path, { path });
			}

			for (const command of pi.getCommands()) {
				if (command.source === "extension") {
					extensions.set(command.sourceInfo.path, {
						path: command.sourceInfo.path,
						sourceInfo: command.sourceInfo,
					});
				}
			}

			for (const tool of pi.getAllTools()) {
				// Built-in tools have synthetic source info, so only include extension tools.
				if (tool.sourceInfo.source !== "builtin") {
					extensions.set(tool.sourceInfo.path, {
						path: tool.sourceInfo.path,
						sourceInfo: tool.sourceInfo,
					});
				}
			}

			const loaded = [...extensions.values()].sort((a, b) => a.path.localeCompare(b.path));
			if (loaded.length === 0) {
				ctx.ui.notify("No extensions found", "info");
				return;
			}

			const items = loaded.map(({ path, sourceInfo }) =>
				sourceInfo ? `${path} (${sourceInfo.scope}, ${sourceInfo.source})` : path,
			);
			const selected = await ctx.ui.select("Loaded Extensions", items);
			if (selected) {
				ctx.ui.notify(selected.slice(0, selected.lastIndexOf(" (")), "info");
			}
		},
	});
}
