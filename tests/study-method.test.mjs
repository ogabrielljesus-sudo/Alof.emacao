import test from 'node:test';
import assert from 'node:assert/strict';
import {methodConfig,validateMethod,performanceLevel,currentDay,cycleLength,examPrintHtml} from '../dist/study-method.js';

test('limites de desempenho usam a proporção exata antes de arredondar',()=>{
 assert.equal(performanceLevel(10,8).label,'Evoluindo bem');
 assert.equal(performanceLevel(10,6).label,'Em atenção');
 assert.equal(performanceLevel(1000,599).label,'Dificuldade');
 assert.equal(performanceLevel(10000,7999).label,'Em atenção');
 assert.equal(performanceLevel(0,0).rate,null);
 assert.equal(performanceLevel(10,6,{reinforce_below:70,good_from:90}).label,'Dificuldade');
});
test('métodos são cópias independentes e aceitam intervalos e etapas personalizados',()=>{
 const a=methodConfig(),b=methodConfig();a.reviews[0].after=30;assert.equal(b.reviews[0].after,1);
 const c=methodConfig({reviews:[{id:'custom',after:30,questions:20}],flashcard:true});validateMethod(c);assert.equal(c.steps.at(-1).kind,'flashcard');
 assert.throws(()=>validateMethod({...c,good_from:50}),/limite/);
 assert.throws(()=>validateMethod({...c,reviews:[{id:'x',after:0,questions:1}]}),/intervalos/);
});
test('dia do ciclo usa o progresso do aluno e preserva dias livres no fim',()=>{
 const c={id:'c',student_id:'s',duration_days:30,start_date:'2020-01-01',blocks:[{date:'2020-01-01'}]};
 assert.equal(currentDay(c,[]),1);
 assert.equal(currentDay(c,[{student_id:'other',key:'c|position',flags:{day:10}}]),1);
 assert.equal(currentDay(c,[{student_id:'s',key:'c|position',flags:{day:4}}]),4);
 assert.equal(cycleLength(c),30);
});
test('impressão escapa conteúdo e deixa todos os comentários depois das questões',()=>{
 const text=examPrintHtml({title:'Simulado <1>',duration:10},[{subject:'Português',body:'<script>alert(1)</script>',options:['Opção A','Opção B'],correct_index:1,explanation:'Comentário exclusivo'}]);
 assert.ok(!text.includes('<script>'));
 assert.ok(text.indexOf('Opção B')<text.indexOf('Gabarito comentado'));
 assert.ok(text.indexOf('Gabarito comentado')<text.indexOf('Comentário exclusivo'));
 assert.ok(text.includes('Questão 1 · B'));
});
