import * as mentoring from '../dist/mentoring.js';
// Run with BUTTON_QA_MODULE pointing to an installed linkedom module.
import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import * as domain from '../dist/domain.js';
import * as cycle from '../dist/cycle-plan.js';
import * as study from '../dist/study-tools.js';
import * as method from '../dist/study-method.js';
import * as integrated from '../dist/study-state.js';
import {makePdf,stampMaterial,setExportFont} from '../dist/pdf-export.js';
setExportFont(new Uint8Array(readFileSync(new URL('../dist/vendor/DejaVuSans.ttf',import.meta.url))));
const fixturePdf=await makePdf({title:'Material',sections:[{lines:['Material de teste']}]});
const {parseHTML}=await import(process.env.BUTTON_QA_MODULE);
const uiSource=readFileSync(new URL('../dist/method-ui.js',import.meta.url),'utf8').replace(/^import .*;\n/gm,'').replace('export function createMethodUI','function createMethodUI');
const additional=['study-space','exports'].map(n=>readFileSync(new URL('../dist/'+n+'.js',import.meta.url),'utf8').replace(/^import .*;\n/gm,'').replace(/export function /g,'function ')).join('\n');
const source=additional+'\n'+uiSource+'\n'+readFileSync(new URL('../dist/app.js',import.meta.url),'utf8').replace(/^import .*;\n/gm,'').replace(/^boot\(\);$/m,'');
const topics=[{career:'CFO',subject:'Português',code:'1',title:'Ortografia'}];
const coverage=new Set();
function setup(role='admin'){
 const {document,window:domWindow}=parseHTML('<html><body><div id="app"></div><div id="notice"></div></body></html>'),events={};
 const window={HTMLElement:domWindow.HTMLElement,HTMLTextAreaElement:domWindow.HTMLTextAreaElement};
 Object.defineProperty(domWindow.HTMLSelectElement.prototype,'value',{configurable:true,get(){return this.querySelector('option[selected]')?.getAttribute('value')||this.querySelector('option')?.getAttribute('value')||'';},set(value){for(const option of this.querySelectorAll('option')){if(option.getAttribute('value')===String(value))option.setAttribute('selected','');else option.removeAttribute('selected');}}});
 document.addEventListener=(type,fn)=>(events[type]??=[]).push(fn);
 window.addEventListener=()=>{};
 window.HTMLElement.prototype.scrollIntoView=function(){this.dataset.scrolled='true';};
 window.HTMLElement.prototype.focus=function(){};
 Object.defineProperty(window.HTMLElement.prototype,'elements',{configurable:true,get(){const form=this;return new Proxy({},{get(_,key){return form.querySelector('[name="'+String(key)+'"]');}});}});
 window.HTMLElement.prototype.reset=function(){};
 window.HTMLTextAreaElement.prototype.setRangeText=function(value,start,end){this.value=this.value.slice(0,start)+value+this.value.slice(end);};
 const profiles=[{id:'mentor',name:'Mentor',role:'admin',active:true,plan:'Estratégico',career:'CFO'},{id:'student',name:'Aluno',email:'test@example.invalid',role:'student',active:true,plan:'Estratégico',career:'CFO'}];
 const blocks=[{id:'block',date:'2026-09-12',subject:'Português',topic:'Ortografia',topic_key:'CFO|Português|1',minutes:60,notes:''}];
 const q={id:'question',subject:'Português',topic:'Ortografia',body:'Questão para teste',options:['A','B'],difficulty:'Média',year:2026};
 const tables={profiles,cycles:[{id:'cycle',student_id:'student',title:'Ciclo',notes:'',blocks,status:'Publicado',start_date:'2026-09-12'}],questions:[q],progress:[],study_logs:[],history:[],question_notes:[],resource_views:[],exam_attempts:[],password_requests:[],errors:[{id:'error',student_id:role==='admin'?'mentor':'student',subject:'Português',topic:'Ortografia',reason:'Desatenção',body:'Erro',explanation:'Rever',reviewed:false}],resources:[{id:'resource',title:'PDF',url:'https://example.com/file.pdf',kind:'Material',subject:'Português'}],exams:[{id:'exam',title:'Simulado 1',duration:10,question_ids:['question'],description:''}],method_studies:[],method_reviews:[],study_sessions:[],cycle_days:[],flashcards:[],flashcard_runs:[],topic_events:[],method_templates:[],question_comments:[{id:'comment',student_id:'student',question_id:'question',body:'Comentário',created_at:new Date().toISOString()}]};
 const calls=[];let failure=false,cancel=false;
 const api={configured:true,login:async()=>({id:role==='admin'?'mentor':'student'}),signup:async()=>({created:true}),recover:async()=>({message:'Pedido enviado ao administrador.'}),changePassword:async()=>{},clearSession(){},logout:async()=>{},list:async table=>tables[table]||[],save:async(table,data,id)=>{if(failure)throw Error('Falha de teste ao salvar');calls.push({table,data,id});return [{id:id||'new',...data}];},upsert:async(...args)=>api.save(...args),remove:async(table,id)=>{if(failure)throw Error('Falha de teste ao excluir');calls.push({table,id});tables[table]=tables[table].filter(x=>x.id!==id);},accountAction:async()=>({message:'Ação administrativa concluída.'}),rpc:async(name,args)=>{if(failure)throw Error('Falha de teste');calls.push({name,args});if(name==='study_timer'){const existing=tables.study_sessions[0];const s=existing||{id:'session',student_id:'student',cycle_id:'cycle',block_id:'block',subject:'Português',topic:'Ortografia',target_seconds:1800,focus_seconds:1500,break_seconds:300,focused_seconds:0,phase_seconds:0,phase:'focus',status:'paused'};if(args.payload.action==='resume')s.status='running';if(args.payload.action==='pause')s.status='paused';if(args.payload.action==='end')s.status='ended';tables.study_sessions=[s];return s;}if(name==='advance_method_day')return {day:2,message:'Próximo dia liberado.'};if(name==='save_question')return 'new-question';if(name==='get_exam_print')return {exam:tables.exams[0],questions:[{...q,correct_index:0,explanation:'Explicação para imprimir'}]};if(name==='start_exam')return {id:'attempt',deadline:new Date(Date.now()+600000).toISOString()};if(name==='submit_exam')return {score:1,total:1,details:[{question_id:'question',correct:true,correct_index:0,explanation:'Comentário do gabarito'}]};return {correct:true,correct_index:0,explanation:'Comentário do gabarito'};},upload:async()=> 'file',assetUrl:async()=> 'https://example.com/file.pdf'};
 class FormDataMock extends Map{constructor(form){super();this.all={};for(const el of form.querySelectorAll('input,select,textarea')){if(!el.name||el.disabled||['checkbox','radio'].includes(el.type)&&!el.checked)continue;const value=el.value||'';this.set(el.name,value);(this.all[el.name]??=[]).push(value);}}getAll(key){return this.all[key]||[];}}
 const context=vm.createContext({...domain,...cycle,...study,...method,...integrated,...mentoring,makePdf,stampMaterial,Blob,URL,Uint8Array,TextDecoder,fetch:async()=>({ok:true,arrayBuffer:async()=>fixturePdf.buffer,headers:{get:()=> 'application/pdf'}}),e:domain.escapeHtml,api,document,window,crypto,structuredClone,FormData:FormDataMock,location:{hash:'#painel/inicio',pathname:'/'},history:{pushState(_,__,url){context.location.hash=url;},replaceState(_,__,url){context.location.hash=url;}},confirm:()=>!cancel,setTimeout(){},clearTimeout(){},setInterval(){},queueMicrotask:fn=>fn(),console});
 window.print=()=>calls.push({name:'window.print'});
 window.open=()=>({opener:null,location:{href:'about:blank'},close(){}});
 vm.runInContext(source,context);context.fixture={tables,topics,profile:profiles[role==='admin'?0:1]};vm.runInContext('state.data=fixture.tables;state.topics=fixture.topics;state.profile=fixture.profile;shell();',context);
 const run=code=>vm.runInContext(code,context);
 const view=name=>run('state.view='+JSON.stringify(name)+';state.activeQuestion=null;state.exam=null;renderView();');
 const click=async(action,attrs={})=>{let el=document.querySelector('[data-action="'+action+'"]');assert.ok(el,'Botão ausente: '+action);for(const [k,v]of Object.entries(attrs))el.dataset[k]=v;document.querySelector('#notice').textContent='';for(const fn of events.click||[])await fn({target:el,preventDefault(){}});coverage.add(action);return document.querySelector('#notice').textContent;};
 const submit=async(selector,values={})=>{const f=document.querySelector(selector);assert.ok(f,'Formulário ausente: '+selector);for(const [key,value]of Object.entries(values)){const el=f.elements[key];assert.ok(el,'Campo ausente: '+key);el.value=value;}const btn=f.querySelector('button:not([type="button"])');document.querySelector('#notice').textContent='';for(const fn of events.submit)await fn({target:f,submitter:btn,preventDefault(){}});coverage.add(selector);return document.querySelector('#notice').textContent;};
 return {run,view,click,submit,document,events,calls,setFailure:v=>failure=v,setCancel:v=>cancel=v};
}

