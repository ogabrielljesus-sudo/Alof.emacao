export const syllabusKey=t=>[t.career,t.subject,t.code].join('|');
export function assignTopics(blocks,topics,progress=[],studentId,previous=null){
 const studied=new Set(progress.filter(p=>p.student_id===studentId&&p.flags?.study).map(p=>p.key.replace(/^edital\|/,'')));
 const done=new Set(progress.filter(p=>p.student_id===studentId&&p.flags?.done).map(p=>p.key));
 const pending=previous?(previous.blocks||[]).filter(b=>!done.has(previous.id+'|'+b.id)):[];
 const completed=new Set(previous?(previous.blocks||[]).filter(b=>done.has(previous.id+'|'+b.id)).map(b=>b.topic_key):[]);
 const used=new Set();
 return blocks.map(b=>{
  const available=topics.filter(t=>t.subject===b.subject);
  if(!available.length)throw Error('Matéria fora do edital do aluno: '+b.subject);
  const index=pending.findIndex(p=>p.subject===b.subject&&!studied.has(p.topic_key));
  const old=index>=0?pending.splice(index,1)[0]:null;
  let t=old&&available.find(t=>syllabusKey(t)===old.topic_key||t.title===old.topic);
  if(!t)t=available.find(t=>!studied.has(syllabusKey(t))&&!completed.has(syllabusKey(t))&&!used.has(syllabusKey(t)));
  const review=!t;
  t=t||available.find(t=>!used.has(syllabusKey(t)))||available[0];
  used.add(syllabusKey(t));
  return {...b,topic:t.title,topic_key:syllabusKey(t),notes:old?.notes||(review?'Revisão: confira a prioridade antes de publicar.':b.notes)};
 });
}
export function nextStart(blocks){const last=blocks.map(b=>b.date).sort().at(-1);if(!last)throw Error('O ciclo anterior não tem datas.');const d=new Date(last+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+1);return d.toISOString().slice(0,10);}
export function renewCycle(cycle,topics,progress=[],continuePending=false){
 const dates=[...new Set(cycle.blocks.map(b=>b.date))].sort(),start=nextStart(cycle.blocks);
 const offset=(Date.parse(start)-Date.parse(dates[0]))/86400000;
 const blocks=cycle.blocks.map(b=>({...b,id:crypto.randomUUID(),date:new Date(Date.parse(b.date)+offset*86400000).toISOString().slice(0,10)}));
 return assignTopics(blocks,topics,progress,cycle.student_id,continuePending?cycle:null);
}
export function validateCycle(blocks,topics){
 if(!blocks.length)throw Error('Adicione ao menos um bloco.');
 const totals=new Map(),subjects=new Set();
 for(const b of blocks){
  if(!/^\d{4}-\d{2}-\d{2}$/.test(b.date)||!Number.isFinite(Date.parse(b.date))||new Date(b.date).toISOString().slice(0,10)!==b.date)throw Error('Confira as datas do ciclo.');
  if(!Number.isInteger(b.minutes)||b.minutes<1||b.minutes>960)throw Error('Informe de 1 a 960 minutos por bloco.');
  const follows=b.topic_key==='follow'&&b.topic==='Seguir edital verticalizado'&&topics.some(t=>t.subject===b.subject);
  if(!follows&&!topics.some(t=>t.subject===b.subject&&syllabusKey(t)===b.topic_key&&t.title===b.topic))throw Error('Selecione um assunto do edital em cada bloco.');
  const pair=b.date+'|'+b.subject;if(subjects.has(pair))throw Error('Escolha matérias diferentes em cada bloco do mesmo dia.');subjects.add(pair);
  totals.set(b.date,(totals.get(b.date)||0)+b.minutes);
 }
 if([...totals.values()].some(n=>n>960))throw Error('Cada dia pode ter até 16 horas de estudo.');
}
// Append to the same cycle so existing block IDs, results and review schedules stay intact.
export function extendCycle(cycle,days,topics,progress=[]){
 const start=cycle.start_date||cycle.blocks.map(b=>b.date).sort()[0];
 const relative=b=>Math.round((Date.parse(b.date)-Date.parse(start))/86400000)+1;
 const length=Math.max(cycle.duration_days||1,...cycle.blocks.map(relative));
 if(!Number.isInteger(days)||days<1||length+days>365)throw Error('A continuação deve manter o ciclo dentro de 365 dias.');
 const alreadyScheduled=cycle.blocks.map(b=>({student_id:cycle.student_id,key:'edital|'+b.topic_key,flags:{study:true}}));
 const pattern=[];for(let d=0;d<days;d++){const sourceDay=d%length+1;for(const b of cycle.blocks.filter(b=>relative(b)===sourceDay))pattern.push({...structuredClone(b),id:crypto.randomUUID(),date:new Date(Date.parse(start)+(length+d)*86400000).toISOString().slice(0,10)});}
 const additional=assignTopics(pattern,topics,[...progress,...alreadyScheduled],cycle.student_id);
 return {blocks:[...structuredClone(cycle.blocks),...additional],duration_days:length+days,first_day:length+1};
}
