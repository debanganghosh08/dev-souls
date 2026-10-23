#!/usr/bin/env node
// Dev Souls CC0 asset downloader and licence audit trail (W3-01).
// Zero npm packages: built-in fetch, node:fs, node:path, node:crypto (+ node:child_process for the CPU check).
//
//   node tools/fetch-assets.mjs --dry-run                 resolve + licence-check everything, write nothing
//   node tools/fetch-assets.mjs --only id,id              fetch a subset
//   node tools/fetch-assets.mjs --category terrain        fetch one category
//   node tools/fetch-assets.mjs --credits                 regenerate CREDITS.md from tools/assets-manifest.json
//   flags: --max-bytes <n>  --force  --keep-raw  --include-optional  --manifest <path>

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DEFAULT_MANIFEST = path.join(ROOT, "tools", "assets.json");
const AUDIT_PATH = path.join(ROOT, "tools", "assets-manifest.json");
const CREDITS_PATH = path.join(ROOT, "CREDITS.md");
const CACHE_DIR = path.join(ROOT, ".cache", "dl");

const USER_AGENT = "dev-souls-assets/1.0 (personal project)";
const DEFAULT_MAX_BYTES = 2 * 1024 ** 3;
const MAX_CONCURRENT_FILES = 3;
const MAX_RETRIES = 3;
const CPU_LOAD_LIMIT_PERCENT = 50;

const POLYHAVEN_API = "https://api.polyhaven.com";
const POLYHAVEN_PAGE = "https://polyhaven.com/a/";
const POLYPIZZA_PAGE = "https://poly.pizza/m/";
const CC0_URL = "https://creativecommons.org/publicdomain/zero/1.0/";

// Manifest map key -> Poly Haven /files map name.
const POLYHAVEN_MAPS = { diffuse: "Diffuse", nor_gl: "nor_gl", rough: "Rough", ao: "AO", disp: "Displacement" };
const POLYHAVEN_TYPES = { texture: 1, model: 2 };

class LicenceRejected extends Error {}

// ---------- small helpers ----------

function fmtBytes(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1024 ** 2) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 ** 3) return `${(n / 1024 ** 2).toFixed(1)} MB`;
  return `${(n / 1024 ** 3).toFixed(2)} GB`;
}

