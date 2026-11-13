const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { pathToFileURL } = require('node:url');
const vm = require('node:vm');

// Exercise the permission handlers shipped in the archive, including origin checks.
const source = readFileSync(process.argv[2], 'utf8');
const start = source.indexOf('var GRANTED =');
const end = source.indexOf('// src/downloads.ts', start);
assert(start >= 0 && end > start, 'Sable permission module was not found');
const enforcePermissions = vm.runInNewContext(
  source.slice(start, end) + '\nenforcePermissions;',
  { process: { platform: 'linux' }, URL }
);
let request, check;
enforcePermissions(
  {
    setPermissionRequestHandler(handler) { request = handler; },
    setPermissionCheckHandler(handler) { check = handler; },
  },
  '/unused/permissions.json',
  (url) => {
    const parsed = URL.parse(url ?? '');
    return parsed?.protocol === 'sable-app:' && parsed.host === 'app';
  },
  () => null
);
const app = 'sable-app://app/';
const widget = 'https://widget.example/';
const contents = (url) => ({ getURL: () => url, isDestroyed: () => false });

for (const permission of ['local-network', 'loopback-network', 'local-network-access']) {
  for (const [page, frame, mainFrame, allowed] of [
    [app, app, true, true],
    [app, widget, false, false],
    [widget, widget, true, false],
  ]) {
    const details = { requestingUrl: frame, securityOrigin: frame, isMainFrame: mainFrame };
    let granted;
    request(contents(page), permission, (value) => { granted = value; }, details);
    assert.equal(granted, allowed, `${permission} request from ${frame} in ${page}`);
    assert.equal(
      check(contents(page), permission, frame, { ...details, embeddingOrigin: page }),
      allowed,
      `${permission} check from ${frame} in ${page}`
    );
  }
  const mismatched = { requestingUrl: app, securityOrigin: widget, isMainFrame: true };
  let granted;
  request(contents(app), permission, (value) => { granted = value; }, mismatched);
  assert.equal(granted, false);
  assert.equal(check(contents(app), permission, app, mismatched), false);
}

(async () => {
  const { n: browserGatesCoreNetwork } = await import(pathToFileURL(process.argv[3]));
  for (const [tauri, electron, gated] of [
    [false, false, true],
    [true, false, false],
    [false, true, false],
  ]) {
    globalThis.isTauri = tauri;
    if (electron) globalThis.sableElectron = { platform: 'linux' };
    else delete globalThis.sableElectron;
    assert.equal(browserGatesCoreNetwork(), gated, `network gating: Tauri=${tauri}, Electron=${electron}`);
  }
  console.log('Sable network checks passed (native/browser detection, permissions and origin checks).');
})().catch((error) => { console.error(error); process.exitCode = 1; });
