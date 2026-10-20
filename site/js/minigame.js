/* Мини-игра «Вылет» для flakheaven.com: 45 секунд, вид сверху.
   Самолёт стреляет сам, игрок уворачивается от разрывов зениток и пуль.
   Управление: палец или мышь (тянуть), стрелки или WASD. Рекорд — только в localStorage браузера. */
(function(){
"use strict";
var root=document.getElementById("mg");if(!root)return;
var cv=root.querySelector("canvas"),ctx=cv.getContext("2d");
var ui={start:root.querySelector(".mg-start"),over:root.querySelector(".mg-over"),score:root.querySelector(".mg-score"),best:root.querySelector(".mg-best"),
  hud:root.querySelector(".mg-hud"),play:root.querySelector(".mg-play"),again:root.querySelector(".mg-again")};
var L=function(ru,en){return document.documentElement.lang==="en"?en:ru;};
var reduce=matchMedia("(prefers-reduced-motion: reduce)").matches;

var ROUND=45,W=360,H=480,scale=1,dpr=1;
var img={};["player","enemy","heavy"].forEach(function(n){var i=new Image();i.src="img/mg_"+n+".webp";img[n]=i;});

/* ---------- земля: длинная полоса Нагорья, рисуется один раз ---------- */
var ground=null,GH=1600;
function rnd(a,b){return a+Math.random()*(b-a);}
function makeGround(){
  ground=document.createElement("canvas");ground.width=W;ground.height=GH;var g=ground.getContext("2d");
  g.fillStyle="#c9a676";g.fillRect(0,0,W,GH);
  for(var i=0;i<260;i++){var x=rnd(0,W),y=rnd(0,GH),r=rnd(10,60);
    var gr=g.createRadialGradient(x,y,0,x,y,r);var dark=Math.random()<.55;
    gr.addColorStop(0,dark?"rgba(120,88,52,.35)":"rgba(236,214,170,.35)");gr.addColorStop(1,"rgba(0,0,0,0)");
    g.fillStyle=gr;g.beginPath();g.arc(x,y,r,0,7);g.fill();
    if(y<60||y>GH-60){g.save();g.translate(0,y<60?GH:-GH);g.fillStyle=gr;g.beginPath();g.arc(x,y,r,0,7);g.fill();g.restore();}}
  /* хребты-тени */
  g.strokeStyle="rgba(90,62,36,.28)";g.lineWidth=5;g.lineCap="round";
  for(var k=0;k<38;k++){var sx=rnd(0,W),sy=rnd(0,GH);g.beginPath();g.moveTo(sx,sy);for(var j=0;j<4;j++){sx+=rnd(-30,30);sy+=rnd(10,30);g.lineTo(sx,sy);}g.stroke();}
  /* река, замкнутая по высоте */
  g.strokeStyle="#6aa7b8";g.lineWidth=9;g.beginPath();
  for(var y=0;y<=GH;y+=8){var x=W*.62+Math.sin(y/GH*Math.PI*4)*70+Math.sin(y/GH*Math.PI*10)*14;y?g.lineTo(x,y):g.moveTo(x,y);}g.stroke();
  g.strokeStyle="rgba(230,240,235,.5)";g.lineWidth=2;g.stroke();
  /* кустики */
  for(var t=0;t<120;t++){var tx=rnd(0,W),ty=rnd(0,GH);g.fillStyle="rgba(86,104,52,.75)";g.beginPath();g.arc(tx,ty,rnd(2,4.5),0,7);g.fill();}
}

/* ---------- состояние ---------- */
var S=null,raf=0,last=0,running=false,inView=true;
function active(){return inView&&!document.hidden;}
function reset(){
  S={t:0,score:0,hp:3,inv:0,px:W/2,py:H*.8,tx:W/2,ty:H*.8,fire:0,scroll:0,
     bullets:[],foes:[],eb:[],flak:[],fx:[],clouds:[],spawn:1,flakT:2,shake:0,kills:0};
  for(var i=0;i<5;i++)S.clouds.push({x:rnd(0,W),y:rnd(-H,H),r:rnd(40,80),v:rnd(70,110)});
}
function diff(){return Math.min(1,S.t/ROUND);}

/* ---------- управление ---------- */
var keys={},drag=null;
addEventListener("keydown",function(e){if(!running||!active())return;var k=e.key;if(/^(Arrow|w|a|s|d|W|A|S|D)/.test(k)){keys[k.toLowerCase()]=1;e.preventDefault();}});
addEventListener("keyup",function(e){keys[e.key.toLowerCase()]=0;});
function pt(e){var r=cv.getBoundingClientRect();return {x:(e.clientX-r.left)/r.width*W,y:(e.clientY-r.top)/r.height*H};}
cv.addEventListener("pointerdown",function(e){if(!running)return;cv.setPointerCapture(e.pointerId);var p=pt(e);drag={x:p.x,y:p.y,px:S.tx,py:S.ty};e.preventDefault();});
cv.addEventListener("pointermove",function(e){if(!drag)return;var p=pt(e);S.tx=drag.px+(p.x-drag.x)*1.25;S.ty=drag.py+(p.y-drag.y)*1.25;});
["pointerup","pointercancel"].forEach(function(n){cv.addEventListener(n,function(){drag=null;});});

/* ---------- размер ---------- */
function resize(){
  var w=root.clientWidth;dpr=Math.min(2,window.devicePixelRatio||1);
  H=Math.round(W*(w<600?1.35:0.62));cv.style.height=(w*H/W)+"px";
  cv.width=Math.round(w*dpr);cv.height=Math.round(w*H/W*dpr);scale=w/W;
  if(S){S.px=Math.min(S.px,W);S.py=Math.min(S.py,H-20);S.tx=S.px;S.ty=S.py;}
}
addEventListener("resize",function(){resize();if(!running)draw();});

/* ---------- игра ---------- */
function boom(x,y,n,big){for(var i=0;i<n;i++){var a=rnd(0,7),v=rnd(30,big?170:110);S.fx.push({x:x,y:y,vx:Math.cos(a)*v,vy:Math.sin(a)*v,l:rnd(.35,.8),m:.8,r:rnd(2,big?6:4),c:Math.random()<.5?"#ffb347":"#ff6a2b"});}
  S.fx.push({x:x,y:y,vx:0,vy:0,l:.35,m:.35,r:big?34:22,ring:1});}
function hit(){if(S.inv>0)return;S.hp--;S.inv=1.2;S.shake=.35;boom(S.px,S.py,14,false);if(S.hp<=0)end();}
function step(dt){
  S.t+=dt;var d=diff();
  /* игрок */
  var kx=(keys.arrowright||keys.d?1:0)-(keys.arrowleft||keys.a?1:0),ky=(keys.arrowdown||keys.s?1:0)-(keys.arrowup||keys.w?1:0);
  if(kx||ky){S.tx=S.px+kx*240*dt*3;S.ty=S.py+ky*240*dt*3;}
  S.tx=Math.max(18,Math.min(W-18,S.tx));S.ty=Math.max(H*.3,Math.min(H-24,S.ty));
  var k=Math.min(1,dt*12);S.px+=(S.tx-S.px)*k;S.py+=(S.ty-S.py)*k;
  if(S.inv>0)S.inv-=dt;
  S.fire-=dt;if(S.fire<=0){S.fire=.11;S.bullets.push({x:S.px-7,y:S.py-22},{x:S.px+7,y:S.py-22});}
  S.bullets.forEach(function(b){b.y-=560*dt;});S.bullets=S.bullets.filter(function(b){return b.y>-10;});
  /* враги */
  S.spawn-=dt;if(S.spawn<=0){S.spawn=Math.max(.32,1.1-d*.8)*rnd(.7,1.2);
    var heavy=Math.random()<.12+d*.18;S.foes.push({x:rnd(30,W-30),y:-40,hp:heavy?6:2,heavy:heavy,ph:rnd(0,7),sh:rnd(.8,2),vy:heavy?55:rnd(85,120)+d*40,w:heavy?44:30});}
  S.foes.forEach(function(f){f.y+=f.vy*dt;f.x+=Math.sin(S.t*1.6+f.ph)*40*dt;f.sh-=dt;
    if(f.sh<=0&&f.y>0&&f.y<H*.6){f.sh=(f.heavy?1.1:2.2)-d*.6;var a=Math.atan2(S.py-f.y,S.px-f.x),v=130+d*60;
      S.eb.push({x:f.x,y:f.y+12,vx:Math.cos(a)*v,vy:Math.sin(a)*v});if(f.heavy){S.eb.push({x:f.x,y:f.y+12,vx:Math.cos(a+.25)*v,vy:Math.sin(a+.25)*v},{x:f.x,y:f.y+12,vx:Math.cos(a-.25)*v,vy:Math.sin(a-.25)*v});}}});
  S.bullets.forEach(function(b){S.foes.forEach(function(f){if(!b.dead&&f.hp>0&&Math.abs(b.x-f.x)<f.w*.5&&Math.abs(b.y-f.y)<f.w*.5){b.dead=1;f.hp--;f.flash=.06;
    if(f.hp<=0){S.score+=f.heavy?250:100;S.kills++;boom(f.x,f.y,f.heavy?22:12,f.heavy);}}});});
  S.bullets=S.bullets.filter(function(b){return !b.dead;});
  S.foes.forEach(function(f){if(f.hp>0&&Math.abs(f.x-S.px)<f.w*.5&&Math.abs(f.y-S.py)<f.w*.5){f.hp=0;boom(f.x,f.y,14,f.heavy);hit();}if(f.flash)f.flash-=dt;});
  S.foes=S.foes.filter(function(f){return f.hp>0&&f.y<H+50;});
  S.eb.forEach(function(b){b.x+=b.vx*dt;b.y+=b.vy*dt;if(Math.hypot(b.x-S.px,b.y-S.py)<9){b.dead=1;hit();}});
  S.eb=S.eb.filter(function(b){return !b.dead&&b.y<H+10&&b.y>-10&&b.x>-10&&b.x<W+10;});
  /* зенитки: кольцо-предупреждение, через 0,9 с разрыв */
  S.flakT-=dt;if(S.flakT<=0){S.flakT=Math.max(.45,1.6-d*1.1)*rnd(.7,1.2);var n=d>.5&&Math.random()<.5?2:1;
    for(var i=0;i<n;i++)S.flak.push({x:Math.max(30,Math.min(W-30,S.px+rnd(-80,80))),y:Math.max(H*.25,Math.min(H-30,S.py+rnd(-90,60))),t:0,T:.9,r:rnd(30,40)});}
  S.flak.forEach(function(f){f.t+=dt;if(!f.done&&f.t>=f.T){f.done=1;boom(f.x,f.y,10,false);S.shake=Math.max(S.shake,.15);if(Math.hypot(S.px-f.x,S.py-f.y)<f.r)hit();}});
  S.flak=S.flak.filter(function(f){return f.t<f.T+.25;});
  /* эффекты, облака, прокрутка */
  S.fx.forEach(function(p){p.x+=p.vx*dt;p.y+=p.vy*dt+40*dt;p.vx*=.96;p.vy*=.96;p.l-=dt;});S.fx=S.fx.filter(function(p){return p.l>0;});
  S.clouds.forEach(function(c){c.y+=c.v*dt;if(c.y-c.r>H){c.y=-c.r-rnd(0,200);c.x=rnd(0,W);}});
  S.scroll=(S.scroll+60*dt)%GH;if(S.shake>0)S.shake-=dt;
  S.score+=dt*10;
  if(S.t>=ROUND){S.score+=S.hp*500;end(true);}
}
function draw(){
  ctx.setTransform(dpr*scale,0,0,dpr*scale,0,0);
  if(!ground)makeGround();
  var sx=0,sy=0;if(S&&S.shake>0&&!reduce){sx=rnd(-3,3);sy=rnd(-3,3);}
  ctx.save();ctx.translate(sx,sy);
  var off=S?S.scroll:0;ctx.drawImage(ground,0,-GH+off);ctx.drawImage(ground,0,off);if(off<H)ctx.drawImage(ground,0,off-GH);
  if(!S){ctx.restore();return;}
  /* тени самолётов */
  ctx.globalAlpha=.25;
  S.foes.forEach(function(f){var i=f.heavy?img.heavy:img.enemy;if(i.complete)ctx.drawImage(i,f.x-f.w*.5+14,f.y-f.w*.5+18,f.w,f.w*i.height/i.width);});
  if(img.player.complete)ctx.drawImage(img.player,S.px-14+14,S.py-26+18,28,28*img.player.height/img.player.width);
  ctx.globalAlpha=1;
  /* зенитки */
  S.flak.forEach(function(f){if(f.done)return;var k=f.t/f.T;ctx.strokeStyle="rgba(255,215,90,"+(.35+k*.6)+")";ctx.lineWidth=2;
    ctx.beginPath();ctx.arc(f.x,f.y,f.r,0,7);ctx.stroke();ctx.fillStyle="rgba(255,190,60,"+(k*.25)+")";ctx.beginPath();ctx.arc(f.x,f.y,f.r*k,0,7);ctx.fill();});
  /* враги */
  S.foes.forEach(function(f){var i=f.heavy?img.heavy:img.enemy;if(!i.complete)return;var h=f.w*i.height/i.width;
    ctx.drawImage(i,f.x-f.w/2,f.y-h/2,f.w,h);if(f.flash>0){ctx.fillStyle="rgba(255,255,255,.5)";ctx.beginPath();ctx.arc(f.x,f.y,f.w*.3,0,7);ctx.fill();}});
  /* пули */
  ctx.fillStyle="#fff3c4";S.bullets.forEach(function(b){ctx.fillRect(b.x-1,b.y-6,2,8);});
  ctx.fillStyle="#ff5a3c";S.eb.forEach(function(b){ctx.beginPath();ctx.arc(b.x,b.y,3.2,0,7);ctx.fill();});
  /* игрок */
  if(img.player.complete&&!(S.inv>0&&Math.floor(S.inv*14)%2)){var pw=28,ph=pw*img.player.height/img.player.width;ctx.drawImage(img.player,S.px-pw/2,S.py-ph/2,pw,ph);}
  /* взрывы */
  S.fx.forEach(function(p){var a=Math.max(0,p.l/p.m);if(p.ring){ctx.strokeStyle="rgba(255,220,150,"+a+")";ctx.lineWidth=3;ctx.beginPath();ctx.arc(p.x,p.y,p.r*(1.4-a),0,7);ctx.stroke();return;}
    ctx.fillStyle=p.c;ctx.globalAlpha=a;ctx.beginPath();ctx.arc(p.x,p.y,p.r,0,7);ctx.fill();ctx.globalAlpha=1;});
  /* облака */
  S.clouds.forEach(function(c){var g=ctx.createRadialGradient(c.x,c.y,0,c.x,c.y,c.r);g.addColorStop(0,"rgba(255,255,255,.55)");g.addColorStop(1,"rgba(255,255,255,0)");ctx.fillStyle=g;ctx.beginPath();ctx.arc(c.x,c.y,c.r,0,7);ctx.fill();});
  ctx.restore();
  /* полоса времени */
  ctx.fillStyle="rgba(0,0,0,.25)";ctx.fillRect(0,0,W,4);ctx.fillStyle="#ffb347";ctx.fillRect(0,0,W*Math.min(1,S.t/ROUND),4);
}
function hud(){var left=Math.max(0,Math.ceil(ROUND-S.t));
  ui.hud.innerHTML="<span>"+"♥".repeat(Math.max(0,S.hp))+"<i>"+"♥".repeat(3-Math.max(0,S.hp))+"</i></span><b>"+Math.floor(S.score)+"</b><span>0:"+(left<10?"0":"")+left+"</span>";}
function loop(ts){if(!running)return;var dt=Math.min(.05,(ts-(last||ts))/1000);last=ts;if(active())step(dt);if(!running)return;draw();hud();raf=requestAnimationFrame(loop);}
function start(){resize();reset();ui.start.hidden=true;ui.over.hidden=true;ui.hud.hidden=false;running=true;last=0;cancelAnimationFrame(raf);raf=requestAnimationFrame(loop);
  try{cv.focus({preventScroll:true});}catch(e){}}
function end(won){running=false;draw();ui.hud.hidden=true;var sc=Math.floor(S.score),best=0;
  try{best=+localStorage.getItem("fh-mg-best")||0;if(sc>best){localStorage.setItem("fh-mg-best",sc);}}catch(e){}
  ui.score.textContent=sc;ui.best.textContent=sc>best?L("Новый рекорд!","New best!"):L("Рекорд: ","Best: ")+best;
  root.querySelector(".mg-title").textContent=won?L("Вы продержались!","You made it!"):L("Сбит","Shot down");
  root.querySelector(".mg-kills").textContent=L("Сбито врагов: ","Kills: ")+S.kills;
  ui.over.hidden=false;}
new IntersectionObserver(function(es){inView=es[0].isIntersecting;},{threshold:.2}).observe(root);
ui.play.onclick=start;ui.again.onclick=start;
resize();draw();
})();