function die(message) {
  console.error(`error: ${message}`);
  process.exit(2);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function insideRoot(p) {
  const rel = path.relative(ROOT, p);
  return rel !== "" && !rel.startsWith("..") && !path.isAbsolute(rel);
}

// Licence gate. Only an unambiguous CC0 / public-domain statement passes; anything else
// (CC-BY, "free", empty, missing) is rejected, because a wrong answer here is a legal problem
// for a shipped game, not a cosmetic one.
function isCc0(text) {
  if (typeof text !== "string") return false;
  const t = text.trim().toLowerCase();
  if (t === CC0_URL) return true;
  if (/\bby\b|cc-by|attribution required/.test(t.replace("no attribution required", ""))) return false;
  return /^(cc0\b|public domain\b)/.test(t);
}

// ---------- CLI ----------

function parseArgs(argv) {
  const opts = {
    only: null, category: null, dryRun: false, force: false, keepRaw: false, credits: false,
    includeOptional: false, maxBytes: DEFAULT_MAX_BYTES, manifest: DEFAULT_MANIFEST,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const value = () => {
      i += 1;
      if (i >= argv.length) die(`${arg} needs a value`);
      return argv[i];
    };
    if (arg === "--only") opts.only = value().split(",").map((s) => s.trim()).filter(Boolean);
    else if (arg === "--category") opts.category = value();
    else if (arg === "--dry-run") opts.dryRun = true;
    else if (arg === "--force") opts.force = true;
    else if (arg === "--keep-raw") opts.keepRaw = true;
    else if (arg === "--credits") opts.credits = true;
    else if (arg === "--include-optional") opts.includeOptional = true;
    else if (arg === "--max-bytes") {
      opts.maxBytes = Number(value());
      if (!Number.isInteger(opts.maxBytes) || opts.maxBytes <= 0) die("--max-bytes must be a positive integer number of bytes");
    } else if (arg === "--manifest") opts.manifest = path.resolve(value());
    else die(`unknown argument ${arg}. See the usage block at the top of tools/fetch-assets.mjs`);
  }
  return opts;
}

function loadManifest(file) {
  let data;
  try {
    data = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (err) {
    die(`cannot read manifest ${file}: ${err.message}. Fix the JSON or pass --manifest <path>.`);
  }
  if (!Array.isArray(data.assets)) die(`manifest ${file} has no "assets" array`);
  for (const a of data.assets) {
    if (!a.id || !a.source || !a.type || !a.dest) die(`manifest entry ${JSON.stringify(a)} is missing id/source/type/dest`);
    if (!insideRoot(path.resolve(ROOT, a.dest))) die(`manifest entry ${a.id}: dest "${a.dest}" points outside the project`);
  }
  return data.assets;
}

function selectAssets(assets, opts) {
  let selected = assets;
  if (opts.only) {
    const known = new Set(assets.map((a) => a.id));
    const unknown = opts.only.filter((id) => !known.has(id));
    if (unknown.length) die(`--only ids not in the manifest: ${unknown.join(", ")}. Add them to tools/assets.json first.`);
    selected = assets.filter((a) => opts.only.includes(a.id));
  }
  if (opts.category) selected = selected.filter((a) => a.category === opts.category);
  if (selected.length === 0) die("no assets match the filters (check --only / --category)");
  return selected;
}

// ---------- laptop safety ----------

function checkCpuLoad() {
  if (process.platform !== "win32") {
    console.log("CPU check skipped (not Windows)");
    return;
  }
  let load = NaN;
  try {
    const out = execFileSync("powershell.exe", [
      "-NoProfile", "-NonInteractive", "-Command",
      "(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average",
    ], { encoding: "utf8", timeout: 30000 });
    load = Number.parseFloat(out.trim());
  } catch (err) {
    die(`could not read CPU load (${err.message}). Retry when the machine is idle; if PowerShell is unavailable, fix that first.`);
  }
  if (!Number.isFinite(load)) die("CPU load query returned no number. Retry in a few seconds.");
  if (load >= CPU_LOAD_LIMIT_PERCENT) {
    die(`CPU load is ${load}% (limit ${CPU_LOAD_LIMIT_PERCENT}%). Close Godot, the game and heavy browser tabs, then retry.`);
  }
  console.log(`CPU load ${load}% - under ${CPU_LOAD_LIMIT_PERCENT}%, continuing`);
}

// ---------- HTTP ----------

async function fetchWithRetry(url, init = {}) {
  let lastErr;
  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      const res = await fetch(url, { ...init, headers: { "User-Agent": USER_AGENT, ...(init.headers || {}) } });
      if (res.ok) return res;
      const err = new Error(`HTTP ${res.status} for ${url}`);
      if (res.status >= 400 && res.status < 500) throw err; // not transient: do not hammer the server
      lastErr = err;
    } catch (err) {
      if (/^HTTP 4\d\d/.test(err.message)) throw err;
      lastErr = err;
    }
    if (attempt < MAX_RETRIES) await sleep(1000 * 2 ** (attempt - 1));
  }
  throw lastErr;
}

// A 404 from either source means the id in tools/assets.json is wrong; say so instead of printing a bare status.
async function fetchOrExplain(url, what) {
  try {
    return await fetchWithRetry(url);
  } catch (err) {
    if (err.message.startsWith("HTTP 404")) throw new Error(`${what} not found (HTTP 404 at ${url}). Check the id in tools/assets.json against the source site.`);
    throw err;
  }
}

async function fetchJson(url, what = "asset") {
  const res = await fetchOrExplain(url, what);
  return res.json();
}

async function fetchText(url, what = "page") {
  const res = await fetchOrExplain(url, what);
  return res.text();
}

