import {headers} from 'next/headers';
import {NextResponse} from 'next/server';
import {revalidatePath} from 'next/cache';
import {config} from '@/server/config';
import {identity,companyContext} from '@/server/authorization';
import {attendanceInput} from '@/modules/attendance/domain';
import {logEvent} from '@/server/logger';
export async function POST(request:Request){
 const reply=(value:object,status=200)=>NextResponse.json(value,{status,headers:{'Cache-Control':'no-store'}});
 if((await headers()).get('origin')!==new URL(config().APP_URL).origin)return reply({error:'Solicitud no válida.'},403);
 if(!request.headers.get('content-type')?.startsWith('application/json'))return reply({error:'Formato no válido.'},415);
 if(Number(request.headers.get('content-length')??0)>16000)return reply({error:'Solicitud demasiado grande.'},413);
 try{
  const body=await request.text();if(body.length>16000)return reply({error:'Solicitud demasiado grande.'},413);
  const input=attendanceInput.safeParse(JSON.parse(body));if(!input.success)return reply({error:'Revisa los datos de la marcación.'},400);
  if(!await identity())return reply({error:'Inicia sesión nuevamente. Tu marcación continúa pendiente.'},401);
  const c=await companyContext(input.data.company);
  const {data,error}=await c.client.rpc('record_attendance',{p_company:c.company.id,p_client_id:input.data.client_id,p_data:input.data.data});
  if(error){logEvent('attendance_mark_denied','warn');return reply({error:error.code==='23514'?'La jornada cambió. Actualiza la página antes de marcar.':error.code==='23505'?'El identificador ya se usó con otros datos. Revisa la marcación pendiente.':'No pudimos registrar. Revisa tu acceso y proyecto.'},error.code==='42501'?403:409);}
  revalidatePath(`/empresas/${c.company.id}`,'layout');return reply({id:data});
 }catch{logEvent('attendance_mark_failed','warn');return reply({error:'No pudimos registrar tu marcación. Inténtalo nuevamente.'},400);}
}
