import { createClient } from '@supabase/supabase-js';
import { readFile } from 'node:fs/promises';
import { parseEnv } from 'node:util';
Object.assign(process.env,parseEnv(await readFile('.env.local','utf8')));
const url=process.env.SUPABASE_URL;
const ref=process.env.DEV_SUPABASE_PROJECT_REF;
const isLocal=url&&['localhost','127.0.0.1'].includes(new URL(url).hostname);
const isDevelopmentCloud=url&&ref&&new URL(url).hostname===`${ref}.supabase.co`&&process.argv.includes('--confirm-development');
if(process.env.APP_ENV!=='development'||!url||(!isLocal&&!isDevelopmentCloud))throw new Error('Seed permitido sólo en desarrollo: define DEV_SUPABASE_PROJECT_REF y confirma con --confirm-development. Nunca usar staging o production.');
const key=process.env.SUPABASE_SECRET_KEY;
if(!key)throw new Error('Falta SUPABASE_SECRET_KEY del proyecto de desarrollo.');
const client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
const {data:companies,error:companyError}=await client.from('companies').select('id,code');
if(companyError||companies?.length!==2)throw new Error('Ejecuta primero las migraciones y el seed SQL del proyecto de desarrollo.');
const fixtures=[
  {email:'global@example.test',name:'Administración de prueba',members:[['SUACOF','ADMIN_GLOBAL'],['CLOUD9','ADMIN_GLOBAL']]},
  {email:'admin@example.test',name:'Administrador SUACOF',members:[['SUACOF','COMPANY_ADMIN']]},
  {email:'supervisor@example.test',name:'Supervisor ficticio',members:[['SUACOF','SUPERVISOR']]},
  {email:'suacof@example.test',name:'Trabajador SUACOF',members:[['SUACOF','EMPLOYEE']]},
  {email:'cloud9@example.test',name:'Trabajador CLOUD 9',members:[['CLOUD9','EMPLOYEE']]},
  {email:'colega@example.test',name:'Otro trabajador SUACOF',members:[['SUACOF','EMPLOYEE']]},
  {email:'multi@example.test',name:'Cuenta multiempresa',members:[['SUACOF','COMPANY_ADMIN'],['CLOUD9','HR']]},
  {email:'inactivo@example.test',name:'Acceso suspendido',members:[['SUACOF','EMPLOYEE']]}
];
const {data:existing,error:listError}=await client.auth.admin.listUsers({perPage:1000});
if(listError)throw new Error('No se pudo consultar Auth de desarrollo.');
for(const fixture of fixtures){
  let user=existing.users.find(u=>u.email===fixture.email);
  if(!user){const result=await client.auth.admin.createUser({email:fixture.email,password:'Local-Fixture-Only-2026!',email_confirm:true});if(result.error||!result.data.user)throw new Error('No se pudo crear fixture Auth.');user=result.data.user;}
  const {error:profileError}=await client.from('profiles').upsert({user_id:user.id,display_name:fixture.name});if(profileError)throw new Error('No se pudo crear perfil de prueba.');
  for(const [code,role]of fixture.members){const company=companies.find(c=>c.code===code)!;const {error}=await client.from('user_company_memberships').upsert({company_id:company.id,user_id:user.id,role_code:role,status:fixture.email==='inactivo@example.test'?'inactive':'active'},{onConflict:'company_id,user_id'});if(error)throw new Error('No se pudo crear membership de prueba.');if(role==='EMPLOYEE'){const {data:employee}=await client.from('employees').select('id').eq('company_id',company.id).eq('user_id',user.id).maybeSingle();if(!employee){const {error}=await client.from('employees').insert({company_id:company.id,user_id:user.id,display_name:fixture.name});if(error)throw new Error('No se pudo crear vínculo de prueba.');}}}
  console.log(`Fixture disponible: ${fixture.email}`);
}
console.log('Seed ficticio de desarrollo completado. Contraseña documentada en README; no usar en otros entornos.');