// ---------- resolvers: turn a manifest entry into a verified download plan ----------

// Poly Haven's API has no licence field, so the per-asset page's schema.org JSON-LD
// (license URL + copyrightNotice) is the source's own licence statement. Both must say CC0.
async function readPolyhavenLicence(id) {
  const html = await fetchText(POLYHAVEN_PAGE + id);
  const match = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/);
  if (!match) throw new LicenceRejected("asset page has no JSON-LD licence block");
  const graph = JSON.parse(match[1])["@graph"] || [];
  const node = graph.find((n) => typeof n["@id"] === "string" && n["@id"].endsWith("#asset"));
  if (!node) throw new LicenceRejected("asset page JSON-LD has no #asset node");
  const licence = `${node.copyrightNotice || "(no copyrightNotice)"} <${node.license || "no licence URL"}>`;
  if (node.license !== CC0_URL || !isCc0(node.copyrightNotice)) throw new LicenceRejected(licence);
  return licence;
}

function pickTextureFile(files, mapKey, resolution) {
  const entry = files[POLYHAVEN_MAPS[mapKey]]?.[resolution];
  if (!entry) return null;
  const fmt = entry.jpg ? entry.jpg : entry.png;
  if (!fmt) return null;
  return { url: fmt.url, size: fmt.size, md5: fmt.md5, rel: path.posix.basename(new URL(fmt.url).pathname) };
}

function planPolyhavenTexture(asset, files) {
  const plan = [];
  const warnings = [];
  for (const mapKey of asset.maps || Object.keys(POLYHAVEN_MAPS)) {
    if (!POLYHAVEN_MAPS[mapKey]) throw new Error(`unknown map "${mapKey}" in manifest (valid: ${Object.keys(POLYHAVEN_MAPS).join(", ")})`);
    const file = pickTextureFile(files, mapKey, asset.resolution);
    if (file) plan.push(file);
    else warnings.push(`no ${mapKey} map at ${asset.resolution}`);
  }
  if (plan.length === 0) throw new Error(`no texture maps found at ${asset.resolution}`);
  return { files: plan, warnings };
}

function planPolyhavenModel(asset, files) {
  const entry = files.gltf?.[asset.resolution]?.gltf;
  if (!entry) throw new Error(`no glTF at ${asset.resolution} (available: ${Object.keys(files.gltf || {}).join(", ") || "none"})`);
  const plan = [{ url: entry.url, size: entry.size, md5: entry.md5, rel: path.posix.basename(new URL(entry.url).pathname) }];
  for (const [rel, f] of Object.entries(entry.include || {})) {
    if (rel.includes("..") || path.posix.isAbsolute(rel)) throw new Error(`refusing include path "${rel}"`);
    plan.push({ url: f.url, size: f.size, md5: f.md5, rel });
  }
  return { files: plan, warnings: [] };
}

async function resolvePolyhaven(asset) {
  const info = await fetchJson(`${POLYHAVEN_API}/info/${asset.id}`, `Poly Haven asset "${asset.id}"`);
  if (info.error || !info.name) throw new Error(`Poly Haven has no asset "${asset.id}" (${info.error || "empty info"}). Check the id on polyhaven.com.`);
  if (info.type !== POLYHAVEN_TYPES[asset.type]) throw new Error(`Poly Haven says type ${info.type}, manifest says ${asset.type}`);
  const authors = Object.keys(info.authors || {});
  if (authors.length === 0) throw new LicenceRejected("info has no authors field; cannot attribute");
  const licence = await readPolyhavenLicence(asset.id);
  const files = await fetchJson(`${POLYHAVEN_API}/files/${asset.id}`);
  const planned = asset.type === "texture" ? planPolyhavenTexture(asset, files) : planPolyhavenModel(asset, files);
  return {
    name: info.name, author: authors.join(", "), sourceUrl: POLYHAVEN_PAGE + asset.id, licence,
    destDir: path.resolve(ROOT, asset.dest), ...planned,
  };
}

