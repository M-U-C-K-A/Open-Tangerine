const assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
function element(dataset={}){return {dataset,hidden:false,disabled:false,textContent:'',style:{},attrs:{},handlers:{},classList:{toggle(){}},setAttribute(k,v){this.attrs[k]=v},addEventListener(k,v){this.handlers[k]=v},setPointerCapture(){}};}
const ids=Object.fromEntries(['play-demo','sample-file','sample-name','shortcut-key','shortcut-label','demo-wheel','result-file','result-name','result-detail','step-number','demo-instruction','demo-next','notch-label'].map(id=>[id,element()]));
const stage=element(),choices=Array.from({length:4},(_,i)=>element({choice:String(i)})),scenes=['convert','crop','merge'].map(scene=>element({scene}));let next=0;const timers=new Map();
const document={hidden:false,getElementById:id=>ids[id],querySelector:()=>stage,querySelectorAll:s=>s==='[data-choice]'?choices:s==='[data-scene]'?scenes:[],addEventListener(){}};
vm.runInNewContext(fs.readFileSync(require.resolve('../docs/assets/demo.js'),'utf8'),{document,matchMedia:()=>({matches:false}),setTimeout:fn=>{timers.set(++next,fn);return next},clearTimeout:id=>timers.delete(id)});
const click=el=>el.handlers.click();const tick=()=>{const [id,fn]=timers.entries().next().value;timers.delete(id);fn()};
click(ids['demo-next']);assert.equal(stage.dataset.phase,'choose');click(choices[0]);assert.equal(stage.dataset.phase,'processing');tick();assert.equal(ids['result-name'].textContent,'weekend.jpg');assert.equal(stage.dataset.phase,'done');
click(scenes[1]);click(ids['demo-next']);click(choices[0]);click(scenes[2]);assert.equal(timers.size,0);assert.equal(stage.dataset.phase,'idle');assert.equal(ids['sample-name'].textContent,'notes.pdf + ideas.pdf');
click(ids['play-demo']);tick();tick();assert.equal(stage.dataset.phase,'processing');click(ids['play-demo']);assert.equal(stage.dataset.phase,'choose');assert.equal(ids['demo-next'].disabled,false);assert.equal(timers.size,0);
click(choices[0]);tick();assert.equal(ids['result-name'].textContent,'combined.pdf');
console.log('PASS demo conversion, scene-switch cancellation, playback pause recovery and PDF result');
