'use strict';
(()=>{
const stage=document.querySelector('.desktop-demo');if(!stage)return;
const scenes={convert:{input:'weekend.png',key:'⇧ Shift',hint:'Reveal conversion options',choices:['JPEG','TIFF','PDF','PNG'],outputs:['weekend.jpg','weekend.tiff','weekend.pdf','weekend.png'],operation:'Converting',detail:'New file. Original kept.'},crop:{input:'weekend.png',key:'⌘ Command',hint:'Reveal image tools',choices:['Crop','Resize','Rotate','Frame'],outputs:['weekend-cropped.png','weekend-resized.png','weekend-rotated.png','weekend-framed.png'],operation:'Preparing your image',detail:'Edited copy. Original kept.'},merge:{input:'notes.pdf + ideas.pdf',key:'⌘ Command',hint:'Reveal PDF tools',choices:['Merge','Split','Pages','Extract'],outputs:['combined.pdf','page-1.pdf','reordered.pdf','extracted.txt'],operation:'Preparing your document',detail:'New document. Originals kept.'}};
const $=id=>document.getElementById(id);let scene='convert',phase='idle',choice=0,timer=null,playing=false;
const reduced=matchMedia('(prefers-reduced-motion: reduce)');
const choiceButtons=[...document.querySelectorAll('[data-choice]')];
function stop(){clearTimeout(timer);timer=null;playing=false;if(phase==='processing'){phase='choose';render();}$('play-demo').textContent='Watch it happen ▷';$('play-demo').setAttribute('aria-pressed','false');}
function render(){const s=scenes[scene];stage.dataset.scene=scene;stage.dataset.phase=phase;stage.dataset.choice=String(choice);$('sample-name').textContent=s.input;$('shortcut-key').textContent=s.key;$('shortcut-label').textContent=s.hint;$('demo-wheel').hidden=phase!=='choose';$('result-file').hidden=phase!=='done';choiceButtons.forEach((b,i)=>{b.textContent=s.choices[i];});$('sample-file').disabled=phase==='processing';$('result-name').textContent=s.outputs[choice];$('result-detail').textContent=s.detail;
const state={idle:['01 / 03','Pick up the sample file.','Start demo →','Ready when you are'],choose:['02 / 03','Choose an option on the wheel.','Choose '+s.choices[0]+' →','Choose your next move'],processing:['02 / 03',s.operation+'…','Working…',s.operation+'…'],done:['03 / 03',s.detail,'Replay ↻','All done. Nice work.']}[phase];['step-number','demo-instruction','demo-next','notch-label'].forEach((id,i)=>$(id).textContent=state[i]);$('demo-next').disabled=phase==='processing';document.querySelectorAll('[data-step]').forEach((el,i)=>el.classList.toggle('active',i===(phase==='idle'?0:phase==='done'?2:1)));}
function select(index){if(phase!=='choose')return;choice=index;phase='processing';render();clearTimeout(timer);timer=setTimeout(()=>{phase='done';render();stop();},reduced.matches?0:1100);}
function advance(){if(phase==='processing')return;if(phase==='idle'){phase='choose';render();}else if(phase==='choose')select(0);else {phase='idle';render();}}
$('demo-next').addEventListener('click',()=>{stop();advance();});
$('sample-file').addEventListener('click',()=>{if(suppressClick){suppressClick=false;return;}stop();if(phase==='done')phase='idle';if(phase==='idle')advance();});
choiceButtons.forEach((button,i)=>button.addEventListener('click',()=>{stop();select(i);}));
document.querySelectorAll('[data-scene]').forEach(button=>button.addEventListener('click',()=>{stop();scene=button.dataset.scene;phase='idle';choice=0;document.querySelectorAll('[data-scene]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));render();}));
$('play-demo').addEventListener('click',()=>{if(playing){stop();return;}stop();playing=true;$('play-demo').textContent='Pause Ⅱ';$('play-demo').setAttribute('aria-pressed','true');phase='idle';render();timer=setTimeout(()=>{phase='choose';render();timer=setTimeout(()=>select(0),reduced.matches?0:1600);},reduced.matches?0:1200);});
// Pointer capture keeps the sample drag within this illustration; real file drops are never read.
let drag=null,suppressClick=false;
$('sample-file').addEventListener('pointerdown',event=>{if(event.button!==0||phase==='processing')return;stop();drag={x:event.clientX,y:event.clientY,moved:false};event.currentTarget.setPointerCapture(event.pointerId);});
$('sample-file').addEventListener('pointermove',event=>{if(!drag)return;const dx=event.clientX-drag.x,dy=event.clientY-drag.y;if(Math.hypot(dx,dy)>8)drag.moved=true;if(drag.moved){event.currentTarget.style.translate=`${Math.max(-40,Math.min(140,dx))}px ${Math.max(-70,Math.min(70,dy))}px`;}});
function endDrag(event){if(!drag)return;const moved=drag.moved;drag=null;event.currentTarget.style.translate='';if(moved){suppressClick=true;phase='choose';render();setTimeout(()=>suppressClick=false,0);}}
$('sample-file').addEventListener('pointerup',endDrag);$('sample-file').addEventListener('pointercancel',event=>{drag=null;event.currentTarget.style.translate='';});
stage.addEventListener('keydown',event=>{if(event.key==='Escape'){stop();phase='idle';render();}if(event.key==='Shift'&&phase==='idle'){stop();phase='choose';render();}});
document.addEventListener('visibilitychange',()=>{if(document.hidden){stop();if(phase==='processing'){phase='choose';render();}}});
render();
})();