function extractField(html, pattern, what) {
  const m = html.match(pattern);
  if (!m) throw new Error(`Poly Pizza page has no ${what}; the page layout may have changed - open the URL in a browser and update the regex in resolvePolypizza`);
  return m[1];
}

async function resolvePolypizza(asset) {
  const html = await fetchText(POLYPIZZA_PAGE + asset.id, `Poly Pizza model "${asset.id}"`);
  const licence = extractField(html, /"Licence":"([^"]*)"/, "Licence field");
  if (!isCc0(licence)) throw new LicenceRejected(licence);
  const title = extractField(html, /"Title":"([^"]*)"/, "Title");
  const author = extractField(html, /"Creator":\{"Username":"([^"]*)"/, "Creator");
  const glbUrl = extractField(html, /(https:\/\/static\.poly\.pizza\/[0-9a-f-]{36}\.glb)(?!\.br)/, ".glb download URL");
  const head = await fetchWithRetry(glbUrl, { method: "HEAD" });
  const size = Number(head.headers.get("content-length"));
  if (!Number.isInteger(size) || size <= 0) throw new Error(`no Content-Length for ${glbUrl}`);
  const dest = path.resolve(ROOT, asset.dest);
  return {
    name: title, author, sourceUrl: POLYPIZZA_PAGE + asset.id, licence,
    destDir: path.dirname(dest), files: [{ url: glbUrl, size, md5: null, rel: path.basename(dest) }], warnings: [],
  };
}

function resolveAsset(asset) {
  if (asset.source === "polyhaven") return resolvePolyhaven(asset);
  if (asset.source === "polypizza") return resolvePolypizza(asset);
  throw new Error(`unknown source "${asset.source}" (valid: polyhaven, polypizza)`);
}

// ---------- download + verification ----------

// Magic-byte check: the server's Content-Type is just a claim, and a wrong file type is the
// classic way a download turns into something that gets executed or crashes an importer.
function verifyMagic(head, rel) {
  const ext = path.posix.extname(rel).toLowerCase();
  const startsWith = (bytes) => bytes.every((b, i) => head[i] === b);
  if (ext === ".jpg" || ext === ".jpeg") return startsWith([0xff, 0xd8, 0xff]);
  if (ext === ".png") return startsWith([0x89, 0x50, 0x4e, 0x47]);
  if (ext === ".glb") return head.subarray(0, 4).toString("latin1") === "glTF";
  if (ext === ".gltf") return head.toString("utf8").replace(/^﻿/, "").trimStart().startsWith("{");
  if (ext === ".bin") return true; // raw glTF buffer; no magic exists, so size + md5 are the only checks
  return false; // anything else is not a type Godot imports and is refused
}

async function downloadFile(file, cacheDir) {
  const target = path.join(cacheDir, file.rel);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const res = await fetchWithRetry(file.url);
  // Only compare the header when the body is not transfer-encoded, otherwise fetch inflates it.
  const headerLen = res.headers.get("content-encoding") ? null : Number(res.headers.get("content-length"));
  const md5 = crypto.createHash("md5");
  const sha256 = crypto.createHash("sha256");
  let received = 0;
  let head = Buffer.alloc(0);
  const out = fs.createWriteStream(target);
  for await (const chunk of res.body) {
    received += chunk.length;
    if (received > file.size) break; // stop early: the server is sending more than it promised
    md5.update(chunk);
    sha256.update(chunk);
    if (head.length < 16) head = Buffer.concat([head, chunk]).subarray(0, 16);
    if (!out.write(chunk)) await new Promise((r) => out.once("drain", r));
  }
  await new Promise((resolve, reject) => out.end((err) => (err ? reject(err) : resolve())));
  if (received !== file.size) throw new Error(`${file.rel}: expected ${file.size} bytes, received ${received}`);
  if (headerLen && headerLen !== received) throw new Error(`${file.rel}: Content-Length ${headerLen} but received ${received}`);
  if (file.md5 && md5.digest("hex") !== file.md5) throw new Error(`${file.rel}: md5 mismatch against the API`);
  if (!verifyMagic(head, file.rel)) throw new Error(`${file.rel}: magic bytes do not match a ${path.posix.extname(file.rel)} file`);
  return { cachePath: target, sha256: sha256.digest("hex") };
}

