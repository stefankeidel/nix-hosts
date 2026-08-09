/**
 * Permission Gate Extension
 *
 * Prompts for confirmation before running potentially dangerous bash commands.
 * Based on the upstream example:
 * https://github.com/earendil-works/pi/blob/main/packages/coding-agent/examples/extensions/permission-gate.ts
 *
 * Patterns checked: rm -rf, sudo, chmod/chown 777, disk/dd operations,
 * force-pushes, and destructive git resets.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	const dangerousPatterns = [
		/\brm\s+(-[a-z]*r[a-z]*f?|-[a-z]*f[a-z]*r|--recursive)/i,
		/\bsudo\b/i,
		/\b(chmod|chown)\b.*777/i,
		/\bdd\s+if=/i,
		/\bmkfs(\.\w+)?\b/i,
		/\bgit\s+push\b.*(--force|-f\b)/i,
		/\bgit\s+reset\s+--hard\b/i,
		/\bgit\s+clean\b.*-[a-z]*d[a-z]*f/i,
	];

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;

		const command = event.input.command as string;
		const isDangerous = dangerousPatterns.some((p) => p.test(command));

		if (isDangerous) {
			if (!ctx.hasUI) {
				// In non-interactive mode, block by default
				return { block: true, reason: "Dangerous command blocked (no UI for confirmation)" };
			}

			const choice = await ctx.ui.select(`⚠️ Dangerous command:\n\n  ${command}\n\nAllow?`, ["Yes", "No"]);

			if (choice !== "Yes") {
				return { block: true, reason: "Blocked by user" };
			}
		}

		return undefined;
	});
}
