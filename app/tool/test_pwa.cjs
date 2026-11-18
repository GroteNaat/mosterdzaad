// Release-build browser test. Install playwright 1.62.1, then run from app/.
// Uses a fresh headless browser context; never a user's browser profile.
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('node:fs/promises');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');

async function main() {
  const appRoot = path.resolve(__dirname, '..');
  const root = path.join(appRoot, 'build/web');
  const previews = path.join(appRoot, 'build/previews');
  const types = {'.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json',
    '.wasm': 'application/wasm', '.png': 'image/png', '.ttf': 'font/ttf', '.otf': 'font/otf'};
  let nextRelease = false;
  const server = http.createServer(async (req, res) => {
    try {
      const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
      const file = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
      if (!file.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
      let data = await fs.readFile(file);
      if (nextRelease && pathname.endsWith('/service_worker.js')) {
        data = Buffer.from(data.toString().replace('const CACHE = PREFIX +', "const CACHE = PREFIX + 'test-update-' +"));
      }
      res.writeHead(200, {'Content-Type': types[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store'}).end(data);
    } catch { res.writeHead(404).end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_EXECUTABLE || undefined});
  const context = await browser.newContext({viewport: {width: 1280, height: 1000}, acceptDownloads: true});
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(String(error)));
  const enableSemantics = async () => {
    await page.locator('flt-semantics-placeholder').waitFor();
    await page.locator('flt-semantics-placeholder').dispatchEvent('click');
  };
  try {
    await page.goto(origin);
    await enableSemantics();
    await page.getByRole('button', {name: 'Nieuw studieboek maken', exact: true}).click();
    await page.getByRole('textbox', {name: 'Naam van je studieboek'}).fill('Browserproef');
    await page.getByRole('button', {name: 'Studieboek maken', exact: true}).click();
    await page.getByRole('button', {name: 'Nieuwe notitie', exact: true}).first().click();
    await page.getByRole('textbox', {name: 'Titel (optioneel)'}).fill('Een bewaarde gedachte');
    await page.getByRole('textbox', {name: 'Wat wil je bewaren?'}).fill('Deze notitie blijft offline bestaan.');
    await page.getByRole('textbox', {name: 'Bijbelverwijzingen'}).fill('Johannes 3:16');
    await page.getByRole('button', {name: 'Opslaan', exact: true}).click();
    await page.getByRole('tab', {name: /Instellingen/}).click();
    await page.getByRole('button', {name: 'Reservekopie downloaden', exact: true}).waitFor();
    await page.waitForFunction(() => !!navigator.serviceWorker.controller);
    const cached = await page.evaluate(async () => {
      const names = await caches.keys();
      const cache = await caches.open(names.find(n => n.startsWith('mosterdzaad-assets-')));
      return (await cache.keys()).map(r => new URL(r.url).pathname);
    });
    assert(cached.includes('/main.dart.js'));
    assert(cached.some(p => p.endsWith('canvaskit.wasm')));
    assert(!cached.includes('/auth.html'));
    const downloadEvent = page.waitForEvent('download');
    await page.getByRole('button', {name: 'Reservekopie downloaden', exact: true}).click();
    const download = await downloadEvent;
    const backupPath = await download.path();
    const backup = JSON.parse(await fs.readFile(backupPath, 'utf8'));
    assert.equal(backup.format, 'mosterdzaad-snapshot');
    assert.equal(JSON.parse(backup.files['mosterdzaad.json']).name, 'Browserproef');
    assert(Object.values(backup.files).some(text => text.includes('Deze notitie blijft offline bestaan.')));
    assert(!JSON.stringify(backup).includes('access_token'));
    // Reload offline: the actual Flutter app must boot and reopen IndexedDB.
    await context.setOffline(true);
    await page.reload();
    await enableSemantics();
    await page.getByRole('tab', {name: /Instellingen/}).click();
    await page.getByRole('button', {name: 'Reservekopie downloaden', exact: true}).waitFor();
    assert((await page.locator('body').innerText()).includes('Browserproef'));
    await fs.mkdir(previews, {recursive: true});
    await page.screenshot({path: path.join(previews, 'pwa-offline.png')});
    await context.setOffline(false);
    await page.getByRole('button', {name: 'Ander studieboek openen', exact: true}).click();
    const chooserEvent = page.waitForEvent('filechooser');
    await page.getByRole('button', {name: 'Reservekopie herstellen', exact: true}).click();
    await (await chooserEvent).setFiles({name: 'backup.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(backup))});
    await page.getByRole('tab', {name: /Instellingen/}).click();
    await page.getByRole('button', {name: 'Reservekopie downloaden', exact: true}).waitFor();
    assert((await page.locator('body').innerText()).includes('Browserproef'));
    // A new service worker must wait rather than discard an unsaved note.
    await page.getByRole('button', {name: 'Nieuwe notitie', exact: true}).first().click();
    await page.getByRole('textbox', {name: 'Wat wil je bewaren?'}).fill('Nog niet opgeslagen concept');
    nextRelease = true;
    await page.evaluate(async () => (await navigator.serviceWorker.getRegistration()).update());
    await page.waitForFunction(async () => !!(await navigator.serviceWorker.getRegistration()).waiting);
    assert.equal(await page.getByRole('textbox', {name: 'Wat wil je bewaren?'}).inputValue(), 'Nog niet opgeslagen concept');
    assert.deepEqual(errors, []);
    console.log('PWA passed: notes persist, offline restart, backup export/restore, updates preserve unsaved edits.');
  } catch (error) {
    await fs.mkdir(previews, {recursive: true});
    await page.screenshot({path: path.join(previews, 'pwa-failure.png')});
    console.error((await page.locator('body').innerText()).slice(0, 5000));
    console.error(await page.locator('body').ariaSnapshot());
    console.error('Browser errors:', errors);
    throw error;
  } finally {
    await context.close();
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