async function downloadAll(files, cacheDir) {
  const results = new Array(files.length);
  let next = 0;
  const worker = async () => {
    while (next < files.length) {
      const i = next++;
      results[i] = await downloadFile(files[i], cacheDir);
    }
  };
  await Promise.all(Array.from({ length: Math.min(MAX_CONCURRENT_FILES, files.length) }, worker));
  return results;
}

function allPresent(plan) {
  return plan.files.every((f) => {
    const p = path.join(plan.destDir, f.rel);
    return fs.existsSync(p) && fs.statSync(p).size === f.size;
  });
}

function copyIntoAssets(plan, results, asset, audit) {
  plan.files.forEach((f, i) => {
    const dest = path.join(plan.destDir, f.rel);
    if (!insideRoot(dest)) throw new Error(`refusing to write outside the project: ${dest}`);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(results[i].cachePath, dest);
    const rel = path.relative(ROOT, dest).split(path.sep).join("/");
    audit.set(rel, {
      id: asset.id, source: asset.source, name: plan.name, author: plan.author, source_url: plan.sourceUrl,
      licence: plan.licence, file_url: f.url, bytes: f.size, sha256: results[i].sha256, dest: rel,
    });
  });
}

// ---------- audit trail ----------

function loadAudit() {
  const map = new Map();
  if (!fs.existsSync(AUDIT_PATH)) return map;
  for (const entry of JSON.parse(fs.readFileSync(AUDIT_PATH, "utf8")).files || []) map.set(entry.dest, entry);
  return map;
}

function saveAudit(audit) {
  const files = [...audit.values()].sort((a, b) => a.dest.localeCompare(b.dest));
  fs.writeFileSync(AUDIT_PATH, JSON.stringify({ generated: new Date().toISOString(), files }, null, 2) + "\n");
}

function writeCredits() {
  if (!fs.existsSync(AUDIT_PATH)) die(`${AUDIT_PATH} does not exist yet. Run a fetch first (without --dry-run).`);
  const files = JSON.parse(fs.readFileSync(AUDIT_PATH, "utf8")).files || [];
  const sources = { polyhaven: "Poly Haven (https://polyhaven.com)", polypizza: "Poly Pizza (https://poly.pizza)" };
  const lines = [
    "# Credits", "",
    "Every third-party asset in this game is released under **CC0 1.0 Universal (public domain dedication)**",
    "or an equivalent public-domain statement, as read from the source site by `tools/fetch-assets.mjs` at",
    "download time. CC0 permits copying, modifying, distributing and selling the work, including commercially,",
    "with no attribution required. We credit the authors anyway, with thanks.", "",
    "Generated from `tools/assets-manifest.json` by `node tools/fetch-assets.mjs --credits`. Do not edit by hand.", "",
  ];
  for (const [source, title] of Object.entries(sources)) {
    const byId = new Map();
    for (const f of files.filter((x) => x.source === source)) {
      const e = byId.get(f.id) || { ...f, count: 0, bytes: 0 };
      e.count += 1;
      e.bytes += f.bytes;
      byId.set(f.id, e);
    }
    if (byId.size === 0) continue;
    lines.push(`## ${title}`, "", "| Asset | Author | Source | Licence | Files |", "|---|---|---|---|---|");
    for (const e of [...byId.values()].sort((a, b) => a.name.localeCompare(b.name))) {
      lines.push(`| ${e.name} (\`${e.id}\`) | ${e.author} | ${e.source_url} | ${e.licence} | ${e.count} (${fmtBytes(e.bytes)}) |`);
    }
    lines.push("");
  }
  fs.writeFileSync(CREDITS_PATH, lines.join("\n"));
  console.log(`wrote ${path.relative(ROOT, CREDITS_PATH)} (${files.length} files credited)`);
}

