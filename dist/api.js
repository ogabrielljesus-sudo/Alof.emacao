import {config} from './config.js';
export const configured=Boolean(config.supabaseUrl&&config.supabaseKey);
let token='', refreshToken='';
export function clearSession(){token='';refreshToken='';}
export function setSession(session){token=session.access_token||'';refreshToken=session.refresh_token||'';}
async function request(path,options={},retry=true){
 if(!configured)throw Error('Conecte o Supabase para ativar cadastros e salvar dados reais.');
 const response=await fetch(config.supabaseUrl.replace(/\/$/,'')+path,{...options,headers:{apikey:config.supabaseKey,...(token?{Authorization:`Bearer ${token}`} : {}),...(options.body instanceof Blob?{}:{'Content-Type':'application/json'}),...options.headers}});
 if(response.status===401&&refreshToken&&retry){const r=await request('/auth/v1/token?grant_type=refresh_token',{method:'POST',body:JSON.stringify({refresh_token:refreshToken})},false);setSession(r);return request(path,options,false);}
 const raw=await response.text();let data;try{data=raw?JSON.parse(raw):null;}catch{data=null;}
 if(!response.ok)throw Error(data?.msg||data?.message||data?.error_description||`Não foi possível concluir (${response.status}).`);
 return data;
}
export async function login(email,password){const session=await request('/auth/v1/token?grant_type=password',{method:'POST',body:JSON.stringify({email,password})});setSession(session);return session.user;}
export const accountAction=(action,data={})=>request('/functions/v1/mentor-accounts',{method:'POST',body:JSON.stringify({action,...data})});
export const signup=(email,password,name)=>accountAction('signup',{email,password,name});
export const recover=email=>accountAction('request-reset',{email});
export const changePassword=password=>request('/auth/v1/user',{method:'PUT',body:JSON.stringify({password})});
export async function logout(){try{await request('/auth/v1/logout',{method:'POST'});}finally{clearSession();}}
export const rpc=(name,args={})=>request('/rest/v1/rpc/'+name,{method:'POST',body:JSON.stringify(args)});
export async function list(table,query=''){let out=[],offset=0;for(;;){const rows=await request(`/rest/v1/${table}?select=*&${query}&limit=1000&offset=${offset}`);out.push(...rows);if(rows.length<1000)return out;offset+=1000;}}
export const save=(table,data,id)=>request('/rest/v1/'+table+(id?'?id=eq.'+encodeURIComponent(id):''),{method:id?'PATCH':'POST',headers:{Prefer:'return=representation'},body:JSON.stringify(data)});
export const upsert=(table,data,conflict)=>request('/rest/v1/'+table+'?on_conflict='+conflict,{method:'POST',headers:{Prefer:'resolution=merge-duplicates,return=representation'},body:JSON.stringify(data)});
export const remove=(table,id)=>request('/rest/v1/'+table+'?id=eq.'+encodeURIComponent(id),{method:'DELETE'});
export async function upload(file){if(file.size>50*1024*1024)throw Error('Use arquivos de até 50 MB ou cadastre o vídeo por link.');const path=crypto.randomUUID()+'/'+file.name.replace(/[^a-zA-Z0-9._-]/g,'_');await request('/storage/v1/object/materials/'+path,{method:'POST',headers:{'Content-Type':file.type||'application/octet-stream'},body:file});return path;}
export async function assetUrl(path){const r=await request('/storage/v1/object/sign/materials/'+path,{method:'POST',body:JSON.stringify({expiresIn:300})});return config.supabaseUrl.replace(/\/$/,'')+'/storage/v1'+r.signedURL;}
