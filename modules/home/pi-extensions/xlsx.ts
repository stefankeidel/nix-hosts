import { randomUUID } from "node:crypto";
import { readFile, writeFile, link, rename, unlink } from "node:fs/promises";
import { basename, dirname, extname, resolve } from "node:path";
import ExcelJS from "exceljs";
import { Type } from "@earendil-works/pi-ai";
import { withFileMutationQueue, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

type Cell = string | number | boolean | null;
type Row = Cell[] | Record<string, Cell>;
type Sheets = Record<string, Row[]>;

function normalizeRows(rows: Row[]): Cell[][] {
  if (!Array.isArray(rows) || rows.length === 0) throw new Error("Each sheet needs at least one row");
  if (rows.every(row => Array.isArray(row))) return rows as Cell[][];
  if (rows.every(row => row !== null && typeof row === "object" && !Array.isArray(row))) {
    const columns = [...new Set(rows.flatMap(row => Object.keys(row)))];
    return [columns, ...rows.map(row => columns.map(key => (row as Record<string, Cell>)[key] ?? null))];
  }
  throw new Error("Rows must all be arrays or all be objects");
}

function parseDelimited(input: string, delimiter: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [], value = "", quoted = false, closed = false;
  for (let i = 0; i < input.length; i++) {
    const char = input[i];
    if (quoted) {
      if (char === '"' && input[i + 1] === '"') { value += '"'; i++; }
      else if (char === '"') { quoted = false; closed = true; }
      else value += char;
    } else if (char === '"' && !value && !closed) quoted = true;
    else if (char === delimiter || char === "\n" || char === "\r") {
      row.push(value); value = ""; closed = false;
      if (char !== delimiter) {
        rows.push(row); row = [];
        if (char === "\r" && input[i + 1] === "\n") i++;
      }
    } else if (closed || char === '"') throw new Error("Malformed quoted delimited field");
    else value += char;
  }
  if (quoted) throw new Error("Unclosed quoted delimited field");
  if (row.length || value || closed) rows.push([...row, value]);
  return rows;
}

function parseMarkdown(input: string): string[][] {
  const lines = input.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  const split = (line: string) => line.replace(/^\|/, "").replace(/(?<!\\)\|$/, "")
    .split(/(?<!\\)\|/).map(part => part.trim().replace(/\\\|/g, "|"));
  if (lines.length < 2) throw new Error("Markdown table needs a header and separator");
  const header = split(lines[0]), separator = split(lines[1]);
  if (header.length !== separator.length || !separator.every(cell => /^:?-{3,}:?$/.test(cell))) {
    throw new Error("Invalid Markdown table separator");
  }
  return [header, ...lines.slice(2).map(split)];
}

async function loadSheets(path: string): Promise<Sheets> {
  const kind = extname(path).toLowerCase();
  const text = (await readFile(path, "utf8")).replace(/^\uFEFF/, "");
  if (kind === ".json") {
    const data: unknown = JSON.parse(text);
    if (data && typeof data === "object" && !Array.isArray(data) && "sheets" in data) {
      return (data as { sheets: Sheets }).sheets;
    }
    return { [sheetName(basename(path, kind))]: data as Row[] };
  }
  const name = sheetName(basename(path, kind));
  if (kind === ".csv" || kind === ".tsv") return { [name]: parseDelimited(text, kind === ".csv" ? "," : "\t") };
  if (kind === ".md") return { [name]: parseMarkdown(text) };
  throw new Error("Source must be .csv, .tsv, .md, or .json");
}

function sheetName(name: string): string {
  return name.replace(/[\\/*?:\[\]]/g, "_").replace(/^'+|'+$/g, "").slice(0, 31) || "Sheet1";
}

export async function workbook(sheets: Sheets): Promise<Buffer> {
  if (!sheets || typeof sheets !== "object" || Array.isArray(sheets)) throw new Error("sheets must be a named object");
  const entries = Object.entries(sheets);
  if (!entries.length || entries.length > 255) throw new Error("Provide 1–255 sheets");
  const names = new Set<string>();
  const book = new ExcelJS.Workbook();
  for (const [name, inputRows] of entries) {
    if (!name || name.length > 31 || /[\\/*?:\[\]]/.test(name) || /^'|'$/.test(name) || names.has(name.toLowerCase())) {
      throw new Error(`Invalid or duplicate Excel sheet name: ${name}`);
    }
    names.add(name.toLowerCase());
    const rows = normalizeRows(inputRows);
    if (!rows[0]?.length || rows[0].length > 16384 || rows.length > 1048576 || rows.some(row => row.length !== rows[0].length)) {
      throw new Error(`Inconsistent rows or Excel sheet size exceeded: ${name}`);
    }
    const sheet = book.addWorksheet(name, { views: [{ state: "frozen", ySplit: 1 }] });
    const widths = Array.from({ length: rows[0].length }, () => 0);
    for (const row of rows) {
      const cells = row.map((value, index) => {
        if (value !== null && value !== undefined && typeof value !== "string" && typeof value !== "number" && typeof value !== "boolean") {
          throw new Error(`Unsupported cell value in ${name}`);
        }
        if (typeof value === "number" && !Number.isFinite(value)) throw new Error(`Non-finite number in ${name}`);
        if (typeof value === "string" && value.length > 32767) throw new Error(`Cell exceeds Excel's text limit in ${name}`);
        widths[index] = Math.max(widths[index], String(value ?? "").length);
        // Plain strings are ExcelJS text cells; formulas require an explicit { formula } object.
        return value;
      });
      sheet.addRow(cells);
    }
    sheet.columns.forEach((column, index) => { column.width = Math.min(Math.max(widths[index] + 2, 12), 60); });
    sheet.getRow(1).eachCell(cell => {
      cell.font = { bold: true, color: { argb: "FFFFFFFF" } };
      cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF24476B" } };
    });
    sheet.autoFilter = { from: "A1", to: sheet.getRow(rows.length).getCell(rows[0].length).address };
  }
  return Buffer.from(await book.xlsx.writeBuffer());
}

export default function xlsxExtension(pi: ExtensionAPI) {
  pi.registerTool({
    name: "write_xlsx",
    label: "Write Excel workbook",
    description: "Write a local .xlsx Excel workbook from inline named tables or a CSV, TSV, Markdown table, or JSON file. JSON accepts an array of objects/rows or {sheets:{name:rows}}. Never uploads data; text is written as literal strings, not formulas. Existing files are preserved unless overwrite is true.",
    exposure: "codemode",
    annotations: { destructiveHint: true, openWorldHint: false, readOnlyHint: false },
    parameters: Type.Object({
      output: Type.String({ description: "Destination .xlsx path, relative to working directory or absolute" }),
      source: Type.Optional(Type.String({ description: "Existing local .csv, .tsv, .md, or .json path; use instead of sheets" })),
      sheets: Type.Optional(Type.Record(Type.String(), Type.Array(Type.Any()), { description: "Named tables: each is an array of objects or arrays (first array is header)" })),
      overwrite: Type.Optional(Type.Boolean({ description: "Replace an existing workbook (default false)" })),
    }),
    async execute(_id, { output, source, sheets, overwrite }: { output: string; source?: string; sheets?: Sheets; overwrite?: boolean }, signal, _update, ctx) {
      if (!!source === !!sheets) throw new Error("Provide exactly one of source or sheets");
      const destination = resolve(ctx.cwd, output);
      if (extname(destination).toLowerCase() !== ".xlsx") throw new Error("Output must end in .xlsx");
      const data = source ? await loadSheets(resolve(ctx.cwd, source)) : sheets!;
      const buffer = await workbook(data);
      return withFileMutationQueue(destination, async () => {
        if (signal?.aborted) throw new Error("Operation aborted");
        const temporary = resolve(dirname(destination), `.${basename(destination)}.${randomUUID()}.tmp`);
        try {
          await writeFile(temporary, buffer, { flag: "wx", mode: 0o600 });
          if (signal?.aborted) throw new Error("Operation aborted");
          if (overwrite) await rename(temporary, destination);
          else await link(temporary, destination); // Atomic no-clobber, even across Pi sessions.
        } finally {
          await unlink(temporary).catch(error => {
            if (error.code !== "ENOENT") throw error;
          });
        }
        return { content: [{ type: "text" as const, text: `Wrote ${destination} (${Object.keys(data).length} sheet(s))` }], details: { path: destination, sheets: Object.keys(data) } };
      });
    },
  });
}