// ---------- per-asset driver ----------

function planBytes(plan) {
  return plan.files.reduce((sum, f) => sum + f.size, 0);
}

async function processAsset(asset, opts, state, audit) {
  const plan = await resolveAsset(asset);
  const bytes = planBytes(plan);
  const where = path.relative(ROOT, plan.destDir).split(path.sep).join("/");
  const detail = `${plan.files.length} files, ${fmtBytes(bytes)} -> ${where}/`;
  for (const w of plan.warnings) console.log(`         warning: ${asset.id}: ${w}`);

  if (asset.optional && !opts.includeOptional) {
    state.optionalBytes += bytes;
    return `optional ${asset.id}  CC0 confirmed, ${detail}  (not fetched; add --include-optional)`;
  }
  if (!opts.force && allPresent(plan)) {
    state.counts.skip += 1;
    return `skip     ${asset.id}  already present (${detail})`;
  }
  if (opts.dryRun) {
    state.counts.dry += 1;
    state.plannedBytes += bytes;
    return `dry      ${asset.id}  would fetch ${detail}`;
  }
  if (state.downloaded + bytes > opts.maxBytes) {
    throw new Error(`fetching ${fmtBytes(bytes)} would pass the ${fmtBytes(opts.maxBytes)} cap (${fmtBytes(state.downloaded)} so far). Raise --max-bytes or fetch fewer assets with --only/--category.`);
  }
  const cacheDir = path.join(CACHE_DIR, asset.id);
  fs.rmSync(cacheDir, { recursive: true, force: true }); // always a fresh directory per asset
  fs.mkdirSync(cacheDir, { recursive: true });
  try {
    const results = await downloadAll(plan.files, cacheDir);
    copyIntoAssets(plan, results, asset, audit);
  } finally {
    if (!opts.keepRaw) fs.rmSync(cacheDir, { recursive: true, force: true });
  }
  state.downloaded += bytes;
  state.written += bytes;
  state.counts.ok += 1;
  return `ok       ${asset.id}  ${detail}  (total ${fmtBytes(state.downloaded)})`;
}

function summarise(state, opts) {
  const c = state.counts;
  console.log("");
  console.log(`summary: ok ${c.ok}, skip ${c.skip}, dry-run ${c.dry}, licence-rejected ${c.licence}, failed ${c.fail}`);
  console.log(`         downloaded ${fmtBytes(state.downloaded)}, written to assets/ ${fmtBytes(state.written)}`);
  if (opts.dryRun) console.log(`         would download ${fmtBytes(state.plannedBytes)} (cap ${fmtBytes(opts.maxBytes)})`);
  if (state.optionalBytes) console.log(`         optional assets not fetched: ${fmtBytes(state.optionalBytes)} (--include-optional)`);
  return c.fail + c.licence > 0 ? 1 : 0;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.credits) {
    writeCredits();
    return 0;
  }
  const assets = selectAssets(loadManifest(opts.manifest), opts);
  if (!opts.dryRun) checkCpuLoad();
  const audit = loadAudit();
  const state = { downloaded: 0, written: 0, plannedBytes: 0, optionalBytes: 0, counts: { ok: 0, skip: 0, dry: 0, licence: 0, fail: 0 } };
  console.log(`${opts.dryRun ? "dry run: " : ""}${assets.length} asset(s) selected`);
  for (const asset of assets) {
    try {
      console.log(await processAsset(asset, opts, state, audit));
    } catch (err) {
      if (err instanceof LicenceRejected) {
        state.counts.licence += 1;
        console.log(`SKIPPED licence  ${asset.id}  source says: ${err.message}  (nothing written; CC0 only)`);
      } else {
        state.counts.fail += 1;
        console.log(`fail     ${asset.id}  ${err.message}`);
      }
    }
  }
  if (!opts.dryRun && state.counts.ok > 0) saveAudit(audit);
  return summarise(state, opts);
}

process.exitCode = await main();
