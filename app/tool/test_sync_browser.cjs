// Fresh browser profile; shared checks exercise the same Dart code as native CI.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),cp=require('node:child_process');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const app=path.resolve(__dirname,'..'),root=path.join(app,'build/sync_probe');
fs.mkdirSync(root,{recursive:true});
const built=cp.spawnSync(process.env.DART_EXECUTABLE||'dart',['compile','js','-O1','tool/sync_browser_probe.dart','-o',path.join(root,'main.js')],{cwd:app,stdio:'inherit'});
if(built.status!==0)process.exit(built.status||1);
for(const file of ['sodium.js','argon_worker.js','secure_store.js','loro_crdt_ffi.js','loro_crdt_ffi.wasm'])fs.copyFileSync(path.join(app,'web',file),path.join(root,file));
for(const file of ['books.json','books-original.json'])fs.copyFileSync(path.join(app,'assets/data',file),path.join(root,file));
if(process.env.NATIVE_FIXTURE)fs.copyFileSync(process.env.NATIVE_FIXTURE,path.join(root,'native-fixture.json'));
fs.writeFileSync(path.join(root,'index.html'),`<!doctype html><meta charset="utf-8"><script>window.requireInterop=${!!process.env.NATIVE_FIXTURE};</script><script src="sodium.js"></script><script src="secure_store.js"></script><script src="main.js" defer></script>`);
(async()=>{
 const server=http.createServer((req,res)=>{
  const file=path.resolve(root,'.'+(req.url==='/'?'/index.html':req.url.split('?')[0]));
  if(!file.startsWith(root+path.sep)||!fs.existsSync(file)){res.writeHead(404).end();return;}
  res.setHeader('Content-Type',file.endsWith('.wasm')?'application/wasm':file.endsWith('.js')?'text/javascript':file.endsWith('.json')?'application/json':'text/html');fs.createReadStream(file).pipe(res);
 }).listen(0,'127.0.0.1');
 await new Promise(r=>server.on('listening',r));
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_EXECUTABLE||undefined});
 try{
  const page=await browser.newPage();page.on('pageerror',e=>console.error(e.message));
  await page.goto(`http://127.0.0.1:${server.address().port}`);
  await page.waitForFunction(()=>window.prototypeResult,null,{timeout:120000});
  const result=await page.evaluate(()=>window.prototypeResult);console.log(result);
  if(!result.startsWith('PASS'))process.exitCode=1;
  const fixture=await page.evaluate(()=>window.webFixture);
  if(fixture)fs.writeFileSync(path.join(root,'web-fixture.json'),fixture);
  await page.evaluate(async()=>{
    await mosterdzaadSecrets.write('test-key','only-local');
    if(await mosterdzaadSecrets.read('test-key')!=='only-local')throw Error('WebCrypto storage');
  });
  await page.reload();
  await page.waitForFunction(()=>window.mosterdzaadSecrets);
  const persisted=await page.evaluate(()=>mosterdzaadSecrets.read('test-key'));
  if(persisted!=='only-local')throw Error('WebCrypto restart');
 }finally{await browser.close();server.closeAllConnections();server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
