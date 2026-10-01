/** Test-only HTTP contract double: simulated Auth + actual PostgreSQL RLS (PGlite).
 * Not imported by application. Never a development/production backend option.
 */
import { createServer } from 'node:http';
import { createHmac, randomUUID } from 'node:crypto';
import { database, B, U } from '../database/harness';
const db=await database();
await db.query("insert into public.user_company_memberships(company_id,user_id,role_code) values($1,$2,'ADMIN_GLOBAL')",[B,U.global]);
const tokens=new Map<string,string>();
const refreshTokens=new Map<string,string>();
const users=Object.fromEntries(Object.entries(U).map(([name,id])=>[id,{id,email:`${name.toLowerCase()}@example.test`,aud:'authenticated',role:'authenticated',app_metadata:{provider:'email'},user_metadata:{},created_at:'2026-01-01T00:00:00Z'}]));
function session(id:string){
  const encoded=(v:unknown)=>Buffer.from(JSON.stringify(v)).toString('base64url');
  const h=encoded({alg:'HS256',typ:'JWT'});const p=encoded({sub:id,exp:Math.floor(Date.now()/1000)+3600,iat:Math.floor(Date.now()/1000),aud:'authenticated',role:'authenticated',session_id:randomUUID()});
  const token=`${h}.${p}.${createHmac('sha256','fixture').update(`${h}.${p}`).digest('base64url')}`;
  const refresh=randomUUID();tokens.set(token,id);refreshTokens.set(refresh,id);
  return {access_token:token,refresh_token:refresh,token_type:'bearer',expires_in:3600,expires_at:Math.floor(Date.now()/1000)+3600,user:users[id]};
}
const tables=new Set(['companies','profiles','user_company_memberships','employees','roles','permissions','role_permissions','audit_logs']);
function identifier(value:string){if(!/^[a-z_]+$/.test(value))throw new Error('Invalid identifier');return `"${value}"`;}
let queue:Promise<unknown>=Promise.resolve();
createServer((request,response)=>{
  const task=async()=>{
    const url=new URL(request.url??'/', 'http://127.0.0.1:55431');
    const json=(status:number,data:unknown)=>{response.writeHead(status,{'Content-Type':'application/json'});response.end(JSON.stringify(data));};
    const chunks:Buffer[]=[];for await(const chunk of request)chunks.push(Buffer.from(chunk));
    const body=chunks.length?JSON.parse(Buffer.concat(chunks).toString()):{};
    const token=request.headers.authorization?.replace(/^Bearer /,'')??'';
    const user=tokens.get(token);
    if(url.pathname==='/health')return json(200,{ready:true});
    if(url.pathname==='/auth/v1/token'){
      if(url.searchParams.get('grant_type')==='refresh_token'){const id=refreshTokens.get(body.refresh_token);return id?json(200,session(id)):json(400,{error:'invalid_grant',msg:'Invalid refresh token'});}
      const fixture=Object.entries(users).find(([,v])=>v.email===body.email);
      return fixture&&body.password==='Fixture-Password-2026!'?json(200,session(fixture[0])):json(400,{error:'invalid_grant',msg:'Invalid login credentials',code:'invalid_credentials'});
    }
    if(url.pathname==='/auth/v1/user')return user?json(200,users[user]):json(401,{msg:'Unauthorized',code:'bad_jwt'});
    if(url.pathname==='/auth/v1/recover')return json(200,{});
    if(url.pathname==='/auth/v1/logout'){tokens.delete(token);return json(200,{});}
    const service=token==='fixture-service-only-not-a-real-key';
    if(!user&&!service)return json(401,{message:'Unauthenticated',code:'42501'});
    await db.exec('begin');
    try{
      await db.exec(`set local role ${service?'service_role':'authenticated'}`);
      await db.query("select set_config('request.jwt.claim.sub',$1,true)",[user??'']);
      if(url.pathname.startsWith('/rest/v1/rpc/')){
        const rpc=url.pathname.split('/').at(-1);
        let sql:string;let args:unknown[];
        if(rpc==='take_auth_attempt'){sql='select public.take_auth_attempt($1) as result';args=[body.p_bucket];}
        else if(rpc==='change_membership'){sql='select public.change_membership($1,$2,$3,$4,$5,$6) as result';args=[body.p_company,body.p_membership,body.p_role,body.p_status,body.p_version,body.p_reason];}
        else if(rpc==='deactivate_company'){sql='select public.deactivate_company($1,$2,$3) as result';args=[body.p_company,body.p_version,body.p_reason];}
        else throw new Error('Unsupported RPC');
        const result=await db.query<{result:unknown}>(sql,args);await db.exec('commit');return json(200,result.rows[0].result);
      }
      const table=url.pathname.split('/').at(-1)??'';
      if(!tables.has(table))throw new Error('Unsupported table');
      const columns=(url.searchParams.get('select')??'*').split(',').map(identifier).join(',');
      const params:unknown[]=[];const where:string[]=[];
      for(const [field,value]of url.searchParams){if(['select','order','limit'].includes(field))continue;if(!value.startsWith('eq.'))throw new Error('Unsupported filter');params.push(value.slice(3));where.push(`${identifier(field)}=$${params.length}`);}
      let sql=`select ${columns} from public.${identifier(table)}${where.length?' where '+where.join(' and '):''}`;
      if(url.searchParams.has('order')){const [field,direction]=url.searchParams.get('order')!.split('.');sql+=` order by ${identifier(field)} ${direction==='desc'?'desc':'asc'}`;}
      if(url.searchParams.has('limit')){const limit=Number(url.searchParams.get('limit'));if(!Number.isInteger(limit)||limit<1||limit>1000)throw new Error('Invalid limit');sql+=` limit ${limit}`;}
      const result=await db.query(sql,params);await db.exec('commit');
      if(request.headers.accept?.includes('application/vnd.pgrst.object+json'))return result.rows.length===1?json(200,result.rows[0]):json(406,{code:'PGRST116',details:`The result contains ${result.rows.length} rows`,message:'JSON object requested, multiple (or no) rows returned'});
      return json(200,result.rows);
    }catch(error){await db.exec('rollback');return json(403,{code:(error as {code?:string}).code??'42501',message:(error as Error).message});}
  };
  queue=queue.then(task,task).catch(()=>{if(!response.headersSent){response.writeHead(500);response.end('{}');}});
}).listen(55431,'127.0.0.1',()=>console.log('Test contract backend ready (not real Supabase Auth).'));
