import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
export const A='10000000-0000-4000-8000-000000000001';
export const B='10000000-0000-4000-8000-000000000002';
export const U={global:'20000000-0000-4000-8000-000000000001',admin:'20000000-0000-4000-8000-000000000002',employeeA:'20000000-0000-4000-8000-000000000003',employeeB:'20000000-0000-4000-8000-000000000004',colleague:'20000000-0000-4000-8000-000000000005',multi:'20000000-0000-4000-8000-000000000006',inactive:'20000000-0000-4000-8000-000000000007',supervisor:'20000000-0000-4000-8000-000000000008'};
export const E={a:'30000000-0000-4000-8000-000000000001',b:'30000000-0000-4000-8000-000000000002',colleague:'30000000-0000-4000-8000-000000000003'};
export async function database(){
  const db=new PGlite();
  await db.exec(`create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls; create schema auth; create table auth.users(id uuid primary key); create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$; grant usage on schema public,auth to anon,authenticated,service_role; grant execute on function auth.uid() to anon,authenticated,service_role;`);
  for(const file of (await readdir('supabase/migrations')).filter(f=>f.endsWith('.sql')).sort())await db.exec(await readFile(`supabase/migrations/${file}`,'utf8'));
  await db.exec(await readFile('supabase/seed.sql','utf8'));
  for(const [label,id] of Object.entries(U)){
    await db.query('insert into auth.users(id) values($1)',[id]);
    await db.query('insert into public.profiles(user_id,display_name) values($1,$2)',[id,`Prueba ${label}`]);
  }
  const memberships=[ [U.global,A,'ADMIN_GLOBAL','active'],[U.admin,A,'COMPANY_ADMIN','active'],[U.employeeA,A,'EMPLOYEE','active'],[U.employeeB,B,'EMPLOYEE','active'],[U.colleague,A,'EMPLOYEE','active'],[U.multi,A,'COMPANY_ADMIN','active'],[U.multi,B,'HR','active'],[U.inactive,A,'EMPLOYEE','inactive'],[U.supervisor,A,'SUPERVISOR','active'] ];
  for(const [user,company,role,status] of memberships)await db.query('insert into public.user_company_memberships(company_id,user_id,role_code,status) values($1,$2,$3,$4)',[company,user,role,status]);
  for(const [id,company,user,name] of [[E.a,A,U.employeeA,'Persona A'],[E.b,B,U.employeeB,'Persona B'],[E.colleague,A,U.colleague,'Persona C']])await db.query('insert into public.employees(id,company_id,user_id,display_name) values($1,$2,$3,$4)',[id,company,user,name]);
  return db;
}
export async function asUser<T>(db:PGlite,user:string|null,fn:(db:PGlite)=>Promise<T>,role='authenticated'):Promise<T>{
  await db.exec('begin');
  try{
    await db.exec(`set local role ${role}`);
    await db.query("select set_config('request.jwt.claim.sub',$1,true)",[user??'']);
    return await fn(db);
  }finally{await db.exec('rollback');}
}
