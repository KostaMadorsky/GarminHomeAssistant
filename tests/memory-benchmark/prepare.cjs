const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const crypto = require('node:crypto');
const repo = path.resolve(__dirname, '../..');
const root = path.join(repo, 'bin', 'memory-benchmark');
fs.mkdirSync(root, {recursive:true});
const rev = process.argv[2] || 'working';
const name = rev === 'working' ? 'feature' : 'upstream';
const out = path.join(root, name);
fs.mkdirSync(path.join(out, 'source'), {recursive:true});
function git(...args) { return cp.execFileSync('git', ['-c', `safe.directory=${repo.replaceAll('\\','/')}`, ...args], {cwd:repo,encoding:'utf8'}); }
let files = rev === 'working' ? fs.readdirSync(path.join(repo,'source')).filter(f=>f.endsWith('.mc') && !f.endsWith('Tests.mc')) : git('ls-tree','--name-only',rev,'source/').trim().split('\n').map(f=>f.slice('source/'.length)).filter(f=>f.endsWith('.mc'));
files = files.filter(f => f !== 'ClientId.mc');
let hashes = {};
for (const f of files) {
  let s = rev === 'working' ? fs.readFileSync(path.join(repo,'source',f),'utf8') : git('show',`${rev}:source/${f}`);
  hashes[f] = crypto.createHash('sha256').update(s).digest('hex');
  if (f === 'HomeAssistantApp.mc') s = instrument(s);
  fs.writeFileSync(path.join(out,'source',f),s);
}
// The production checkout uses an untracked developer ClientId. Never copy credentials.
const clientId = fs.readFileSync(path.join(repo,'source','ClientId.mc.unpopulated'),'utf8');
fs.writeFileSync(path.join(out,'source','ClientId.mc'),clientId);
function functionBounds(s, name) {
  const start = s.indexOf(`function ${name}(`);
  if (start < 0) throw Error(`Missing ${name}`);
  // The functions instrumented here have no structural object types in signatures.
  const open = s.indexOf('{',start); let depth=1, i=open+1;
  // Braces in string literals and comments must not participate in the scan.
  let state='code';
  for (; i<s.length && depth; i++) {
    const c=s[i], next=s[i+1];
    if (state==='line') {if(c==='\n') state='code'; continue;}
    if (state==='block') {if(c==='*' && next==='/'){state='code'; i++;} continue;}
    if (state==='string') {if(c==='\\'){i++;continue;} if(c==='"')state='code'; continue;}
    if(c==='/' && next==='/'){state='line';i++;continue;}
    if(c==='/' && next==='*'){state='block';i++;continue;}
    if(c==='"'){state='string';continue;}
    if(c==='{')depth++; if(c==='}')depth--;
  }
  if(depth) throw Error(`Unclosed ${name}`);
  return {start,open,end:i};
}
function replaceBody(s, name, body) { const b=functionBounds(s,name); return s.slice(0,b.open+1)+'\n'+body+'\n    '+s.slice(b.end-1); }
function instrument(app) {
  app = replaceBody(app,'getInitialView',`
        mIsApp = true;
        mQuitTimer = new QuitTimer();
        mUpdateTimer = new Timer.Timer();
        Properties.setValue("api_key", "synthetic-benchmark");
        Properties.setValue("api_url", "http://127.0.0.1:8765");
        Properties.setValue("webhook_id", "synthetic-benchmark");
        Properties.setValue("poll_delay_combined", 30000);
        Properties.setValue("enable_menu_update_check", false);
        Properties.setValue("cache_config", false);
        Properties.setValue("clear_webhook_id", false);
        Properties.setValue("wifi_lte_execution", false);
        Properties.setValue("app_timeout", 0);
        Properties.setValue("show_type_icons", true);
        Properties.setValue("enable_battery_level", false);
        Settings.update();
        mBenchTimer = new Timer.Timer();
        mBenchTimer.start(method(:benchmarkFetch), 500, false);
        return [new WatchUi.View(), new WatchUi.BehaviorDelegate()];`);
  const hasSeam=app.includes('function requestMenuUpdate(');
  if (hasSeam) app=replaceBody(app,'requestMenuUpdate',`
        benchmarkTransport(null, {"type" => "render_template", "data" => templates}, {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON},
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:onReturnUpdateMenuItems));`);
  else {
    const b=functionBounds(app,'updateMenuItems');
    let block=app.slice(b.start,b.end);
    if(block.split('Communications.makeWebRequest(').length !== 2) throw Error('Unexpected update transport count');
    app=app.slice(0,b.start)+block.replace('Communications.makeWebRequest(', 'benchmarkTransport(')+app.slice(b.end);
  }
  const hasNavigation=app.includes('function menuNavigationChanged(');
  let nav=hasNavigation ? 'menuNavigationChanged();' : 'mItemsToUpdate = null; mTemplates = null; updateMenuItems();';
  if(hasNavigation) {
    const b=functionBounds(app,'menuNavigationChanged');
    const sig=app.slice(b.start,b.open);
    if(!sig.includes('menuNavigationChanged()')) nav='menuNavigationChanged(true);';
  }
  const helper=`
    private var mBenchTimer as Timer.Timer?;
    private var mBenchDefinition as Lang.Dictionary?;
    private var mBenchScenario as Lang.String = "";
    private var mBenchRequests as Lang.Number = 0;
    private var mBenchCycle as Lang.Number = 0;
    private var mBenchBusy as Lang.Boolean = false;
    function benchmarkSnapshot(label as Lang.String) as Void {
        var stats = System.getSystemStats();
        System.println("MEM," + mBenchScenario + "," + mBenchCycle + "," + label + "," + stats.usedMemory + "," + stats.freeMemory + "," + stats.totalMemory + "," + mBenchRequests);
    }
    function benchmarkFetch() as Void {
        benchmarkSnapshot("baseline");
        Communications.makeWebRequest("http://127.0.0.1:8765/menu", null, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:benchmarkOnMenu));
    }
    function benchmarkOnMenu(code as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        if (code != 200 || data == null) {
            System.println("BENCH_ERROR_MENU," + code); System.exit(); return;
        }
        mBenchScenario = (data as Lang.Dictionary).get("benchmark_scenario") as Lang.String;
        benchmarkSnapshot("parsed_config");
        mBenchDefinition = data as Lang.Dictionary;
        mBenchTimer.start(method(:benchmarkConstruct), 250, false);
    }
    function benchmarkConstruct() as Void {
        mHaMenu = new HomeAssistantView(mBenchDefinition, null);
        mBenchDefinition = null;
        benchmarkSnapshot("constructed_inline");
        mBenchTimer.start(method(:benchmarkStart), 250, false);
    }
    function benchmarkStart() as Void {
        benchmarkSnapshot("constructed_settled");
        mUpdating = true;
        updateMenuItems();
    }
    function benchmarkTransport(url, data, options, callback) as Void {
        mBenchRequests++;
        mBenchBusy = true;
        benchmarkSnapshot("request_" + mBenchRequests);
        Communications.makeWebRequest("http://127.0.0.1:8765/render", data, options, method(:benchmarkOnResponse));
    }
    function benchmarkOnResponse(code as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        benchmarkSnapshot("decoded_response_" + mBenchRequests);
        if (code != 200 || data == null) {
            System.println("BENCH_ERROR_RESPONSE," + code); System.exit(); return;
        }
        mBenchBusy = false;
        onReturnUpdateMenuItems(code, data as Lang.Dictionary);
        mUpdateTimer.stop();
        if (!mBenchBusy) { mBenchTimer.start(method(:benchmarkSettled), 250, false); }
    }
    function benchmarkSettled() as Void {
        benchmarkSnapshot("settled");
        if (mBenchScenario.equals("lazy") && mBenchCycle < 2) {
            var group = HomeAssistantMenuItem.getDisplayedItem(mHaMenu.getItem(8)) as HomeAssistantGroupMenuItem;
            group.setEntered(mBenchCycle == 0);
            if (mBenchCycle == 0) { group.getMenuView(); }
            mBenchCycle++;
            ${nav}
        } else if (mBenchCycle < 3) {
            mBenchCycle++;
            updateMenuItems();
        } else {
            System.println("BENCH_DONE," + mBenchScenario);
            System.exit();
        }
    }
`;
  // Upstream predates policy methods: omit lazy-only calls in its harness.
  const finalHelper = name==='upstream' ? helper.replace(/        if \(mBenchScenario\.equals\("lazy"\) && mBenchCycle < 2\) \{[\s\S]*?        \} else if \(mBenchCycle < 3\)/, '        if (mBenchCycle < 3)') : helper;
  const end = app.lastIndexOf('\n}\n',app.indexOf('\nfunction getApp'));
  if(end<0)throw Error('Class end not found');
  return app.slice(0,end)+'\n'+finalHelper+app.slice(end);
}
const manifest=fs.readFileSync(path.join(repo,'manifest.xml'),'utf8').replace(/id="98c36259-498a-4458-9cef-74a273ad2bc3"/,'id="8187e137-e1b4-4ba8-b4c0-7ea083499acd"');
fs.writeFileSync(path.join(out,'manifest.xml'),manifest);
const p=repo.replaceAll('\\','/');
fs.writeFileSync(path.join(out,'benchmark.jungle'),`project.manifest = manifest.xml\nbase.sourcePath = source\nbase.resourcePath = ${p}/resources\nfenix9pro47mm.resourcePath = $(fenix9pro47mm.resourcePath);${p}/resources-launcher-65-65;${p}/resources-icons-53;${p}/resources-complication\ninstinct2.resourcePath = $(instinct2.resourcePath);${p}/resources-launcher-62-62;${p}/resources-icons-21-w\ninstinct2.excludeAnnotations = selectView\n`);
fs.writeFileSync(path.join(out,'source-hashes.json'),JSON.stringify({revision:rev,head:git('rev-parse','HEAD').trim(),hashes},null,2));
console.log(`Prepared ${name}: ${files.length} production sources; requests use localhost synthetic server only.`);
