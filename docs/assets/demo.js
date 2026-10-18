'use strict';
// The film itself is CSS: deterministic, continuous, and independent of pointer input.
const film=document.querySelector('.product-film');
const motionButton=document.getElementById('motion-toggle');
if(film&&motionButton){
  const reduced=matchMedia('(prefers-reduced-motion: reduce)');
  let userPaused=false, inView=true;
  function sync(){
    film.dataset.paused=String(userPaused||reduced.matches);
    film.dataset.suspended=String(document.hidden||!inView);
    motionButton.setAttribute('aria-pressed',String(userPaused));
    motionButton.setAttribute('aria-label',userPaused?'Resume animation':'Pause animation');
    motionButton.textContent=userPaused?'Resume animation ▷':'Pause animation Ⅱ';
  }
  motionButton.addEventListener('click',()=>{userPaused=!userPaused;sync();});
  document.addEventListener('visibilitychange',sync);
  reduced.addEventListener('change',sync);
  if(typeof IntersectionObserver!=='undefined')new IntersectionObserver(entries=>{inView=entries[0].isIntersecting;sync();},{threshold:0.05}).observe(film);
  sync();
}
