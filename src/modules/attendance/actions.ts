'use server';
import {headers} from 'next/headers';
import {revalidatePath} from 'next/cache';
import {z} from 'zod';
import {config} from '@/server/config';
import {companyContext,requirePermission} from '@/server/authorization';
import type {ActionState} from '@/shared/types';
const common={company:z.uuid(),reason:z.string().trim().min(5).max(500)};
export async function requestCorrection(_state:ActionState,form:FormData):Promise<ActionState>{
 const parsed=z.object({...common,event:z.uuid(),timestamp:z.iso.datetime({offset:true})}).safeParse(Object.fromEntries(form));
 if(!parsed.success)return {error:'Revisa la fecha y el motivo.'};
 try{if((await headers()).get('origin')!==new URL(config().APP_URL).origin)return {error:'Solicitud no válida.'};
  const c=await companyContext(parsed.data.company),{error}=await c.client.rpc('request_attendance_correction',{p_company:c.company.id,p_event:parsed.data.event,p_timestamp:parsed.data.timestamp,p_reason:parsed.data.reason});
  if(error)return {error:'No pudimos solicitar la corrección. Debe ser del mismo día, anterior a ahora y no tener otra revisión abierta.'};
  revalidatePath(`/empresas/${c.company.id}`,'layout');return {success:'Solicitud registrada. La marcación original se conserva.'};
 }catch{return {error:'No pudimos registrar la solicitud.'};}
}
export async function reviewCorrection(_state:ActionState,form:FormData):Promise<ActionState>{
 const parsed=z.object({...common,id:z.uuid(),decision:z.enum(['approve','reject'])}).safeParse(Object.fromEntries(form));if(!parsed.success)return {error:'Revisa el motivo de revisión.'};
 try{if((await headers()).get('origin')!==new URL(config().APP_URL).origin)return {error:'Solicitud no válida.'};const c=await requirePermission(parsed.data.company,'attendance.review');const {error}=await c.client.rpc('review_attendance_correction',{p_company:c.company.id,p_id:parsed.data.id,p_approve:parsed.data.decision==='approve',p_reason:parsed.data.reason});if(error)return {error:'No puedes revisar tu propia solicitud ni alterar el orden de las marcaciones.'};revalidatePath(`/empresas/${c.company.id}`,'layout');return {success:'Revisión guardada y auditada.'};}catch{return {error:'No pudimos guardar la revisión.'};}
}