test('navegação e edições silenciosas; adições e exclusões têm uma confirmação',async()=>{
 const t=setup();t.view('alunos');assert.equal(await t.click('edit-student'),'');assert.ok(t.document.querySelector('#student-form'));assert.equal(await t.submit('#student-form',{paid_until:'2026-10-01'}),'');assert.equal(t.calls.find(c=>c.table==='profiles').data.paid_until,'2026-10-01');
 await t.click('edit-student');assert.equal(await t.submit('#admin-password-form',{password:'teste1234'}),'');
 t.view('alunos');await t.click('edit-student');t.setCancel(true);assert.equal(await t.click('delete-student'),'');t.setCancel(false);assert.match(await t.click('delete-student'),/excluído/);
 t.view('registros');assert.match(await t.submit('#log-form',{subject:'Português',topic:'Ortografia',source:'Livro',total:'5',correct:'3'}),/adicionado/);assert.equal(t.calls.find(c=>c.table==='study_logs').data.correct,3);
 t.view('desempenho');assert.equal(await t.submit('#performance-filter'),'');
 t.view('registros');t.setFailure(true);assert.equal(await t.submit('#log-form',{total:'3',correct:'1'}),'');assert.match(t.document.querySelector('.action-error').textContent,/Falha/);
});
test('menus, painéis e rotas antigas não apresentam funções removidas',()=>{
 for(const role of ['admin','student']){const t=setup(role);for(const view of ['inicio','mais','alunos','edital','panorama','desempenho','revisoes','dificuldades','historico','flashcards','erros']){t.view(view);assert.doesNotMatch(t.document.querySelector('#content').textContent,/flashcard|caderno de erros/i);assert.equal(t.document.querySelector('[data-action="question-error"]'),null);}}
});
test('criar, continuar, renovar e editar método preservam o plano',async()=>{
 const t=setup();for(const a of ['edit-cycle','renew-cycle','continue-cycle']){t.view('ciclos');await t.click(a);assert.ok(t.document.querySelector('#save-cycle'));}
 await t.click('edit-block-method');await t.click('method-step-add');await t.click('method-step-up',{index:'2'});await t.click('method-step-down',{index:'1'});await t.click('method-step-remove',{index:'2'});await t.submit('#method-editor-form',{initial_questions:'15',move_day:'2'});assert.equal(t.run('state.draft[0].method.initial_questions'),15);assert.equal(t.run('state.draft[0].date'),'2026-09-13');await t.submit('#save-cycle');assert.equal(t.calls.find(c=>c.table==='cycles').data.blocks[0].method.initial_questions,15);
 t.run('state.data.progress.push({student_id:"student",key:"cycle|position",flags:{day:8}})');t.view('ciclos');await t.click('continue-cycle');assert.equal(t.run('state.editCycle'),'cycle');assert.equal(t.run('state.draftDay'),'2026-09-19');
});
test('questões, comentários, simulados e impressão mantêm seus controles',async()=>{
 const t=setup();t.view('questoes');await t.click('edit-question');await t.click('open-question');assert.equal(await t.submit('#answer-form',{answer:'0'}),'');assert.match(t.document.querySelector('#question-result').textContent,/correta/);await t.submit('#note-form',{body:'Nota'});assert.ok(t.calls.some(c=>c.table==='question_notes'));await t.click('clear-highlight');
 assert.match(await t.submit('[data-comment-question]',{body:'Novo comentário'}),/adicionado/);assert.match(await t.click('delete-comment'),/apagado/);await t.click('close-question');
 t.view('simulados');await t.click('edit-exam');await t.click('compose-exam-question');assert.match(await t.submit('#question-form',{subject:'Português',topic:'Ortografia',body:'Nova',options:'A\nB',explanation:'Comentário'}),/adicionada/);assert.equal(t.run('state.examDraft.question_ids.at(-1)'),'new-question');
 await t.click('print-exam');assert.ok(t.document.querySelector('#export-dialog a[download]'));await t.click('export-close');await t.click('start-exam');await t.submit('#exam-submit');assert.ok(t.calls.some(c=>c.name==='submit_exam'));await t.click('close-exam');assert.match(await t.click('delete-exam'),/excluído/);
});
test('simulado bloqueia a questão 81 na seleção, no formulário e no cadastro integrado',async()=>{
 const t=setup();t.run('state.data.questions=Array.from({length:81},(_,i)=>({...state.data.questions[0],id:"q"+i}));');t.view('simulados');const boxes=[...t.document.querySelectorAll('[name="questions"]')];boxes.forEach(b=>b.checked=true);for(const fn of t.events.change)await fn({target:boxes[80]});assert.equal(boxes[80].checked,false);assert.match(t.document.querySelector('.action-error').textContent,/máximo 80 questões/);
 await t.click('compose-exam-question');assert.equal(t.document.querySelector('#question-form'),null);boxes[80].checked=true;await t.submit('#exam-form',{career:'CFO'});assert.ok(!t.calls.some(c=>c.table==='exams'));boxes[80].checked=false;assert.match(await t.submit('#exam-form',{career:'CFO'}),/adicionado/);assert.equal(t.calls.find(c=>c.table==='exams').data.question_ids.length,80);
});
test('estudo e revisão sincronizam por RPC e cronômetro permanece no assunto',async()=>{
 const t=setup('student');t.view('ciclos');await t.click('study-open');await t.submit('#study-start-form',{duration:'30',focus:'25',rest:'5'});assert.ok(t.document.querySelector('.study-workspace'));await t.click('timer-resume');await t.click('timer-pause');await t.click('study-return');await t.click('open-study-task');await t.submit('#method-step-form');assert.ok(t.calls.some(c=>c.name==='record_method_action'));await t.click('timer-end');assert.equal(t.run('state.data.study_sessions[0].status'),'ended');
 t.run('state.data.method_studies.push({id:"s",student_id:"student",cycle_id:"cycle",subject:"Português",topic:"Ortografia",topic_key:"CFO|Português|1"});state.data.method_reviews.push({id:"due",student_id:"student",cycle_id:"cycle",study_id:"s",status:"pending",due_day:1,questions:5})');t.view('inicio');assert.ok(t.document.querySelector('[data-action="open-review"]'));await t.click('open-review');await t.submit('#review-result-form',{total:'5',correct:'4'});assert.ok(t.calls.some(c=>c.name==='record_method_action'&&c.args.payload.action==='review'));
});
test('conteúdos continuam organizados por módulo e ligados ao histórico',async()=>{
 const t=setup('student');t.run('state.data.resources[0].topic_key="CFO|Português|1";state.data.resources[0].module_name="Módulo 2";state.data.resources[0].position=1;state.data.resources.push({...state.data.resources[0],id:"next",title:"Exercícios",position:2},{...state.data.resources[0],id:"ten",module_name:"Módulo 10"})');t.view('materiais');await t.click('select-resource',{id:'resource'});assert.ok(t.document.querySelector('.lesson-pagination [data-id="next"]'));await t.click('topic-history');assert.match(t.document.querySelector('#study-dialog').textContent,/Ortografia/);assert.deepEqual([...t.document.querySelectorAll('.module-title strong')].map(x=>x.textContent),['Módulo 2','Módulo 10']);
});
test('cards do mentor abrem detalhes e dificuldades abrem histórico do assunto',async()=>{
 const t=setup();t.run('state.data.study_logs.push({id:"log",student_id:"student",date:"2026-09-13",created_at:"2026-09-13T12:00:00Z",subject:"Português",topic:"Ortografia",topic_key:"CFO|Português|1",total:10,correct:5,minutes:0});');t.view('inicio');assert.ok(t.document.querySelector('.mentor-student'));assert.equal(t.document.querySelector('table'),null);assert.match(t.document.querySelector('#content').textContent,/50%/);await t.click('edit-student');assert.match(t.document.querySelector('#student-editor').textContent,/10 questões/);t.view('dificuldades');await t.click('topic-history');assert.match(t.document.querySelector('#study-dialog').textContent,/5 erros/);
});
test('autenticação, recuperação e geração permanecem operacionais',async()=>{
 const t=setup();for(const mode of ['login','cadastro','recuperar','nova-senha']){t.run('authPage('+JSON.stringify(mode)+')');const values=mode==='nova-senha'?{password:'teste1234'}:mode==='recuperar'?{email:'test@example.invalid'}:mode==='cadastro'?{email:'test@example.invalid',password:'teste1234',name:'Teste'}:{email:'test@example.invalid',password:'teste1234'};await t.submit('#auth-form',values);assert.equal(t.document.querySelector('.action-error'),null);}
 t.run('state.profile=fixture.profile;shell()');t.view('ciclos');await t.click('cycle-select-all');await t.submit('#generate-cycle',{student_id:'student',count:'1'});assert.ok(t.document.querySelector('#save-cycle'));
});
test('inventário de controles exercitados',()=>console.log([...coverage].sort().join(', ')));
