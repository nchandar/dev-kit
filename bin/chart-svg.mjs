// Render a Mermaid file with pele. Called by bin/chart-svg; see library/deep/model-check.md.
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [src, out, tools] = process.argv.slice(2);

let render, PeleError;
try {
  const pkg = JSON.parse(await readFile(join(tools, "node_modules/pele/package.json"), "utf8"));
  const entry = (pkg.exports && pkg.exports["."] && (pkg.exports["."].import || pkg.exports["."].default)) || pkg.module || pkg.main;
  ({ render, PeleError } = await import(pathToFileURL(join(tools, "node_modules/pele", entry)).href));
} catch {
  console.error("chart-svg: cannot load pele; run bin/setup --apply");
  process.exit(1);
}

let source;
try {
  source = await readFile(src, "utf8");
} catch {
  console.error(`chart-svg: cannot read ${src}`);
  process.exit(1);
}

try {
  await Bun.write(out, render(source).svg);
} catch (error) {
  // Pele messages can carry diagram text, so print them as plain text, never as markup.
  if (error instanceof PeleError) console.error(error.message);
  else console.error(`chart-svg: ${error && error.message ? error.message : error}`);
  process.exit(1);
}
