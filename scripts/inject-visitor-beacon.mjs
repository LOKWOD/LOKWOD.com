import { readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";

const workerBaseUrl = "https://lokwod-visitor-beacon.syracuseappraiser.workers.dev";
const unconfiguredPlaceholder = ["__", "WORKER_BASE_URL", "__"].join("");
const root = resolve(process.argv[2] || ".");
const siteId = String(process.argv[3] || "").trim().toLowerCase();
const skipDirectories = new Set([".git", "node_modules", ".wrangler"]);

if (!/^https:\/\//i.test(workerBaseUrl) || workerBaseUrl === unconfiguredPlaceholder) {
  throw new Error("The visitor beacon Worker URL has not been configured.");
}
if (!/^[a-z0-9-]{2,64}$/.test(siteId)) {
  throw new Error("A valid site ID is required as the second argument.");
}

const markerStart = "<!-- LOKWOD Website Visitor Beacon -->";
const markerEnd = "<!-- End LOKWOD Website Visitor Beacon -->";
const block = `${markerStart}<script defer src="${workerBaseUrl}/beacon.js" data-site="${siteId}"></script>${markerEnd}`;
const markedBlockPattern = /<!--\s*LOKWOD Website Visitor Beacon\s*-->[\s\S]*?<!--\s*End LOKWOD Website Visitor Beacon\s*-->/gi;
const standalonePattern = /<script\b(?=[^>]*\bdata-site=["'][^"']+["'])(?=[^>]*\bsrc=["']https:\/\/[^"']+\/beacon\.js["'])[^>]*>\s*<\/script>/gi;

let changed = 0;
let alreadyCorrect = 0;
let processed = 0;

function inject(path) {
  const original = readFileSync(path, "utf8");
  if (!/<\/body>/i.test(original)) {
    throw new Error(`Cannot install visitor beacon in ${relative(root, path)}: missing </body>.`);
  }

  const cleaned = original
    .replace(markedBlockPattern, "")
    .replace(standalonePattern, "")
    .replace(/\s+<\/body>/i, "</body>");
  const next = cleaned.replace(/<\/body>/i, `\n${block}\n</body>`);
  processed += 1;

  const endpointCount = (next.match(/\/beacon\.js/g) || []).length;
  const siteCount = (next.match(new RegExp(`data-site=["']${siteId}["']`, "g")) || []).length;
  if (endpointCount !== 1 || siteCount !== 1 || !next.includes(workerBaseUrl)) {
    throw new Error(`Visitor beacon verification failed for ${relative(root, path)}.`);
  }

  if (next === original) {
    alreadyCorrect += 1;
    return;
  }
  writeFileSync(path, next);
  changed += 1;
}

function walk(directory) {
  for (const name of readdirSync(directory)) {
    if (skipDirectories.has(name)) continue;
    const path = join(directory, name);
    const stat = statSync(path);
    if (stat.isDirectory()) walk(path);
    else if (name.toLowerCase().endsWith(".html")) inject(path);
  }
}

walk(root);
if (processed === 0) throw new Error(`No HTML files were found under ${root}.`);
console.log(`LOKWOD visitor beacon: processed ${processed}, updated ${changed}, already correct ${alreadyCorrect}.`);
