// 重启保护 · DSH Safe Restart
// Copyright (C) 2026 TNT460
//
// 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
// （第 3 版或你选择的任何更新版本）的条款重新分发和/或修改它。
//
// 本程序基于「有用」的期望分发，但不提供任何担保；甚至不包含适销性或
// 特定用途适用性的默示担保。详见 GNU 通用公共许可证。
//
// 你应当已随本程序收到一份 GNU 通用公共许可证；如果没有，
// 见 <https://www.gnu.org/licenses/>。

// dsh-simulate.mjs — dry-run the profile's plugin bundle graph before restarting DSH.
// Usage: node dsh-simulate.mjs [profileDir]
// Exit codes: 0 = all entries loaded, 2 = at least one entry failed, 3 = usage/parse error.
import { readFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const profileDir = resolve(process.argv[2] || 'C:/Users/Admin1/.dsh/profiles/desktop');
const pkgPath = join(profileDir, 'package.json');

function loadJson(p) {
  return JSON.parse(readFileSync(p, 'utf8'));
}

function entryOf(pkgDir, pkg) {
  // Mirror the usual node resolution: exports["."] -> module/main -> index.js
  const ex = pkg.exports;
  let rel = null;
  if (typeof ex === 'string') rel = ex;
  else if (ex && typeof ex === 'object') {
    const dot = ex['.'];
    if (typeof dot === 'string') rel = dot;
    else if (dot && typeof dot === 'object') {
      rel = dot.import || dot.node || dot.default || null;
    }
  }
  if (!rel) rel = pkg.module || pkg.main || 'index.js';
  return join(pkgDir, rel);
}

function locate(name) {
  const p = join(profileDir, 'node_modules', ...name.split('/'));
  if (existsSync(join(p, 'package.json'))) return p;
  return null;
}

const pkg = loadJson(pkgPath);
const bundles = pkg?.dsh?.profile?.bundles || [];
const deps = pkg?.dependencies || {};

console.log(`profile : ${profileDir}`);
console.log(`bundles : ${bundles.length}`);
console.log('');

const rows = [];
for (const name of bundles) {
  const dir = locate(name);
  if (!dir) {
    rows.push({ name, status: 'MISSING', detail: 'not installed in node_modules' });
    continue;
  }
  let sub = {};
  try { sub = loadJson(join(dir, 'package.json')); } catch (e) {
    rows.push({ name, status: 'BAD-PKG', detail: e.message.slice(0, 120) });
    continue;
  }
  const ver = sub.version || deps[name] || '?';
  const entry = entryOf(dir, sub);

  // engine gate
  const engines = sub.engines || {};
  const wantNode = engines.node;
  let engineNote = '';
  if (wantNode) engineNote = ` engines.node=${wantNode}`;

  if (!existsSync(entry)) {
    rows.push({ name, ver, status: 'NO-ENTRY', detail: entry.replace(profileDir, '.'), engineNote });
    continue;
  }

  try {
    await import(pathToFileURL(entry).href);
    rows.push({ name, ver, status: 'OK', detail: entry.replace(profileDir, '.') + engineNote });
  } catch (e) {
    const msg = (e && (e.code ? `${e.code}: ${e.message}` : e.message) || String(e)).replace(/\s+/g, ' ');
    // Plugins legitimately import host packages that only exist inside app.asar at runtime.
    const hostDep = /Cannot find package '@deepseek-ai\//.test(msg);
    if (hostDep) {
      const missingPkg = (msg.match(/Cannot find package '([^']+)'/) || [])[1] || '@deepseek-ai/*';
      rows.push({ name, ver, status: 'HOSTDEP', detail: `needs host package ${missingPkg} (expected at runtime)` });
    } else {
      rows.push({ name, ver, status: 'FAIL', detail: msg.slice(0, 200) });
    }
  }
}

const pad = (s, n) => String(s).padEnd(n);
console.log(pad('STATUS', 9), pad('BUNDLE', 40), pad('VER', 10), 'DETAIL');
console.log('-'.repeat(110));
for (const r of rows) {
  console.log(pad(r.status, 9), pad(r.name.slice(0, 39), 40), pad(r.ver || '', 10), r.detail);
}
console.log('');

// cordis.patch.yml sanity
const patchPath = join(profileDir, 'cordis.patch.yml');
let patchStatus = 'absent';
if (existsSync(patchPath)) {
  const text = readFileSync(patchPath, 'utf8');
  patchStatus = `${text.split('\n').length} lines, ${text.length} bytes`;
  if (/^\s*\[[^\]]*\]\s*$/m.test(text) && text.trim().startsWith('[')) {
    patchStatus += ' (JSON-ish flow list at top)';
  }
}
console.log(`cordis.patch.yml : ${patchStatus}`);

const missing = rows.filter((r) => r.status === 'MISSING');
const fails = rows.filter((r) => r.status === 'FAIL' || r.status === 'BAD-PKG' || r.status === 'NO-ENTRY');
const dupes = bundles.filter((n, i) => bundles.indexOf(n) !== i);

if (missing.length) console.log(`missing   : ${missing.map((r) => r.name).join(', ')}`);
if (dupes.length) console.log(`duplicate : ${[...new Set(dupes)].join(', ')}`);
if (fails.length) {
  console.log(`failed    : ${fails.map((r) => r.name).join(', ')}`);
  process.exit(2);
}
console.log('result    : all bundles imported cleanly');
process.exit(0);
