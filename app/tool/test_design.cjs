// Real release UI, fresh browser profile and synthetic notes only.
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('node:fs/promises');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');

async function main() {
  const root = path.resolve(__dirname, '../build/web');
  const previews = path.resolve(__dirname, '../build/previews');
  await fs.mkdir(previews, {recursive: true});
  const types = {'.html':'text/html','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.ttf':'font/ttf','.otf':'font/otf','.png':'image/png'};
  const server = http.createServer(async (req, res) => {
    try {
      const pathname = new URL(req.url, 'http://localhost').pathname;
      const file = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
      if (!file.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
      res.writeHead(200, {'Content-Type': types[path.extname(file)] || 'application/octet-stream'}).end(await fs.readFile(file));
    } catch { res.writeHead(404).end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({headless:true, executablePath:process.env.CHROME_EXECUTABLE || undefined});
  const context = await browser.newContext({viewport:{width:1600,height:1200},acceptDownloads:true});
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(String(error)));
  const button = name => page.getByRole('button', {name, exact:true});
  const field = name => page.getByRole('textbox', {name, exact:name.startsWith('Titel')});
  const frames = () => page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  const fill = async (name, value) => { await field(name).click(); await frames(); await field(name).fill(value); await frames(); };
  const semantics = async () => {
    await page.locator('flt-semantics-placeholder').waitFor();
    await page.locator('flt-semantics-placeholder').dispatchEvent('click');
  };
  const shot = name => page.screenshot({path:path.join(previews, name + '.png')});
  const save = async () => {
    await button('Opslaan').click();
    await page.getByRole('heading', {name:'Nieuwe notitie', exact:true}).waitFor({state:'hidden'});
    await frames();
  };
  try {
    await page.goto(`http://127.0.0.1:${server.address().port}`);
    await semantics();
    await button('Nieuw studieboek maken').click();
    await fill('Naam van je studieboek', 'Mijn stille momenten');
    await button('Studieboek maken').click();
    await button('Leesplannen').click();
    await button('Nieuw toevoegen').click();
    assert.equal(await field('Aantal dagen / sessies').inputValue(), '');
    assert((await field('Titel').boundingBox()).y < (await field('Omschrijving').boundingBox()).y);
    await fill('Titel', 'Twee dagen van aandacht');
    await fill('Omschrijving', 'Een moment van rust. Lees, verwonder en schrijf op wat je raakt.');
    // Sidebar stays available during editing and protects unsaved work.
    await button('Instellingen').click();
    await button('Annuleren').click();
    await field('Titel').click();
    assert.equal(await field('Titel').inputValue(), 'Twee dagen van aandacht');
    await fill('Aantal dagen / sessies', '3');
    await button('Sessie 3').click();
    await fill('Overdenking en vragen', 'Deze tekst blijft bij het tijdelijk inkorten bewaard.');
    await fill('Aantal dagen / sessies', '1');
    await fill('Aantal dagen / sessies', '3');
    // The existing expansion may remain open; no controller may be discarded.
    if (!await field('Overdenking en vragen').isVisible()) await button('Sessie 3').click();
    await field('Overdenking en vragen').click();
    assert.equal(await field('Overdenking en vragen').inputValue(), 'Deze tekst blijft bij het tijdelijk inkorten bewaard.');
    await fill('Aantal dagen / sessies', '2');
    await shot('design-plan-editor');
    await button('Opslaan').click();
    await button('Inkorten en opslaan').click();
    await page.getByRole('button', {name:'Twee dagen van aandacht 2 sessies',exact:true}).waitFor();
    await frames();
    await button('Overzicht').click();
    await page.getByText(/Ruimte om te groeien/).waitFor();
    await page.getByRole('button', {name:/Twee dagen van aandacht/}).waitFor();
    if (await button('Sluiten').isVisible()) await button('Sluiten').click();
    await shot('design-overview-desktop');
    await page.getByRole('button', {name:/Twee dagen van aandacht/}).click();
    for (let i = 1; i <= 2; i++) {
      await button(`Sessie ${i}`).click();
      await button('Schrijf je gedachten').click();
      await fill('Wat wil je bewaren?', `Gedachte voor dag ${i}`);
      await save();
      await button(`Sessie ${i}`).click();
    }
    await button('Overzicht').click();
    await page.getByText(/Ruimte om te groeien/).waitFor();
    await page.getByRole('group', {name:/Je leesplannen zijn afgerond/}).waitFor();
    // Deleting one session's only note makes the plan active again.
    await button('Notities').click();
    await page.getByRole('button', {name:/Gedachte voor dag 1/}).click();
    await button('Verwijderen').click();
    await button('Verwijderen').click();
    await button('Instellingen').click();
    await button('Definitief verwijderen').click();
    await button('Annuleren').click();
    await button('Terugzetten').waitFor();
    await button('Definitief verwijderen').click();
    await button('Definitief verwijderen').click();
    await button('Terugzetten').waitFor({state:'hidden'});
    const downloaded = page.waitForEvent('download');
    await button('Reservekopie downloaden').click();
    const backup = await fs.readFile(await (await downloaded).path(), 'utf8');
    assert(!backup.includes('Gedachte voor dag 1'));
    assert(backup.includes('Gedachte voor dag 2'));
    const allLocal = await page.evaluate(() => new Promise((resolve, reject) => {
      const request = indexedDB.open('mosterdzaad-v1');
      request.onerror = () => reject(request.error);
      request.onsuccess = () => {
        const db = request.result;
        const read = db.transaction('files').objectStore('files').getAll();
        read.onsuccess = () => { resolve(read.result); db.close(); };
        read.onerror = () => reject(read.error);
      };
    }));
    assert(!allLocal.some(text => text.includes('Gedachte voor dag 1')));
    await button('Overzicht').click();
    await page.getByText(/Ruimte om te groeien/).waitFor();
    await page.getByRole('button', {name:/Twee dagen van aandacht/}).waitFor();
    await shot('design-overview-with-notes');
    await page.setViewportSize({width:390,height:844});
    await page.reload();
    await semantics();
    await button('Kies een Bijbelboek').waitFor();
    await frames();
    await shot('design-overview-phone');
    await page.setViewportSize({width:844,height:390});
    await button('Instellingen').waitFor();
    await shot('design-landscape');
    assert.deepEqual(errors, []);
    console.log('Design passed: persistent navigation, unsaved edits, session count/retention, plan completion, confirmed permanent deletion, desktop/phone/landscape.');
  } catch (error) {
    await shot('design-failure');
    console.error(await page.locator('body').ariaSnapshot());
    console.error('Browser errors:', errors);
    throw error;
  } finally {
    await context.close(); await browser.close();
    server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
