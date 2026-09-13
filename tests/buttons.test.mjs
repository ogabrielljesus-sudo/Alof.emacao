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
 const context=vm.createContext({...domain,...cycle,...study,...method,...integrated,makePdf,stampMaterial,Blob,URL,Uint8Array,TextDecoder,fetch:async()=>({ok:true,arrayBuffer:async()=>fixturePdf.buffer,headers:{get:()=> 'application/pdf'}}),e:domain.escapeHtml,api,document,window,crypto,structuredClone,FormData:FormDataMock,location:{hash:'#painel/inicio',pathname:'/'},history:{pushState(_,__,url){context.location.hash=url;},replaceState(_,__,url){context.location.hash=url;}},confirm:()=>!cancel,setTimeout(){},clearTimeout(){},setInterval(){},queueMicrotask:fn=>fn(),console});
 window.print=()=>calls.push({name:'window.print'});
 window.open=()=>({opener:null,location:{href:'about:blank'},close(){}});
 vm.runInContext(source,context);context.fixture={tables,topics,profile:profiles[role==='admin'?0:1]};vm.runInContext('state.data=fixture.tables;state.topics=fixture.topics;state.profile=fixture.profile;shell();',context);
 const run=code=>vm.runInContext(code,context);
 const view=name=>run('state.view='+JSON.stringify(name)+';state.activeQuestion=null;state.exam=null;renderView();');
 const click=async(action,attrs={})=>{let el=document.querySelector('[data-action="'+action+'"]');assert.ok(el,'Botão ausente: '+action);for(const [k,v]of Object.entries(attrs))el.dataset[k]=v;document.querySelector('#notice').textContent='';for(const fn of events.click||[])await fn({target:el,preventDefault(){}});coverage.add(action);return document.querySelector('#notice').textContent;};
 const submit=async(selector,values={})=>{const f=document.querySelector(selector);assert.ok(f,'Formulário ausente: '+selector);for(const [key,value]of Object.entries(values)){const el=f.elements[key];assert.ok(el,'Campo ausente: '+key);el.value=value;}const btn=f.querySelector('button:not([type="button"])');document.querySelector('#notice').textContent='';for(const fn of events.submit)await fn({target:f,submitter:btn,preventDefault(){}});coverage.add(selector);return document.querySelector('#notice').textContent;};
 return {run,view,click,submit,document,events,calls,setFailure:v=>failure=v,setCancel:v=>cancel=v};
}
test('editores, ciclos, seleção de dias e cancelamento respondem com notificação',async()=>{
 const t=setup();t.view('alunos');assert.match(await t.click('edit-student'),/Editor/);assert.equal(t.document.querySelector('#student-editor').dataset.scrolled,'true');
 assert.match(await t.submit('#student-form'),/Salvo/);await t.click('edit-student');assert.match(await t.submit('#admin-password-form',{password:'teste1234'}),/concluída/);
 t.view('alunos');await t.click('edit-student');t.setCancel(true);assert.match(await t.click('delete-student'),/cancelada/);t.setCancel(false);assert.match(await t.click('delete-student'),/excluído/);
 for(const action of ['edit-cycle','renew-cycle','continue-cycle']){t.view('ciclos');assert.ok(await t.click(action));}
 t.view('ciclos');assert.match(await t.click('cycle-select-all'),/selecionadas/);assert.match(await t.click('cycle-select-none'),/removida/);
 t.view('ciclos');await t.click('edit-cycle');assert.match(await t.click('remove-block'),/removido/);assert.match(await t.click('add-block'),/adicionada/);assert.match(await t.click('select-draft-day'),/selecionado/);assert.match(await t.submit('#save-cycle'),/Salvo/);
});
test('questões, caderno, comentários e simulados respondem com confirmação',async()=>{
 const t=setup();t.view('questoes');assert.match(await t.click('edit-question'),/edição/);assert.match(await t.click('open-question'),/aberta/);assert.match(await t.submit('#answer-form',{answer:'0'}),/corrigida/);assert.match(await t.submit('#note-form',{body:'Nota'}),/salvos/);
 assert.match(await t.click('clear-highlight'),/removidos/);assert.match(await t.click('question-error'),/copiada/);assert.equal(t.document.querySelector('#error-form').elements.body.value,'Questão para teste');
 const input=t.document.querySelector('#error-form').elements.body;input.selectionStart=0;input.selectionEnd=7;assert.match(await t.click('format-error'),/aplicada/);assert.match(await t.submit('#error-form'),/Salvo/);assert.match(await t.click('edit-error'),/edição/);assert.match(await t.click('review-error'),/Salvo/);
 t.view('questoes');await t.click('open-question');assert.match(await t.submit('[data-comment-question]',{body:'Comentário novo'}),/publicado/);assert.match(await t.click('delete-comment'),/apagado/);assert.match(await t.click('close-question'),/Banco/);
 t.view('simulados');assert.match(await t.click('edit-exam'),/edição/);assert.match(await t.click('compose-exam-question'),/aberto/);
 assert.match(await t.submit('#question-form',{subject:'Português',topic:'Ortografia',body:'Nova',options:'A\nB',explanation:'Explicação'}),/selecionada no simulado/);
 assert.match(await t.click('start-exam'),/iniciado/);assert.match(await t.submit('#exam-submit'),/resultado salvo/);assert.match(await t.click('close-exam'),/Lista/);assert.match(await t.click('delete-exam'),/excluído/);
});
test('gravações, filtros e erros informam resultados sem sucesso falso',async()=>{
 const t=setup();for(const [view,form,values]of [['registros','#log-form',{subject:'Português',topic:'Ortografia',source:'Livro',total:'5',correct:'3',notes:'Observação'}],['historico','#history-form',{title:'Nota',body:'Texto'}],['materiais','#resource-form',{title:'PDF',url:'https://example.com/pdf'}]]){t.view(view);assert.match(await t.submit(form,values),/Salvo/);}
 for(const [view,form]of [['edital','#edital-filter'],['desempenho','#performance-filter'],['questoes','#question-filter'],['erros','#error-filter'],['panorama','#panorama-filter']]){t.view(view);assert.match(await t.submit(form),/Filtros/);}
 t.view('registros');t.setFailure(true);assert.match(await t.submit('#log-form',{total:'3',correct:'1'}),/Falha/);assert.equal(t.document.querySelector('#notice').getAttribute('data-kind'),'error');t.setFailure(false);
 t.view('materiais');assert.match(await t.click('open-resource'),/PDF preparado/);t.view('inicio');assert.match(await t.click('logout'),/saiu/);assert.equal(await t.click('dismiss-notice'),'');
});
test('cadastro, login, recuperação, geração e publicação de simulado',async()=>{
 const t=setup();for(const mode of ['login','cadastro','recuperar','nova-senha']){t.run('authPage('+JSON.stringify(mode)+')');const values=mode==='nova-senha'?{password:'teste1234'}:mode==='recuperar'?{email:'test@example.invalid'}:mode==='cadastro'?{email:'test@example.invalid',password:'teste1234',name:'Teste'}:{email:'test@example.invalid',password:'teste1234'};assert.ok(await t.submit('#auth-form',values));assert.notEqual(t.document.querySelector('#notice').getAttribute('data-kind'),'error');}
 t.run('state.profile=fixture.profile;shell()');t.view('ciclos');await t.click('cycle-select-all');assert.match(await t.submit('#generate-cycle',{student_id:'student',count:'1'}),/gerada/);
 t.view('simulados');t.document.querySelector('[name="questions"]').checked=true;assert.match(await t.submit('#exam-form'),/salvo/);
 t.view('questoes');await t.click('open-question');const root=t.document.querySelector('#question-body');t.run('window.getSelection=()=>({rangeCount:1,isCollapsed:false,anchorNode:document.querySelector("#question-body").firstChild,focusNode:document.querySelector("#question-body").firstChild,getRangeAt:()=>({startContainer:document.querySelector("#question-body").firstChild,startOffset:0,toString:()=>"Questão",cloneRange:()=>({selectNodeContents(){},setEnd(){},toString:()=>""})}),removeAllRanges(){}})');assert.match(await t.click('highlight'),/grifado/);
});
test('botões do aluno, progresso, validação e bloqueio de pop-up',async()=>{
 const t=setup('student');t.view('ciclos');await t.click('study-open');await t.submit('#study-start-form');assert.match(await t.click('open-study-task'),/Etapa/);assert.match(await t.submit('#method-step-form'),/Etapa concluída/);assert.ok(t.calls.some(c=>c.name==='record_method_action'));
 t.view('edital');const topic=t.document.querySelector('[data-edital]');topic.checked=true;for(const fn of t.events.change)await fn({target:topic});assert.match(t.document.querySelector('#notice').textContent,/Progresso/);
 t.view('materiais');assert.match(await t.click('select-resource'),/Conteúdo aberto/);assert.ok(t.document.querySelector('.lesson-content [data-action="export-material"]'));
 for(const fn of t.events.invalid)fn({target:{validationMessage:'Preencha este campo.'}});assert.match(t.document.querySelector('#notice').textContent,/Preencha/);
});
test('edição do método preserva revisões, move o assunto e salva os valores no ciclo',async()=>{
 const t=setup();t.view('ciclos');await t.click('edit-cycle');
 assert.match(await t.click('edit-block-method'),/edição/);
 assert.ok(t.document.querySelector('#method-editor-form'));
 assert.match(await t.click('method-review-add'),/alterada/);
 assert.equal(t.document.querySelectorAll('[data-review-index]').length,5);
 assert.match(await t.click('method-review-remove',{index:'4'}),/alterada/);
 assert.match(await t.click('method-step-add'),/alterada/);
 assert.match(await t.click('method-step-up',{index:'2'}),/alterada/);
 assert.match(await t.click('method-step-down',{index:'1'}),/alterada/);
 assert.match(await t.click('method-step-remove',{index:'2'}),/alterada/);
 assert.match(await t.submit('#method-editor-form',{initial_questions:'15',move_day:'2'}),/Método aplicado/);
 assert.equal(t.run('state.draft[0].method.initial_questions'),15);
 assert.equal(t.run('state.draft[0].date'),'2026-09-13');
 await t.submit('#save-cycle');assert.equal(t.calls.find(c=>c.table==='cycles').data.blocks[0].method.initial_questions,15);
});
test('modelos, impressão, navegação dos dias e erros do servidor mostram confirmação',async()=>{
 const t=setup();t.view('metodos');assert.match(await t.click('method-template-new'),/modelo aberto/);
 assert.match(await t.submit('#method-editor-form',{name:'Modelo de teste'}),/Modelo de método salvo/);
 assert.ok(t.calls.some(c=>c.table==='method_templates'&&c.data.name==='Modelo de teste'));
 t.view('simulados');assert.match(await t.click('print-exam'),/PDF preparado/);assert.ok(t.document.querySelector('#export-dialog a[download]'));assert.match(await t.click('export-close'),/fechada/);
 const u=setup('student');u.view('ciclos');assert.match(await u.click('board-next'),/atualizados/);
 assert.match(await u.click('board-current'),/atualizados/);
 u.run('state.data.cycles[0].blocks=[];renderView()');u.setFailure(true);assert.match(await u.click('study-advance'),/Falha/);assert.equal(u.document.querySelector('#notice').dataset.kind,'error');
});
test('estudar abre duração, cronômetro e mantém o assunto ao voltar',async()=>{
 const t=setup('student');t.view('ciclos');assert.match(await t.click('study-open'),/Escolha/);assert.match(await t.submit('#study-start-form',{duration:'30',focus:'25',rest:'5'}),/Tela do assunto/);
 assert.ok(t.document.querySelector('.study-workspace'));assert.match(await t.click('timer-resume'),/iniciado/);assert.match(await t.click('timer-pause'),/pausado/);assert.match(await t.click('study-return'),/Tela/);assert.match(await t.click('timer-end'),/encerrada/);
 t.view('flashcards');assert.match(t.document.querySelector('#content').textContent,/Dia 08/);
});
test('admin cria e edita flashcards por assunto e preserva ciclo na continuação',async()=>{
 const t=setup();t.view('flashcards');assert.match(await t.submit('#flashcard-form',{front:'Pergunta?',back:'Resposta'}),/vinculado/);assert.ok(t.calls.some(c=>c.table==='flashcards'&&c.data.topic_key==='CFO|Português|1'));
 t.run('state.data.progress.push({student_id:"student",key:"cycle|position",flags:{day:8}})');t.view('ciclos');assert.match(await t.click('continue-cycle'),/Dia 08/);assert.equal(t.run('state.editCycle'),'cycle');assert.equal(t.run('state.draft[0].id'),'block');assert.equal(t.run('state.draftDay'),'2026-09-19');
});
test('navegação guiada, assinatura e organização de conteúdos preservam os controles',async()=>{
 const t=setup();t.view('alunos');await t.click('edit-student');assert.ok(t.document.querySelector('[name="subscription_start"]'));assert.ok(t.document.querySelector('[name="paid_until"]'));assert.match(await t.submit('#student-form',{subscription_start:'2026-09-01',paid_until:'2026-10-01'}),/Salvo/);assert.equal(t.calls.find(c=>c.table==='profiles').data.paid_until,'2026-10-01');
 t.view('materiais');assert.match(await t.click('edit-resource'),/edição/);assert.ok(t.document.querySelector('[name="module_name"]'));assert.ok(t.document.querySelector('[name="release_month"]'));assert.match(await t.click('cancel-resource'),/cancelada/);assert.match(await t.click('delete-resource'),/excluído/);
 const u=setup('student');u.view('inicio');assert.match(u.document.querySelector('.mobile-nav').textContent,/Hoje/);assert.match(u.document.querySelector('.mobile-nav').textContent,/Mais/);assert.match(u.document.querySelector('#content').textContent,/Continue de onde parou/);u.view('mais');assert.match(u.document.querySelector('#content').textContent,/Edital verticalizado/);assert.match(u.document.querySelector('#content').textContent,/Simulados/);u.view('revisoes');assert.match(u.document.querySelector('#content').textContent,/Tudo o que precisa ser retomado/);u.view('materiais');assert.match(u.document.querySelector('#content').textContent,/Módulo geral/);
});
test('inventário de controles revisados',()=>{console.log('Controles exercitados:',[...coverage].sort().join(', '));assert.ok(coverage.size>=48);});
