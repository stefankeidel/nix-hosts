import { fileURLToPath } from "node:url";

export type Request = { operation: string; [key: string]: unknown };
export type Exec = (command: string, args: string[], options: {
  signal?: AbortSignal; timeout: number; maxBuffer: number;
}) => Promise<{ code: number; stdout: string; stderr: string; killed?: boolean; truncated?: boolean }>;

function lispString(value: string): string {
  return `"${value.replaceAll("\\", "\\\\").replaceAll('"', '\\"').replaceAll("\n", "\\n")}"`;
}

export async function request(exec: Exec, input: Request, signal?: AbortSignal): Promise<Record<string, unknown>> {
  signal?.throwIfAborted();
  const payload = Buffer.from(JSON.stringify(input), "utf8").toString("base64");
  const bridge = fileURLToPath(new URL("./bridge.el", import.meta.url));
  const expression = `(progn (load ${lispString(bridge)} nil t) (pi-vulpea-dispatch-json "${payload}"))`;
  const args = ["--alternate-editor=false", "--quiet"];
  if (process.env.PI_VULPEA_SOCKET) args.push("--socket-name", process.env.PI_VULPEA_SOCKET);
  args.push("--eval", expression);
  const result = await exec(process.env.PI_VULPEA_EMACSCLIENT || "emacsclient", args, {
    signal, timeout: 20_000, maxBuffer: 256 * 1024,
  });
  if (result.code !== 0 || result.killed || result.truncated) {
    throw new Error("Vulpea Emacs request failed or timed out. Check the running Emacs server. A timed-out write may have completed; read the target before retrying.");
  }
  let response: { ok: boolean; data?: Record<string, unknown>; error?: string };
  try {
    const encoded: unknown = JSON.parse(result.stdout.trim());
    if (typeof encoded !== "string" || !/^[A-Za-z0-9+/=]+$/.test(encoded)) throw new Error("Invalid envelope");
    response = JSON.parse(Buffer.from(encoded, "base64").toString("utf8"));
  } catch {
    throw new Error("Invalid response from the Vulpea Emacs bridge; no automatic write retry.");
  }
  if (!response.ok || !response.data) throw new Error(response.error || "Vulpea request failed");
  if (Buffer.byteLength(JSON.stringify(response.data), "utf8") > 50_000) {
    throw new Error("Vulpea response exceeds 50KB; read/list with a smaller limit. If this followed a write, read the target before retrying the write.");
  }
  return response.data;
}
