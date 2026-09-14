import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {sessionClock,visibleSteps,dayTasks} from '../dist/study-state.js';
import {extendCycle} from '../dist/cycle-plan.js';
import {makePdf,stampMaterial,setExportFont} from '../dist/pdf-export.js';
import {PDFDocument,PDFName} from '../dist/vendor/pdf-lib.js';
const c={id:'c',student_id:'s',start_date:'2026-01-01',duration_days:8,blocks:[{id:'b',date:'2026-01-01',subject:'Matemática',topic:'MMC',topic_key:'CFO|Matemática|1',minutes:45,notes:'Orientação',method:{reviews:[],steps:[{id:'study',kind:'study',title:'Teoria'},{id:'flash',kind:'flashcard',title:'Flashcards'}]}}]};
const d={profiles:[{id:'s',plan:'Estratégico'}],progress:[{student_id:'s',key:'c|position',flags:{day:8}}],method_studies:[{id:'ms',student_id:'s',cycle_id:'c',block_id:'b',topic_key:'CFO|Matemática|1',config:{flashcard:true},studied_day:1,studied_at:'2026-01-01',flags:{study:true}}],method_reviews:[],flashcards:[{topic_key:'CFO|Matemática|1',review_keys:['r3']}],flashcard_runs:[]};
test('relógio exclui descanso, limita ausência e para no fim da etapa',()=>{
 const s={status:'running',phase:'focus',focus_seconds:60,break_seconds:10,target_seconds:600,focused_seconds:55,phase_seconds:55};
 assert.deepEqual(sessionClock(s,20000,0),{focused:60,remaining:0,goal:540});
 assert.equal(sessionClock({...s,phase:'break',phase_seconds:0},10000,0).focused,55);
 assert.equal(sessionClock({...s,status:'paused'},10000,0).focused,55);
 assert.equal(sessionClock({...s,phase_seconds:0,focused_seconds:0,focus_seconds:1500},1000000,0).focused,30);
});
test('etapas removidas não bloqueiam alunos antigos em nenhuma semana',()=>{
 assert.equal(visibleSteps(c,c.blocks[0],d).length,1);
 const b={...c.blocks[0],date:'2026-01-08'};assert.equal(visibleSteps(c,b,d).length,1);
 assert.equal(visibleSteps(c,b,{...d,method_studies:[]}).length,1);
 assert.equal(visibleSteps(c,b,{...d,flashcards:[]}).length,1);
 assert.equal(visibleSteps(c,b,{...d,profiles:[{id:'s',plan:'Básico'}]}).length,1);
});
test('progresso do dia não soma de novo tarefas já concluídas nos dias anteriores',()=>{
 assert.equal(dayTasks(c,d).length,0);
 const reviews=[{id:'r',study_id:'ms',cycle_id:'c',review_key:'r3',due_day:8,status:'completed'}];
 const tasks=dayTasks(c,{...d,method_reviews:reviews});assert.equal(tasks.length,1);assert.equal(tasks.filter(t=>t.done).length,1);
});
test('ampliação mantém identificadores, ordem por dia e configuração do mentor',()=>{
 const cycle={...c,duration_days:2,blocks:[c.blocks[0],{...c.blocks[0],id:'b2',date:'2026-01-02',topic:'Frações',topic_key:'CFO|Matemática|2',minutes:90}]};
 const topics=['MMC','Frações','Porcentagem','Regra de três'].map((title,i)=>({career:'CFO',subject:'Matemática',code:String(i+1),title}));
 const result=extendCycle(cycle,2,topics,[]);assert.deepEqual(result.blocks.slice(0,2),cycle.blocks);assert.equal(result.blocks[2].topic,'Porcentagem');assert.equal(result.blocks[3].topic,'Regra de três');assert.equal(result.blocks[3].minutes,90);assert.deepEqual(result.blocks[2].method,cycle.blocks[0].method);assert.equal(result.duration_days,4);assert.throws(()=>extendCycle(cycle,365,topics));
});
test('PDF multipágina mantém uma única marca por página mesmo ao exportar novamente',async()=>{
 setExportFont(new Uint8Array(readFileSync(new URL('../dist/vendor/DejaVuSans.ttf',import.meta.url))));
 const pdf=await makePdf({title:'Questões de Matemática',sections:[{title:'MMC e MDC',lines:Array.from({length:100},(_,i)=>'Questão '+(i+1)+' · Calcule √16 + 2². Acentuação: café, órgão e ação.')},{title:'Gabarito comentado',breakBefore:true,lines:['A resposta é 8.']}]});
 const doc=await PDFDocument.load(pdf);assert.ok(doc.getPageCount()>2);assert.ok(doc.getPages().every(p=>p.node.get(PDFName.of('AlofWatermarked'))));
 const before=doc.getPages().map(p=>p.node.Contents().size());
 const again=await PDFDocument.load(await stampMaterial(pdf));assert.deepEqual(again.getPages().map(p=>p.node.Contents().size()),before);
});
