export const escapeHtml=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function safeUrl(value){try{const u=new URL(value);return ['https:','http:'].includes(u.protocol)?u.href:'';}catch{return '';}}
export function isoDay(d=new Date()){return new Intl.DateTimeFormat('en-CA',{timeZone:'America/Bahia',year:'numeric',month:'2-digit',day:'2-digit'}).format(d);}
export function summarize(logs){const total=logs.reduce((s,r)=>s+Number(r.total),0),correct=logs.reduce((s,r)=>s+Number(r.correct),0),minutes=logs.reduce((s,r)=>s+Number(r.minutes||0),0);return {total,correct,minutes,rate:total?Math.round(correct/total*1000)/10:0};}
export function suggestCycle({start,days,hours,count,subjects}){
 if(!Array.isArray(subjects)||!subjects.length)throw Error('Selecione ao menos uma matéria para o ciclo.');
 subjects=[...new Set(subjects)];
 if(!Number.isInteger(days)||days<1||days>365)throw Error('Informe um período entre 1 e 365 dias.');
 if(!Number.isFinite(hours)||hours<=0||hours>16)throw Error('Informe até 16 horas de estudo por dia.');
 if(!Number.isInteger(count)||count<1||count>subjects.length)throw Error('A quantidade por dia deve ser entre 1 e o total de matérias selecionadas.');
 const initial=new Date(start+'T12:00:00Z');
 if(!/^\d{4}-\d{2}-\d{2}$/.test(start)||!Number.isFinite(initial.getTime())||initial.toISOString().slice(0,10)!==start)throw Error('Informe uma data inicial válida.');
 const minutes=Math.round(hours*60);
 if(minutes<count*10)throw Error('Reserve ao menos 10 minutos por matéria.');
 if(days*count<subjects.length)throw Error('Aumente os dias ou as matérias por dia para incluir todas as matérias selecionadas.');
 const blocks=[];
 for(let d=0;d<days;d++){
  const date=new Date(initial);date.setUTCDate(date.getUTCDate()+d);
  for(let i=0;i<count;i++)blocks.push({id:crypto.randomUUID(),date:date.toISOString().slice(0,10),subject:subjects[(d*count+i)%subjects.length],topic:'Definir assunto',minutes:Math.floor(minutes/count)+(i<minutes%count?1:0),notes:''});
 }
 return blocks;
}
export function studentAlert(profile,logs,today=isoDay()){const own=logs.filter(x=>x.student_id===profile.id),sorted=[...own].sort((a,b)=>b.date.localeCompare(a.date));if(!sorted.length)return 'Sem registros';const age=(Date.parse(today)-Date.parse(sorted[0].date))/86400000;if(age>=3)return `${Math.floor(age)} dias sem registro`;const end=Date.parse(today),recent=own.filter(x=>end-Date.parse(x.date)<7*86400000),previous=own.filter(x=>end-Date.parse(x.date)>=7*86400000&&end-Date.parse(x.date)<14*86400000);const a=summarize(recent),b=summarize(previous);return a.total>=20&&b.total>=20&&b.rate-a.rate>=10?'Queda de aproveitamento':'Em acompanhamento';}
