import { Type } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const KEV_URL = "http://127.0.0.1:8009";
const STATUS_KEY = "kev";
const RETRY_MS = 1_000;
const HEALTHY_POLL_MS = 5_000;

const questionSchema = Type.Object({
  type: Type.Union([Type.Literal("noul"), Type.Literal("choice"), Type.Literal("score")]),
  instructions: Type.Optional(Type.Any({ description: "The decision or judgment Kev should make" })),
  criteria: Type.Optional(Type.Any({ description: "Choice map, ordered score levels, or optional true/false descriptions" })),
});

type KevQuestion = {
  type: "noul" | "choice" | "score";
  instructions?: unknown;
  criteria?: unknown;
};

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function getModels(signal?: AbortSignal): Promise<Record<string, unknown>> {
  const response = await fetch(`${KEV_URL}/v1/models`, { signal });
  if (!response.ok) throw new Error(`Kev returned HTTP ${response.status}`);
  return await response.json() as Record<string, unknown>;
}

async function isReady(): Promise<boolean> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 750);
  try {
    await getModels(controller.signal);
    return true;
  } catch {
    return false;
  } finally {
    clearTimeout(timeout);
  }
}

export default function kevExtension(pi: ExtensionAPI) {
  let monitorGeneration = 0;

  function setStatus(ctx: ExtensionContext, ready: boolean): void {
    ctx.ui.setStatus(
      STATUS_KEY,
      ready
        ? ctx.ui.theme.fg("success", "● Kev")
        : ctx.ui.theme.fg("warning", "● Kev starting…"),
    );
  }

  async function monitor(ctx: ExtensionContext, generation: number): Promise<void> {
    while (generation === monitorGeneration) {
      const ready = await isReady();
      if (generation !== monitorGeneration) return;
      setStatus(ctx, ready);
      await sleep(ready ? HEALTHY_POLL_MS : RETRY_MS);
    }
  }

  async function waitUntilReady(signal?: AbortSignal): Promise<void> {
    while (true) {
      if (signal?.aborted) throw new Error("Kev request aborted while waiting for the server");
      if (await isReady()) return;
      await sleep(RETRY_MS);
    }
  }

  pi.on("session_start", (_event, ctx) => {
    const generation = ++monitorGeneration;
    void monitor(ctx, generation);
  });

  pi.on("session_shutdown", (_event, ctx) => {
    monitorGeneration++;
    ctx.ui.setStatus(STATUS_KEY, undefined);
  });

  pi.registerCommand("kev", {
    description: "Show the central Kev server status and model details",
    handler: async (_args, ctx) => {
      try {
        ctx.ui.notify(JSON.stringify(await getModels(), null, 2), "info");
      } catch {
        ctx.ui.notify(
          "Kev is not ready. launchd will keep trying; see ~/Library/Logs/kev.error.log.",
          "warning",
        );
      }
    },
  });

  pi.registerTool({
    name: "kev_status",
    label: "Kev status",
    description: "Check the central Kev decision server and return details about its loaded model, backend, precision, and prefix cache.",
    parameters: Type.Object({}),
    async execute(_toolCallId, _params, signal) {
      try {
        const result = await getModels(signal);
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
          details: result,
        };
      } catch (error) {
        throw new Error(
          `Kev is unavailable; launchd logs are in ~/Library/Logs/kev.error.log: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
    },
  });

  pi.registerTool({
    name: "ask_kev",
    label: "Ask Kev",
    description: "Ask the local Kev decision model one or more independent yes/no (noul), multiple-choice, or ordinal score questions about shared input. Use criteria as an option-to-description object for choice or an ordered array for score.",
    parameters: Type.Object({
      state: Type.Any({ description: "Text, object, or array containing the evidence Kev should evaluate" }),
      questions: Type.Record(Type.String(), questionSchema, {
        description: "Questions keyed by a short result ID",
      }),
    }),
    async execute(
      _toolCallId,
      input: { state: unknown; questions: Record<string, KevQuestion> },
      signal,
    ) {
      await waitUntilReady(signal);
      const response = await fetch(`${KEV_URL}/v1/systemone`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ state: input.state, model: "kev-latest", questions: input.questions }),
        signal,
      });
      const text = await response.text();
      if (!response.ok) throw new Error(`Kev returned HTTP ${response.status}: ${text}`);
      const result = JSON.parse(text) as Record<string, unknown>;
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        details: result,
      };
    },
  });
}
