const DATA=__DATA__;
let country='Ethiopia',view='overview',outcome='All reasons',selected=null;
const $=id=>document.getElementById(id);
const currentData=()=>DATA[country].views[view];
const fmt=v=>v==null?'Not estimated':v.toFixed(1);
const fmt2=v=>v==null?'Not estimated':v.toFixed(2);
const count=v=>v.toLocaleString('en-US');
const ns='http://www.w3.org/2000/svg';
function el(tag,attrs,text){const n=document.createElementNS(ns,tag);Object.entries(attrs).forEach(([k,v])=>n.setAttribute(k,v));if(text!==undefined)n.textContent=text;return n}
function color(v){const t=Math.max(0,Math.min(1,v/100)),a=[242,246,247],b=[21,63,91];return 'rgb('+a.map((x,i)=>Math.round(x+(b[i]-x)*t)).join(',')+')'}
function hidePopup(){$('reason-tooltip').hidden=true}
function exposureTier(r){return r.month1_episodes<125?'Below 125':r.month1_episodes<250?'125–249':'250+'}
function sampleWarnings(r){
 let notes=[];
 if(r.month1_episodes<125)notes.push('Only '+count(r.month1_episodes)+' first-month exposures. DHS reporting conventions would normally suppress this rate. It is retained here for exploratory detail and requires strong caution.');
 else if(r.month1_episodes<250)notes.push(count(r.month1_episodes)+' first-month exposures: within the DHS 125–249 caution category.');
 if(r.observed_target_endings<5)notes.push('Only '+r.observed_target_endings+' observed target endings; this outcome is very sparse.');
 else if(r.observed_target_endings<30)notes.push(r.observed_target_endings+' observed target endings. Interpret this outcome with its confidence interval.');
 if(r.month12_episodes<25)notes.push('Only '+r.month12_episodes+' episodes remain in the month-12 risk set.');
 return notes.length?'<div class="warning">'+notes.join(' ')+'</div>':'<p class="note">'+count(r.month1_episodes)+' first-month exposures. Assess precision with the confidence interval; the exposure category is not a power calculation.</p>';
}
function reasonTable(code,compact=false,shares=false){
 const key=shares?(outcome==='All reasons'?'share_all':'share_actionable'):'probability_12';
 const low=shares?key+'_ci_low':'ci_low_12',high=shares?key+'_ci_high':'ci_high_12';
 const rows=currentData().reasons.filter(r=>r.area_code===code&&(outcome==='All reasons'||r.actionable)).sort((a,b)=>b[key]-a[key]);
 const leading=rows.filter(r=>r[key]>0).slice(0,3);let body='';
 for(const r of rows){
  const flag=r.observed_endings<5?'†':r.observed_endings<30?'*':'';
  const marker=outcome==='All reasons'&&r.actionable?'<span class="actionable-marker" role="img" aria-label="Potentially actionable cause"></span>':'';
  body+='<tr class="'+(leading.includes(r)?'top-reason':'')+'"><td>'+marker+r.reason+flag+'</td><td>'+fmt2(r[key])+'%</td><td>'+(r[low]==null?'Not estimated':fmt2(r[low])+'–'+fmt2(r[high])+'%')+'</td>'+(!compact&&!shares?'<td>'+r.observed_endings+'</td>':'')+'</tr>';
 }
 return '<table class="reason-table"><thead><tr><th>Reported reason</th><th>'+(shares?'Share':'Probability')+'</th><th>95% CI</th>'+(!compact&&!shares?'<th>Endings</th>':'')+'</tr></thead><tbody>'+body+'</tbody></table><div class="reason-key">Highest to lowest; top three positive estimates are bold.'+(outcome==='All reasons'?' <span class="actionable-marker" aria-hidden="true"></span>Potentially actionable cause.':'')+'</div>';
}
function showPopup(code,event){
 if(!window.matchMedia('(hover: hover)').matches)return;
 const d=currentData(),all=d.summary.find(r=>r.area_code===code&&r.outcome==='All reasons'),act=d.summary.find(r=>r.area_code===code&&r.outcome==='Potentially actionable'),box=$('reason-tooltip');
 box.innerHTML='<h3>'+all.area+'</h3><div class="note">12-month probabilities · Modern methods excluding EC</div><div class="popup-totals"><div><span>All reasons</span><strong>'+fmt2(all.probability_12)+'%</strong></div><div><span>Potentially actionable</span><strong>'+fmt2(act.probability_12)+'%</strong></div></div>'+reasonTable(code,true)+'<p class="note">'+count(all.month1_episodes)+' first-month exposures ('+exposureTier(all)+'). '+count(all.eligible_episodes)+' eligible episodes. * 5–29 endings; † fewer than 5. CI endpoints do not add.</p>';
 box.hidden=false;
 const rect=document.querySelector('.area[data-code="'+code+'"]').getBoundingClientRect();
 const px=event&&event.clientX!==undefined?event.clientX:rect.x+rect.width/2,py=event&&event.clientY!==undefined?event.clientY:rect.y+rect.height/2;
 const bb=box.getBoundingClientRect();let left=px+18,top=py+18;
 if(left+bb.width>innerWidth-10)left=px-bb.width-18;
 if(top+bb.height>innerHeight-10)top=py-bb.height-18;
 box.style.left=Math.max(10,Math.min(left,innerWidth-bb.width-10))+'px';box.style.top=Math.max(10,Math.min(top,innerHeight-bb.height-10))+'px';
}
function pick(code){
 selected=code;renderDetail();
 document.querySelectorAll('.area').forEach(p=>p.classList.toggle('selected',Number(p.dataset.code)===code));
 document.querySelectorAll('#rows tr').forEach(t=>t.classList.toggle('selected',Number(t.dataset.code)===code));
}
function renderDetail(){
 const d=currentData(),r=d.summary.find(r=>r.area_code===selected&&r.outcome===outcome),times=d.monthly.filter(r=>r.area_code===selected&&r.outcome===outcome),feature=d.features.find(f=>f.code===selected);
 $('detail').innerHTML='<h3>'+r.area+'</h3><p class="note">'+count(r.eligible_episodes)+' eligible episodes · '+count(r.observed_target_endings)+' observed target endings</p>'+(feature.members?'<details class="membership"><summary>Included states/provinces</summary><p>'+feature.members+'</p></details>':'')+'<table class="mini"><thead><tr><th>Since initiation</th><th>Probability</th><th>95% CI</th></tr></thead><tbody>'+times.map(t=>'<tr><td>'+t.month+' months</td><td>'+fmt(t.probability)+'%</td><td>'+(t.ci_low==null?'Not estimated':fmt(t.ci_low)+'–'+fmt(t.ci_high)+'%')+'</td></tr>').join('')+'</tbody></table>'+sampleWarnings(r);
 $('reason-title').textContent=r.area+' · reasons for first-year discontinuation';
 $('probability-analysis').innerHTML=reasonTable(selected)+'<p class="note">Endings are unweighted observed events. * 5–29 endings; † fewer than 5. Confidence-interval endpoints do not add.</p>';
 $('share-denominator').textContent=(outcome==='All reasons'?'Among all observed first-year modern-method discontinuations, including other/unknown/missing reasons.':'Among observed first-year discontinuations attributed to the five potentially actionable categories only.')+' Percentages are survey-weighted; EC is excluded. Observed endings: '+count(r.observed_target_endings)+'.';
 $('share-analysis').innerHTML=reasonTable(selected,false,true)+'<p class="note">* 5–29 endings; † fewer than 5. A zero observed count does not establish zero population risk.</p>';
}
function geographyOptions(){
 const select=$('geography');select.replaceChildren();
 for(const [key,d] of Object.entries(DATA[country].views)){const option=document.createElement('option');option.value=key;option.textContent=d.label;select.append(option)}
 select.value=view;select.disabled=Object.keys(DATA[country].views).length===1;
}
function render(){
 hidePopup();const d=currentData(),rows=d.summary.filter(r=>r.area_code&&r.outcome===outcome).sort((a,b)=>b.probability_12-a.probability_12),nat=d.summary.find(r=>!r.area_code&&r.outcome===outcome);
 if(!rows.some(r=>r.area_code===selected))selected=rows[0].area_code;
 const top=rows.slice(0,3).map(r=>r.area_code);
 document.querySelectorAll('.country').forEach(b=>b.setAttribute('aria-pressed',b.dataset.country===country));geographyOptions();
 $('maptitle').textContent=country+' · DHS '+d.metadata.survey+' · '+d.label;
 $('mapscope').textContent='12-month discontinuation · '+outcome.toLowerCase()+' · Modern methods excluding EC · Unadjusted';
 $('national').innerHTML='<span>National 12-month probability · '+outcome.toLowerCase()+'</span><br><strong>'+fmt(nat.probability_12)+'%</strong> <span>('+fmt(nat.ci_low_12)+'–'+fmt(nat.ci_high_12)+'%, 95% CI)</span><div class="note">'+count(nat.eligible_episodes)+' modern-method episodes · EC excluded</div>';
 const low=rows.filter(r=>r.month1_episodes<125).length,caution=rows.filter(r=>r.month1_episodes>=125&&r.month1_episodes<250).length;
 $('viewnote').textContent=d.detail?'Exploratory detail: '+low+' areas have fewer than 125 first-month exposures and '+caution+' have 125–249. Below-125 estimates are retained for exploration with explicit warnings. This view does not establish precise rankings.':d.grouping_note;
 $('viewnote').classList.toggle('detail-warning',d.detail);
 const svg=el('svg',{viewBox:'0 0 800 660',class:'map'+(d.features.length===6?' coarse-map':''),role:'group','aria-label':country+' '+d.label+': 12-month modern-method discontinuation, '+outcome});
 const defs=el('defs',{}),hatch=el('pattern',{id:'hatch-low',width:7,height:7,patternUnits:'userSpaceOnUse',patternTransform:'rotate(35)'}),dots=el('pattern',{id:'dots-caution',width:8,height:8,patternUnits:'userSpaceOnUse'});
 hatch.append(el('line',{x1:0,x2:0,y1:0,y2:7,stroke:'#244957','stroke-width':1.4,opacity:.32}));dots.append(el('circle',{cx:2,cy:2,r:1,fill:'#244957',opacity:.22}));defs.append(hatch,dots);svg.append(defs);
 for(const f of d.features){
  const r=rows.find(r=>r.area_code===f.code),path=el('path',{d:f.path,fill:color(r.probability_12),'fill-rule':'evenodd',class:'area'+(top.includes(f.code)?' top':'')+(f.code===selected?' selected':''),'data-code':f.code,tabindex:0,role:'button','aria-label':r.area+': '+fmt(r.probability_12)+'%; '+exposureTier(r)+' first-month exposures','aria-describedby':'reason-tooltip'});
  path.addEventListener('mouseenter',e=>showPopup(f.code,e));path.addEventListener('mousemove',e=>showPopup(f.code,e));path.addEventListener('mouseleave',hidePopup);path.addEventListener('focus',()=>showPopup(f.code,null));path.addEventListener('blur',hidePopup);path.addEventListener('click',()=>pick(f.code));path.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();pick(f.code)}});svg.append(path);
  if(r.month1_episodes<250)svg.append(el('path',{d:f.path,fill:r.month1_episodes<125?'url(#hatch-low)':'url(#dots-caution)','fill-rule':'evenodd','pointer-events':'none'}));
 }
 for(const f of d.features){
  if(Math.hypot(f.center[0]-f.label[0],f.center[1]-f.label[1])>6)svg.append(el('line',{x1:f.center[0],y1:f.center[1],x2:f.label[0],y2:f.label[1],class:'leader'}));
  const text=el('text',{x:f.label[0],y:f.label[1]-(f.lines.length-1)*6.5+4,'text-anchor':'middle',class:'map-label'});f.lines.forEach((line,i)=>text.append(el('tspan',{x:f.label[0],dy:i?13:0},line)));svg.append(text);
 }
 $('mapwrap').replaceChildren(svg);$('rank').innerHTML='';
 for(const r of rows.slice(0,3)){const b=document.createElement('button');b.innerHTML='<span>'+r.area+'</span><span class="rate">'+fmt(r.probability_12)+'%</span><small>95% CI '+fmt(r.ci_low_12)+'–'+fmt(r.ci_high_12)+'% · '+count(r.month1_episodes)+' first-month exposures</small>'+(r.month1_episodes<250?'<small class="exposure-alert">'+exposureTier(r)+' exposures: interpret with caution</small>':'');b.addEventListener('click',()=>pick(r.area_code));$('rank').append(b)}
 $('rows').innerHTML='';
 for(const r of rows){const tr=document.createElement('tr');tr.dataset.code=r.area_code;const td=document.createElement('td'),b=document.createElement('button');b.textContent=r.area;b.addEventListener('click',()=>pick(r.area_code));td.append(b);tr.append(td);for(const v of [fmt(r.probability_12)+'%',r.ci_low_12==null?'Not estimated':fmt(r.ci_low_12)+'–'+fmt(r.ci_high_12)+'%',count(r.eligible_episodes),count(r.month1_episodes),count(r.observed_target_endings),exposureTier(r)]){const cell=document.createElement('td');cell.textContent=v;tr.append(cell)}$('rows').append(tr)}
 $('tabletitle').textContent='All '+rows.length+' areas · ordered by 12-month point estimate';pick(selected);
}
document.querySelectorAll('.country').forEach(b=>b.addEventListener('click',()=>{country=b.dataset.country;view='overview';selected=null;render()}));
$('geography').addEventListener('change',e=>{view=e.target.value;selected=null;render()});
$('outcome').addEventListener('change',e=>{outcome=e.target.value;selected=null;render()});
window.addEventListener('scroll',hidePopup,{passive:true});window.addEventListener('resize',hidePopup);render();
