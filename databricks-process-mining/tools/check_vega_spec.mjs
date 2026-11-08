// Prüft process_graph.vl.json gegen die Graph-Daten aus tools/local_sql_check.py (build/graph_*.json).
// Kompiliert mit Vega-Lite, rendert als SVG nach build/, Exit-Code 1 bei Warnungen oder Fehlern.
//   cd tools && npm install && node check_vega_spec.mjs
// Für Vega-Lite 5 zusätzlich:  npm install vega@5 vega-lite@5 && node check_vega_spec.mjs
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import * as vega from "vega";
import * as vl0 from "vega-lite";

const vl = vl0.compile ? vl0 : vl0.default;
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const build = path.join(root, "build");
const files = fs.readdirSync(build).filter(f => /^graph_.*\.json$/.test(f));
if (!files.length) { console.error("Keine build/graph_*.json – zuerst python tools/local_sql_check.py ausführen."); process.exit(2); }

let problems = 0;
for (const f of files) {
  const spec = JSON.parse(fs.readFileSync(path.join(root, "process_graph.vl.json"), "utf8"));
  const rows = JSON.parse(fs.readFileSync(path.join(build, f), "utf8"));
  const fy = Math.max(...rows.filter(r => r.row_type === "frame").map(r => r.y));
  spec.data = { values: rows };                 // in Databricks: {"name": "databricks_query"}
  spec.width = 640; spec.height = Math.round(640 * fy / 800);
  const warns = [];
  const logger = { level() { return this; }, warn: (...a) => warns.push(a.join(" ")), info() {}, debug() {},
                   error: (...a) => warns.push("ERROR " + a.join(" ")) };
  const view = new vega.View(vega.parse(vl.compile(spec, { logger }).spec), { renderer: "none", logger });
  const svg = await view.toSVG();
  fs.writeFileSync(path.join(build, f.replace(".json", ".svg")), svg);
  console.log(`${warns.length ? "ERR" : "OK "} ${f}  (Vega-Lite ${vl.version})${warns.length ? "\n    " + warns.join("\n    ") : ""}`);
  problems += warns.length;
}
process.exit(problems ? 1 : 0);
