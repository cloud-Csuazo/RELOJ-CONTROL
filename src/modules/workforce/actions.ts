'use server';
import {headers} from 'next/headers';
import {revalidatePath} from 'next/cache';
import {z} from 'zod';
import {requirePermission} from '@/server/authorization';
import {config} from '@/server/config';
import {logEvent} from '@/server/logger';
import type {ActionState} from '@/shared/types';
import {workforceData} from './domain';
export async function saveWorkforce(_state:ActionState,form:FormData):Promise<ActionState>{
 const raw=Object.fromEntries(form);
 const envelope=z.object({company:z.uuid(),id:z.union([z.uuid(),z.literal('')]).default(''),version:z.coerce.number().int().positive().default(1),reason:z.string().trim().min(5).max(500)}).safeParse(raw);
 const data=workforceData.safeParse(raw);
 if(!envelope.success||!data.success)return {error:data.error?.issues[0]?.message==='RUT inválido'?'El RUT no es válido. Revisa su dígito verificador.':'Revisa los campos obligatorios, fechas, montos y motivo.'};
 try{
  if((await headers()).get('origin')!==new URL(config().APP_URL).origin)return {error:'No pudimos validar la solicitud.'};
  const c=await requirePermission(envelope.data.company,'workforce.manage');
  const {kind,...payload}=data.data;
  const {error}=await c.client.rpc('save_workforce',{p_company:envelope.data.company,p_kind:kind,p_id:envelope.data.id||null,p_version:envelope.data.version,p_data:payload,p_reason:envelope.data.reason});
  if(error){logEvent('workforce_write_denied','warn');return {error:error.code==='40001'?'El registro cambió. Recarga la página para editarlo.':error.code==='23505'?'Ya existe un registro con ese RUT o código.':error.code==='23514'?'Revisa las fechas, el RUT y los contratos existentes. No pueden superponerse.':'No pudimos guardar. Revisa los datos y permisos.'};}
  revalidatePath(`/empresas/${envelope.data.company}`,'layout');
  return {success:'Guardado y registrado en el historial.'};
 }catch{logEvent('workforce_write_failed','warn');return {error:'No pudimos guardar. Inténtalo nuevamente.'};}
}
export async function endWorkforceHistory(_state:ActionState,form:FormData):Promise<ActionState>{
 const data=z.object({company:z.uuid(),kind:z.enum(['contract','project_assignment','supervisor_assignment']),id:z.uuid(),version:z.coerce.number().int().positive(),ends_on:z.iso.date(),reason:z.string().trim().min(5).max(500)}).safeParse(Object.fromEntries(form));
 if(!data.success)return {error:'Revisa la fecha y el motivo.'};
 try{if((await headers()).get('origin')!==new URL(config().APP_URL).origin)return {error:'Solicitud no válida.'};const c=await requirePermission(data.data.company,'workforce.manage');const {error}=await c.client.rpc('end_workforce_history',{p_company:data.data.company,p_kind:data.data.kind,p_id:data.data.id,p_version:data.data.version,p_ends_on:data.data.ends_on,p_reason:data.data.reason});if(error)return {error:'No pudimos finalizar el registro. Revisa fechas, versión y permisos.'};revalidatePath(`/empresas/${data.data.company}`,'layout');return {success:'Término registrado en el historial.'};}catch{return {error:'No pudimos finalizar el registro.'};}
}
