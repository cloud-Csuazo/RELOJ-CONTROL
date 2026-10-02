import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import type { PGlite } from '@electric-sql/pglite';
import { database, asUser, A, B, U, E } from './harness';
let db:PGlite;
before(async()=>{db=await database();});
after(async()=>{await db?.close();});
test('all public application tables have RLS enabled',async()=>{
  const result=await db.query<{relname:string;relrowsecurity:boolean}>("select relname,relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'");
  assert.ok(result.rows.length>=8); assert.ok(result.rows.every(r=>r.relrowsecurity));
});
test('private limiter has RLS enabled',async()=>{
  const result=await db.query<{relrowsecurity:boolean}>("select relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relname='auth_rate_limits'");
  assert.equal(result.rows[0]?.relrowsecurity,true);
});
test('authenticated clients cannot read the private limiter directly',async()=>{await assert.rejects(asUser(db,U.employeeA,q=>q.query('select * from private.auth_rate_limits')),/permission denied/);});
test('unauthenticated role cannot read companies',async()=>{await assert.rejects(asUser(db,null,q=>q.query('select * from public.companies'),'anon'),/permission denied/);});
test('employee SUACOF cannot see CLOUD9 via known ID',async()=>{await asUser(db,U.employeeA,async q=>assert.equal((await q.query('select id from public.companies where id=$1',[B])).rows.length,0));});
test('CLOUD9 employee cannot see SUACOF via known ID',async()=>{await asUser(db,U.employeeB,async q=>assert.equal((await q.query('select id from public.companies where id=$1',[A])).rows.length,0));});
test('employee sees their own labor relationship only',async()=>{await asUser(db,U.employeeA,async q=>assert.deepEqual((await q.query<{id:string}>('select id from public.employees')).rows.map(r=>r.id),[E.a]));});
test('employee A cannot read colleague B within same company',async()=>{await asUser(db,U.employeeA,async q=>assert.equal((await q.query('select id from public.employees where company_id=$1 and id=$2',[A,E.colleague])).rows.length,0));});
test('employee A cannot read employee in another company by ID',async()=>{await asUser(db,U.employeeA,async q=>assert.equal((await q.query('select id from public.employees where id=$1',[E.b])).rows.length,0));});
test('profile and identity are private to the user',async()=>{await asUser(db,U.employeeA,async q=>assert.deepEqual((await q.query<{user_id:string}>('select user_id from public.profiles')).rows.map(r=>r.user_id),[U.employeeA]));});
test('company admin cannot read unassigned company',async()=>{await asUser(db,U.admin,async q=>assert.equal((await q.query('select id from public.companies where id=$1',[B])).rows.length,0));});
test('ADMIN_GLOBAL sees only explicitly assigned companies',async()=>{await asUser(db,U.global,async q=>assert.deepEqual((await q.query<{id:string}>('select id from public.companies')).rows.map(r=>r.id),[A]));});
test('role can differ by company for a single account',async()=>{await asUser(db,U.multi,async q=>assert.deepEqual((await q.query<{company_id:string;role_code:string}>('select company_id,role_code from public.user_company_memberships where user_id=$1 order by company_id',[U.multi])).rows,[{company_id:A,role_code:'COMPANY_ADMIN'},{company_id:B,role_code:'HR'}]));});
test('inactive membership blocks company and employee access',async()=>{await asUser(db,U.inactive,async q=>{assert.equal((await q.query('select id from public.companies')).rows.length,0);assert.equal((await q.query('select id from public.employees')).rows.length,0);});});
test('membership expired or not yet active blocks access',async()=>{
  await db.exec('begin');
  try{await db.query("update public.user_company_memberships set valid_from=now()+interval '1 day' where user_id=$1",[U.employeeA]);await db.exec('set local role authenticated');await db.query("select set_config('request.jwt.claim.sub',$1,true)",[U.employeeA]);assert.equal((await db.query('select id from public.companies')).rows.length,0);}finally{await db.exec('rollback');}
});
test('changing client company ID does not permit INSERT of a membership',async()=>{await assert.rejects(asUser(db,U.employeeA,q=>q.query("insert into public.user_company_memberships(company_id,user_id,role_code) values($1,$2,'ADMIN_GLOBAL')",[B,U.employeeA])),/permission denied/);});
test('ordinary users cannot change their role directly',async()=>{await assert.rejects(asUser(db,U.employeeA,q=>q.query("update public.user_company_memberships set role_code='ADMIN_GLOBAL' where user_id=$1",[U.employeeA])),/permission denied/);});
test('profile updates cannot alter user_id',async()=>{await assert.rejects(asUser(db,U.employeeA,q=>q.query('update public.profiles set user_id=$1 where user_id=$2',[U.colleague,U.employeeA])),/permission denied/);});
test('ordinary users can update own display name',async()=>{await asUser(db,U.employeeA,async q=>assert.equal((await q.query("update public.profiles set display_name='Mi nombre' where user_id=$1 returning user_id",[U.employeeA])).rows.length,1));});
test('employee cannot view audit log even within own company',async()=>{await asUser(db,U.employeeA,async q=>assert.equal((await q.query('select id from public.audit_logs')).rows.length,0));});
for(const operation of ['update public.audit_logs set action=\'tampered\'','delete from public.audit_logs',`insert into public.audit_logs(company_id,action,entity_type,entity_id) values('${A}','fake','companies','${A}')`]){
  test(`append-only audit denies ${operation.split(' ')[0]} even to ADMIN_GLOBAL`,async()=>{await assert.rejects(asUser(db,U.global,q=>q.query(operation)),/permission denied/);});
}
test('admin log reader is restricted to assigned company',async()=>{await asUser(db,U.global,async q=>assert.ok((await q.query<{company_id:string}>('select company_id from public.audit_logs')).rows.every(r=>r.company_id===A)));});
test('COMPANY_ADMIN cannot mutate memberships via RPC',async()=>{await assert.rejects(asUser(db,U.admin,q=>q.query("select public.change_membership($1,gen_random_uuid(),'HR','active',1,'Prueba denegada')",[A])),/ACCESS_DENIED/);});
test('ADMIN_GLOBAL cannot mutate unassigned company via RPC',async()=>{await assert.rejects(asUser(db,U.global,q=>q.query("select public.change_membership($1,gen_random_uuid(),'HR','active',1,'Prueba denegada')",[B])),/ACCESS_DENIED/);});
test('approved role change generates atomic audit with real actor and reason',async()=>{
  await asUser(db,U.global,async q=>{
    const member=(await q.query<{id:string;version:number}>('select id,version from public.user_company_memberships where company_id=$1 and user_id=$2',[A,U.colleague])).rows[0];
    await q.query("select public.change_membership($1,$2,'HR','active',$3,'Cambio aprobado')",[A,member.id,member.version]);
    const logs=await q.query<{actor_user_id:string;reason:string;changed_fields:{after:{role_code:string}}}>('select actor_user_id,reason,changed_fields from public.audit_logs where entity_id=$1 and action=\'update\'',[member.id]);
    assert.equal(logs.rows.length,1);assert.equal(logs.rows[0].actor_user_id,U.global);assert.equal(logs.rows[0].reason,'Cambio aprobado');assert.equal(logs.rows[0].changed_fields.after.role_code,'HR');
  });
});
test('suspension blocks same authenticated identity without requiring JWT refresh',async()=>{
  await asUser(db,U.global,async q=>{
    const m=(await q.query<{id:string}>('select id from public.user_company_memberships where company_id=$1 and user_id=$2',[A,U.employeeA])).rows[0];
    await q.query("select public.change_membership($1,$2,'EMPLOYEE','inactive',1,'Suspensión aprobada')",[A,m.id]);
    await q.query("select set_config('request.jwt.claim.sub',$1,true)",[U.employeeA]);
    assert.equal((await q.query('select id from public.companies')).rows.length,0);
  });
});
test('stale membership version is rejected',async()=>{await assert.rejects(asUser(db,U.global,async q=>{const m=(await q.query<{id:string}>('select id from public.user_company_memberships where user_id=$1',[U.employeeA])).rows[0];await q.query("select public.change_membership($1,$2,'HR','active',999,'Cambio antiguo')",[A,m.id]);}),/VERSION_CONFLICT/);});
test('last ADMIN_GLOBAL cannot be removed',async()=>{await assert.rejects(asUser(db,U.global,async q=>{const m=(await q.query<{id:string}>('select id from public.user_company_memberships where user_id=$1',[U.global])).rows[0];await q.query("select public.change_membership($1,$2,'HR','active',1,'Quitar último administrador')",[A,m.id]);}),/LAST_ADMIN_REQUIRED/);});
test('company deactivation generates audit and denies subsequent access',async()=>{
  await asUser(db,U.global,async q=>{await q.query("select public.deactivate_company($1,1,'Empresa desactivada en prueba')",[A]);assert.equal((await q.query('select id from public.companies')).rows.length,0);await q.exec('reset role');const r=await q.query<{reason:string}>("select reason from public.audit_logs where entity_id=$1 and action='update'",[A]);assert.equal(r.rows[0].reason,'Empresa desactivada en prueba');});
});
test('auth limiter is inaccessible to ordinary authenticated callers',async()=>{await assert.rejects(asUser(db,U.employeeA,q=>q.query('select public.take_auth_attempt($1)',['a'.repeat(64)])),/permission denied/);});
test('shared limiter blocks sixth request',async()=>{
  await asUser(db,null,async q=>{for(let i=0;i<6;i++){const result=await q.query<{allowed:boolean}>('select public.take_auth_attempt($1) as allowed',['a'.repeat(64)]);assert.equal(result.rows[0].allowed,i<5);}},'service_role');
});
test('invalid timezone is rejected by the database',async()=>{await assert.rejects(db.query("insert into public.companies(code,legal_name,display_name,timezone) values('TEST','Empresa prueba','Empresa prueba','UTC-3')"),/INVALID_TIMEZONE/);});
