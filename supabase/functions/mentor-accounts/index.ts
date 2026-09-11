import {createClient} from 'npm:@supabase/supabase-js@2.116.0';

const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store'};
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json'}});
const hash=async(value:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))).map(b=>b.toString(16).padStart(2,'0')).join('');
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response(null,{headers:cors});
 if(req.method!=='POST')return reply({message:'Método não permitido.'},405);
 try{
  const raw=await req.text();if(raw.length>10000)return reply({message:'Solicitação muito longa.'},413);
  const body=JSON.parse(raw),action=body.action;
  const supabase=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  if(action==='signup'||action==='request-reset'){
   const email=String(body.email||'').trim().toLowerCase();
   if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>254)return reply({message:'Informe um e-mail válido.'},400);
   const ip=req.headers.get('cf-connecting-ip')||req.headers.get('x-forwarded-for')?.split(',').at(-1)?.trim()||'unknown';
   for(const key of [action+':ip:'+ip,action+':email:'+email]){
    const {data,error}=await supabase.rpc('consume_account_limit',{bucket:await hash(key)});
    if(error)throw error;
    if(!data)return reply({message:'Muitas tentativas. Aguarde 15 minutos antes de tentar novamente.'},429);
   }
   if(action==='signup'){
    if(typeof body.password!=='string'||body.password.length<8||body.password.length>128)return reply({message:'A senha precisa ter entre 8 e 128 caracteres.'},400);
    const name=String(body.name||'').trim();if(!name||name.length>150)return reply({message:'Informe seu nome, com até 150 caracteres.'},400);
    // Accounts always start as blocked students. No email is sent or required.
    const {error}=await supabase.auth.admin.createUser({email,password:body.password,email_confirm:true,user_metadata:{name}});
    if(error)return reply({message:error.code==='email_exists'||error.message.toLowerCase().includes('already')?'Já existe um cadastro com este e-mail. Entre ou solicite recuperação ao mentor.':'Não foi possível criar o cadastro. Confira os dados ou fale com o mentor.'},400);
    return reply({created:true});
   }
   const {data:student,error}=await supabase.from('profiles').select('id').eq('email',email).eq('role','student').maybeSingle();if(error)throw error;
   if(student){const {error}=await supabase.from('password_requests').insert({student_id:student.id});if(error&&error.code!=='23505')throw error;}
   return reply({message:'Se houver cadastro de aluno, o pedido aparecerá para o mentor. Combine a nova senha com ele pelo WhatsApp.'});
  }
  // Every privileged action verifies the live user and authoritative profile.
  const jwt=req.headers.get('authorization')?.replace(/^Bearer\s+/i,'');
  if(!jwt)return reply({message:'Entre com a conta administrativa.'},401);
  const {data:{user},error:authError}=await supabase.auth.getUser(jwt);
  if(authError||!user)return reply({message:'Sessão inválida. Entre novamente.'},401);
  const {data:admin}=await supabase.from('profiles').select('role,active').eq('id',user.id).single();
  if(admin?.role!=='admin'||!admin.active)return reply({message:'Acesso restrito ao administrador.'},403);
  if(!['reset-password','delete-student'].includes(action))return reply({message:'Ação inválida.'},400);
  const {data:student}=await supabase.from('profiles').select('id,role,active').eq('id',String(body.student_id||'')).single();
  if(!student||student.role!=='student'||student.id===user.id)return reply({message:'Selecione uma conta de aluno.'},400);
  if(action==='reset-password'){
   if(typeof body.password!=='string'||body.password.length<8||body.password.length>128)return reply({message:'A senha precisa ter entre 8 e 128 caracteres.'},400);
   const {error}=await supabase.auth.admin.updateUserById(student.id,{password:body.password,email_confirm:true});if(error)throw error;
   const {error:markError}=await supabase.from('password_requests').update({resolved_at:new Date().toISOString()}).eq('student_id',student.id).is('resolved_at',null);if(markError)throw markError;
   return reply({message:'Senha atualizada. Entregue a nova senha ao aluno pelo contato combinado.'});
  }
  const {error:blockError}=await supabase.from('profiles').update({active:false}).eq('id',student.id);if(blockError)throw blockError;
  const {error}=await supabase.auth.admin.deleteUser(student.id);
  if(error){await supabase.from('profiles').update({active:student.active}).eq('id',student.id);throw error;}
  return reply({message:'Aluno e seus registros excluídos.'});
 }catch{return reply({message:'Não foi possível concluir. Confira os dados e tente novamente.'},400);}
});
