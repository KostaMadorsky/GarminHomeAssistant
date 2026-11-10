const http=require('node:http');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'../../bin/memory-benchmark');
fs.mkdirSync(root,{recursive:true});
const scenarioFile=path.join(root,'scenario.json');
function fixture(scenario, leafCount=34) {
 const info=(name,content)=>({type:'info',name,content});
 const group=(name,items,flags={})=>({type:'group',name,title:name,content:`{{ states('sensor.synthetic_${name.toLowerCase().replaceAll(' ','_')}') }}`, ...flags, items});
 const ordinary=Array.from({length:8},(_,i)=>info(`Ordinary ${i+1}`,`{{ states('sensor.synthetic_ordinary_${i+1}') }}`));
 let n=0;
 const leaves=(label,count)=>Array.from({length:count},(_,i)=>info(`${label} ${i+1}`,`{{ state_attr('sensor.synthetic_benchmark_forecast_${++n}', '${label.toLowerCase()}') | default('-') }}`));
 let daily=Math.floor(leafCount/2/2), hourly=Math.floor(leafCount/2)-daily;
 const forecast=group('Forecast',[
   group('Location One',[group('Daily One',leaves('Day',daily)),group('Hourly One',leaves('Hour',hourly))]),
   group('Location Two',[group('Daily Two',leaves('Day',daily)),group('Hourly Two',leaves('Hour',hourly))])
 ],{lazy_loading:scenario==='lazy',delayed_load:scenario==='delayed'});
 return {title:'Synthetic benchmark',benchmark_scenario:scenario,items:[...ordinary,forecast]};
}
const server=http.createServer((req,res)=>{
 if(req.url==='/menu') {
  const settings=JSON.parse(fs.readFileSync(scenarioFile,'utf8'));
  const json=JSON.stringify(fixture(settings.scenario,settings.leafCount));
  fs.appendFileSync(path.join(root,'server.log'),`${new Date().toISOString()} MENU ${settings.scenario} ${json.length} bytes\n`);
  res.writeHead(200,{'Content-Type':'application/json'});res.end(json);return;
 }
 if(req.url==='/render') {
  let body='';req.on('data',d=>body+=d);req.on('end',()=>{
   try {
    let parsed;
    try{parsed=JSON.parse(body);}catch {const query=new URLSearchParams(body);parsed=Object.fromEntries(query);if(typeof parsed.data==='string')parsed.data=JSON.parse(parsed.data);}
    const data=parsed.data || {};
    let response={};
    for(const key of Object.keys(data)) response[key]=`${key}: Tue cloudy 15-24C 60% 1-5mm`;
    const json=JSON.stringify(response);
    fs.appendFileSync(path.join(root,'server.log'),`${new Date().toISOString()} RENDER ${Object.keys(data).length} templates request=${body.length} response=${json.length} bytes\n`);
    res.writeHead(200,{'Content-Type':'application/json'});res.end(json);
   }catch(e){console.error(e,body.slice(0,200));res.writeHead(500);res.end('{}');}
  });return;
 }
 res.writeHead(404);res.end('{}');
});
module.exports={fixture};
if(require.main===module) server.listen(8765,'127.0.0.1',()=>console.log('Synthetic benchmark server listening on 127.0.0.1:8765'));
