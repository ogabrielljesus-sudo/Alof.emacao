import {writeFile} from 'node:fs/promises';
import {config} from '../dist/config.js';
const hasOverride=Boolean(process.env.SUPABASE_URL||process.env.SUPABASE_PUBLISHABLE_KEY);
const supabaseUrl=hasOverride?process.env.SUPABASE_URL||'':config.supabaseUrl;
const supabaseKey=hasOverride?process.env.SUPABASE_PUBLISHABLE_KEY||'':config.supabaseKey;
if(supabaseKey.startsWith('sb_secret_'))throw Error('Use a chave publicável, nunca uma chave secreta.');
if(supabaseKey.startsWith('eyJ')){try{const payload=JSON.parse(Buffer.from(supabaseKey.split('.')[1],'base64url').toString());if(payload.role!=='anon')throw Error('Chave não publicável.');}catch{throw Error('Use uma chave publicável/anon válida, nunca service_role.');}}
if(supabaseUrl&&!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(supabaseUrl))throw Error('SUPABASE_URL deve ser a URL HTTPS do projeto Supabase.');
if(Boolean(supabaseKey)!==Boolean(supabaseUrl))throw Error('Defina as duas variáveis do Supabase.');
await writeFile(new URL('../dist/config.js',import.meta.url),'// Public configuration only.\nexport const config = '+JSON.stringify({supabaseUrl,supabaseKey})+';\n');
console.log(supabaseUrl?'Integração Supabase configurada.':'Prévia: Supabase ainda não configurado.');
