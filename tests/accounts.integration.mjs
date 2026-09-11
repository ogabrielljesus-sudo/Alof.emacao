// Run explicitly with MENTORIA_ADMIN_PASSWORD. Uses and deletes one temporary account.
import assert from 'node:assert/strict';
import * as api from '../dist/api.js';
const adminEmail='alofemacao@gmail.com',adminPassword=process.env.MENTORIA_ADMIN_PASSWORD;
if(!adminPassword)throw Error('Set MENTORIA_ADMIN_PASSWORD to run the account integration check.');
const email='qa-'+crypto.randomUUID()+'@example.invalid',password='Qa'+crypto.randomUUID().replaceAll('-','').slice(0,6),nextPassword='Qb'+crypto.randomUUID().replaceAll('-','').slice(0,6);
let studentId;
const adminLogin=()=>api.login(adminEmail,adminPassword);
try{
 await adminLogin();
 await api.signup(email,password,'Teste temporário de cadastro');
 studentId=(await api.login(email,password)).id;
 assert.ok(studentId);console.log('Cadastro sem e-mail e login com 8 caracteres: OK');
 await assert.rejects(()=>api.accountAction('reset-password',{student_id:studentId,password:nextPassword}),/restrito/);
 await api.recover(email);
 await adminLogin();
 assert.ok((await api.list('password_requests','student_id=eq.'+studentId)).some(r=>!r.resolved_at));
 await api.accountAction('reset-password',{student_id:studentId,password:nextPassword});
 assert.equal((await api.login(email,nextPassword)).id,studentId);console.log('Solicitação ao mentor, bloqueio ao aluno e nova senha: OK');
}finally{
 await adminLogin();
 if(!studentId)studentId=(await api.list('profiles','email=eq.'+encodeURIComponent(email)))[0]?.id;
 if(studentId){await api.accountAction('delete-student',{student_id:studentId});assert.equal((await api.list('profiles','id=eq.'+studentId)).length,0);console.log('Exclusão da conta temporária e registros vinculados: OK');}
 await api.logout();
}
