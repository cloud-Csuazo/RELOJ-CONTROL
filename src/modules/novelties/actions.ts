'use server';
import {headers} from 'next/headers';
import {revalidatePath} from 'next/cache';
import {z} from 'zod';
import {config} from '@/server/config';
import {companyContext} from '@/server/authorization';
import {logEvent} from '@/server/logger';
import type {ActionState} from '@/shared/types';
import {noveltyData,integerMoney} from './domain';
export async function saveNovelty(_state:ActionState,form:FormData):Promise<ActionState>{
 const raw=Object.fromEntries(form),company=z.uuid().safeParse(raw.company);if(!company.success)return {error:'Empresa no válida.'};
 try{
  if((await headers()).get('origin')!==new URL(config().APP_URL).origin)return {error:'Solicitud no válida.'};const c=await companyContext(company.data);
  let rpc:string,args:Record<string,unknown>;
  switch(raw.kind){
   case 'novelty.create':{const parsed=noveltyData.safeParse(raw);if(!parsed.success)return {error:parsed.error.issues[0]?.message??'Revisa los campos.'};const {type,draft,...data}=parsed.data;rpc='create_novelty';args={p_company:c.company.id,p_data:{...data,kind:type},p_draft:draft==='true'};break;}
   case 'novelty.transition':{const parsed=z.object({id:z.uuid(),version:z.coerce.number().int().positive(),action:z.enum(['submit','cancel','start_review','approve','reject']),approved_amount:integerMoney,approved_minutes:z.coerce.number().int().min(0).max(10080).default(0),reason:z.string().trim().min(5).max(500)}).safeParse(raw);if(!parsed.success)return {error:'Revisa la decisión y su motivo.'};const d=parsed.data;rpc='transition_novelty';args={p_company:c.company.id,p_id:d.id,p_version:d.version,p_action:d.action,p_data:{approved_amount:d.approved_amount,approved_minutes:d.approved_minutes},p_reason:d.reason};break;}
   case 'novelty.comment':{const parsed=z.object({id:z.uuid(),body:z.string().trim().min(1).max(2000)}).safeParse(raw);if(!parsed.success)return {error:'Escribe un comentario.'};rpc='add_novelty_comment';args={p_company:c.company.id,p_id:parsed.data.id,p_body:parsed.data.body};break;}
   case 'novelty.payment':{const parsed=z.object({id:z.uuid(),client_id:z.uuid(),amount:integerMoney.refine(v=>v!=='0'),payment_method:z.string().trim().min(2).max(80),reference:z.string().trim().max(160).default(''),reason:z.string().trim().min(5).max(500)}).safeParse(raw);if(!parsed.success)return {error:'Revisa el monto y el comprobante de pago.'};const {id,client_id,...data}=parsed.data;rpc='record_novelty_payment';args={p_company:c.company.id,p_id:id,p_client_id:client_id,p_data:data};break;}
   case 'category.create':{const parsed=z.string().trim().min(2).max(100).safeParse(raw.name);if(!parsed.success)return {error:'Nombre de categoría no válido.'};rpc='save_expense_category';args={p_company:c.company.id,p_name:parsed.data};break;}
   default:return {error:'Operación no válida.'};
  }
  const {error}=await c.client.rpc(rpc,args);if(error){logEvent('novelty_write_denied','warn');return {error:error.code==='40001'?'El registro cambió. Recarga antes de continuar.':error.message.includes('PERIOD_LOCKED')?'El período está cerrado. No se puede cambiar.':'No pudimos guardar. Revisa permisos, estado, monto y período; no puedes aprobar tus propias solicitudes.'};}
  revalidatePath(`/empresas/${c.company.id}`,'layout');return {success:'Operación registrada y auditada.'};
 }catch{logEvent('novelty_write_failed','warn');return {error:'No pudimos guardar la operación.'};}
}
