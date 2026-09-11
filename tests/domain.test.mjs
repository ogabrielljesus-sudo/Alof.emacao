import test from 'node:test';
import assert from 'node:assert/strict';
import {suggestCycle,summarize,studentAlert,escapeHtml,safeUrl} from '../dist/domain.js';
test('períodos de 30, 60 e 365 dias distribuem somente as matérias escolhidas',()=>{for(const days of [30,60,365]){const b=suggestCycle({start:'2026-12-15',days,hours:2.25,count:2,subjects:['Direito','Português','Matemática','História']});assert.equal(b.length,days*2);assert.deepEqual(new Set(b.map(x=>x.subject)),new Set(['Direito','Português','Matemática','História']));for(let i=0;i<b.length;i+=2){assert.notEqual(b[i].subject,b[i+1].subject);assert.equal(b[i].minutes+b[i+1].minutes,135);}assert.equal(new Set(b.map(x=>x.date)).size,days);}});
test('rejeita datas inválidas, períodos fracionados e seleção que não cabe no período',()=>{const base={start:'2026-09-11',days:30,hours:3,count:1,subjects:['A','B']};for(const invalid of [{start:'2026-02-30'},{days:30.5},{days:366},{hours:NaN},{count:1.5},{days:1}])assert.throws(()=>suggestCycle({...base,...invalid}));});
test('ciclo respeita minutos diários, matérias e mudança de mês',()=>{const b=suggestCycle({start:'2026-09-30',days:3,hours:2.5,count:2,subjects:['Português','Matemática','História']});assert.equal(b.length,6);assert.equal(b[2].date,'2026-10-01');for(const d of new Set(b.map(x=>x.date)))assert.equal(b.filter(x=>x.date===d).reduce((a,b)=>a+b.minutes,0),150);assert.equal(new Set(b.map(x=>x.id)).size,6);});
test('não gera ciclo vazio nem matérias repetidas no mesmo dia',()=>{assert.throws(()=>suggestCycle({start:'2026-09-10',days:28,hours:3,count:3,subjects:['A']}));assert.throws(()=>suggestCycle({start:'2026-09-10',days:0,hours:3,count:1,subjects:[]}));});
test('aproveitamento ponderado e denominador zero',()=>{assert.deepEqual(summarize([]),{total:0,correct:0,minutes:0,rate:0});assert.equal(summarize([{total:10,correct:10,minutes:0},{total:90,correct:45,minutes:60}]).rate,55);});
test('alerta usa amostra mínima e intervalos comparáveis',()=>{const p={id:'a'};assert.equal(studentAlert(p,[],'2026-09-10'),'Sem registros');assert.equal(studentAlert(p,[{student_id:'a',date:'2026-09-01',total:10,correct:9}],'2026-09-10'),'9 dias sem registro');assert.equal(studentAlert(p,[{student_id:'a',date:'2026-09-10',total:30,correct:15},{student_id:'a',date:'2026-09-01',total:30,correct:29}],'2026-09-10'),'Queda de aproveitamento');});
test('conteúdo é escapado e links de script são bloqueados',()=>{assert.equal(safeUrl('javascript:alert(1)'),'');assert.equal(safeUrl('https://example.com'),'https://example.com/');assert.equal(escapeHtml('<script>'), '&lt;script&gt;');});
// Ciclos vinculados ao edital: criação, renovação e continuação.
import {assignTopics,renewCycle,validateCycle,syllabusKey} from '../dist/cycle-plan.js';
const topicsFixture=[{career:'CFO',subject:'Português',code:'1',title:'Ortografia'},{career:'CFO',subject:'Português',code:'2',title:'Sintaxe'}];
test('geração escolhe assuntos do edital e ignora estudo concluído',()=>{
 const progress=[{student_id:'aluno',key:'edital|CFO|Português|1',flags:{study:true}}];
 const blocks=assignTopics(suggestCycle({start:'2026-09-11',days:1,hours:1,count:1,subjects:['Português']}),topicsFixture,progress,'aluno');
 assert.equal(blocks[0].topic,'Sintaxe');validateCycle(blocks,topicsFixture);
 assert.throws(()=>validateCycle([{...blocks[0],subject:'Fora do edital'}],topicsFixture));
});
test('renovação preserva ciclo anterior e cria datas e identificadores novos',()=>{
 const blocks=assignTopics(suggestCycle({start:'2026-09-11',days:2,hours:1,count:1,subjects:['Português']}),topicsFixture,[],'aluno');
 const cycle={id:'ciclo',student_id:'aluno',blocks},before=JSON.stringify(cycle),next=renewCycle(cycle,topicsFixture);
 assert.equal(JSON.stringify(cycle),before);assert.equal(next[0].date,'2026-09-13');assert.notEqual(next[0].id,blocks[0].id);validateCycle(next,topicsFixture);
});
test('continuação traz primeiro o bloco pendente do aluno correto',()=>{
 const blocks=assignTopics(suggestCycle({start:'2026-09-11',days:2,hours:1,count:1,subjects:['Português']}),topicsFixture,[],'aluno');
 const next=renewCycle({id:'ciclo',student_id:'aluno',blocks},topicsFixture,[{student_id:'aluno',key:'ciclo|'+blocks[0].id,flags:{done:true}}],true);
 assert.equal(next[0].topic,'Sintaxe');assert.equal(next[0].topic_key,syllabusKey(topicsFixture[1]));
});
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import * as domain from '../dist/domain.js';
import * as cyclePlan from '../dist/cycle-plan.js';
test('login redesenha o painel mesmo quando o endereço já é painel/inicio',async()=>{
 const elements=new Map(),handlers={};
 const element=()=>({innerHTML:'',textContent:'',setAttribute(){},removeAttribute(){},remove(){},append(){}});
 const document={querySelector(key){if(!elements.has(key))elements.set(key,element());return elements.get(key);},addEventListener(type,fn){(handlers[type]??=[]).push(fn);},createElement:element};
 const profile={id:'admin-test',name:'Mentor',role:'admin',active:true,plan:'Estratégico',career:'CFO'};
 const context=vm.createContext({...domain,...cyclePlan,e:domain.escapeHtml,api:{configured:true,login:async()=>({id:profile.id}),list:async table=>table==='profiles'?[profile]:[]},document,location:{hash:'#painel/inicio'},window:{addEventListener(){}},setInterval(){},setTimeout(){},clearTimeout(){},FormData:class{constructor(){return new Map([['email','admin@example.invalid'],['password','fixture-only']]);}},crypto});
 const source=readFileSync(new URL('../dist/app.js',import.meta.url),'utf8').replace(/^import .*;\n/gm,'').replace(/^boot\(\);$/m,'');
 vm.runInContext(source,context);
 await handlers.submit[0]({preventDefault(){},target:{id:'auth-form',dataset:{mode:'login'},append(){}},submitter:element()});
 assert.match(elements.get('#app').innerHTML,/Alunos e acessos/);
 assert.match(elements.get('#content').innerHTML,/Sua mentoria, por inteiro/);
});
