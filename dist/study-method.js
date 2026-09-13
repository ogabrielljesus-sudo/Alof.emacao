import {escapeHtml as e} from './domain.js';
import {dayNumber} from './study-tools.js';

export const DEFAULT_METHOD = {
  initial_questions:10, reviews:[{id:'r1',after:1,questions:5},{id:'r2',after:3,questions:5},{id:'r3',after:7,questions:7},{id:'r4',after:14,questions:10}],
  reinforce_below:60, good_from:80, extra_enabled:true, extra_after:3, extra_questions:5,
  priority:'Alta', studied_before:false, flashcard:false, resource_id:'', video_id:'', notes:'',
  steps:[{id:'study',kind:'study',title:'Estudar teoria'},{id:'questions',kind:'questions',title:'Resolver questões'}]
};
export function methodConfig(value={}) {
  const c={...structuredClone(DEFAULT_METHOD),...structuredClone(value||{})};
  c.steps=c.steps||structuredClone(DEFAULT_METHOD.steps);
  if(c.flashcard&&!c.steps.some(s=>s.kind==='flashcard'))c.steps.push({id:'flashcard',kind:'flashcard',title:'Revisar flashcards do assunto'});
  return c;
}
export function validateMethod(c) {
  for(const k of ['initial_questions','extra_questions'])if(!Number.isInteger(c[k])||c[k]<1||c[k]>500)throw Error('Informe de 1 a 500 questões por etapa.');
  for(const k of ['reinforce_below','good_from'])if(!Number.isInteger(c[k])||c[k]<0||c[k]>100)throw Error('Os limites de desempenho devem estar entre 0 e 100.');
  if(c.reinforce_below>=c.good_from)throw Error('O limite de dificuldade deve ser menor que o de bom desempenho.');
  if(!Number.isInteger(c.extra_after)||c.extra_after<1||c.extra_after>365)throw Error('O intervalo do reforço deve ser de 1 a 365 dias.');
  if(!Array.isArray(c.reviews)||c.reviews.length>20)throw Error('Use até 20 revisões por assunto.');
  const reviewIds=new Set();
  for(const r of c.reviews){if(!r.id||reviewIds.has(r.id)||!Number.isInteger(r.after)||r.after<1||r.after>365||!Number.isInteger(r.questions)||r.questions<1||r.questions>500)throw Error('Confira os intervalos e as questões das revisões.');reviewIds.add(r.id);}
  if(!Array.isArray(c.steps)||!c.steps.length||c.steps.length>12)throw Error('Defina de 1 a 12 etapas para o assunto.');
  const ids=new Set();for(const s of c.steps){if(!s.id||ids.has(s.id)||!['study','questions','flashcard','task','summary'].includes(s.kind)||!s.title?.trim())throw Error('Confira os nomes e tipos das etapas.');ids.add(s.id);}
  return c;
}
export function performanceLevel(total,correct,c=DEFAULT_METHOD){
  if(!total)return {rate:null,label:'Sem questões',color:''};
  const rate=correct/total*100;
  return {rate:Math.round(rate*10)/10,label:rate<c.reinforce_below?'Dificuldade':rate<c.good_from?'Em atenção':'Evoluindo bem',color:rate<c.reinforce_below?'red':rate<c.good_from?'yellow':'green'};
}
export const cycleStart=c=>c.start_date||c.blocks.map(b=>b.date).sort()[0];
export const blockDay=(b,c)=>dayNumber(b.date,cycleStart(c));
export function cycleLength(c){return Math.max(c.duration_days||1,...c.blocks.map(b=>blockDay(b,c)));}
export function currentDay(c,progress){return Math.max(1,Number(progress.find(p=>p.student_id===c.student_id&&p.key===c.id+'|position')?.flags?.day)||1);}
export function topicResults(logs,studentId){
  const groups=new Map();for(const log of logs.filter(l=>l.student_id===studentId)){
    const key=log.subject+'|'+log.topic;const g=groups.get(key)||{subject:log.subject,topic:log.topic,total:0,correct:0};g.total+=Number(log.total);g.correct+=Number(log.correct);groups.set(key,g);
  }return [...groups.values()];
}
export function examPrintHtml(exam,questions){
  return `<div class="print-paper"><header><strong>Mentoria @alof.emacao</strong><h1>${e(exam.title)}</h1><p>${e(exam.description||'')}</p><p>${questions.length} questões · ${exam.duration} minutos</p><p>Nome: ____________________________________________________</p></header>${questions.map((q,i)=>`<article class="print-question"><h2>Questão ${i+1} · ${e(q.subject)}</h2><p>${e(q.body)}</p><ol type="A">${q.options.map(o=>'<li>'+e(o)+'</li>').join('')}</ol></article>`).join('')}<section class="print-key"><h1>Gabarito comentado</h1><p>${e(exam.title)} · Mentoria @alof.emacao</p>${questions.map((q,i)=>`<article class="print-answer"><h2>Questão ${i+1} · ${String.fromCharCode(65+q.correct_index)}</h2><p>${e(q.explanation)}</p></article>`).join('')}</section><footer>@alof.emacao</footer></div>`;
}
