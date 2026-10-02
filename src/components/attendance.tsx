import {companyContext} from '@/server/authorization';
import {Journey} from './journey';
import {Card,Badge} from './ui';
import {CorrectionForm,ReviewCorrectionForm} from './attendance-correction-form';
import {eventLabels,type EventRow} from '@/modules/attendance/domain';
const alertLabels:Record<string,string>={GPS_UNAVAILABLE:'Sin GPS',GPS_LOW_ACCURACY:'GPS poco preciso',OFFLINE_NEEDS_REVIEW:'Sin conexión: revisar hora',DEVICE_CLOCK_DIFFERENCE:'Hora del dispositivo distinta',LONG_OPEN_SESSION:'Jornada extensa sin cierre',OUTSIDE_EXPECTED_LOCATION:'Fuera de ubicación esperada',NO_EXPECTED_LOCATION:'Sin ubicación configurada'};
export async function Attendance({companyId,personal=false,date}:{companyId:string;personal?:boolean;date?:string}){
 const c=await companyContext(companyId),tz=c.company.timezone;
 const employeeResult=await c.client.from('employees').select('id,display_name,status').eq('company_id',companyId).eq('user_id',c.user.id).maybeSingle();
 if(employeeResult.error)throw new Error('ATTENDANCE_UNAVAILABLE');
 const own=employeeResult.data;
 const defaultDate=new Intl.DateTimeFormat('en-CA',{timeZone:tz,year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const selected=date&&/^\d{4}-\d{2}-\d{2}$/.test(date)?date:defaultDate;
 // Broad UTC window followed by exact company-local date filtering, including DST.
 const start=new Date(`${selected}T00:00:00Z`);if(!Number.isFinite(start.getTime()))throw new Error('INVALID_DATE');
 let query=c.client.from('attendance_events').select('id,employee_id,session_id,event_type,timestamp_server,timestamp_device,timezone,alerts,sync_status,distance_meters').eq('company_id',companyId).gte('timestamp_server',new Date(start.getTime()-24*3600000).toISOString()).lt('timestamp_server',new Date(start.getTime()+48*3600000).toISOString()).order('timestamp_server').limit(1000);
 if(personal){if(!own)return <Card><h2>Tu ficha laboral está pendiente</h2><p>Administración debe vincular tu cuenta a una ficha activa antes de marcar.</p></Card>;query=query.eq('employee_id',own.id);}
 const [eventResult,employeeNames,corrections,permission]=await Promise.all([query,c.client.from('employees').select('id,display_name').eq('company_id',companyId).limit(500),c.client.from('attendance_corrections').select('id,event_id,employee_id,corrected_timestamp,original_timestamp,status,reason,requested_by').eq('company_id',companyId).order('requested_at',{ascending:false}).limit(100),c.client.from('role_permissions').select('permission_code').eq('role_code',c.membership.role_code).eq('permission_code','attendance.review').maybeSingle()]);
 if(eventResult.error||employeeNames.error||corrections.error||permission.error)throw new Error('ATTENDANCE_UNAVAILABLE');
 const events=(eventResult.data as EventRow[]).filter(e=>new Intl.DateTimeFormat('en-CA',{timeZone:tz,year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(e.timestamp_server))===selected);
 const format=(timestamp:string)=>new Intl.DateTimeFormat('es-CL',{timeZone:tz,dateStyle:'short',timeStyle:'medium'}).format(new Date(timestamp));
 let journey=null;
 if(personal&&own){
  const [sessions,assignments]=await Promise.all([c.client.from('attendance_sessions').select('id,state,project_id').eq('company_id',companyId).eq('employee_id',own.id).order('started_at',{ascending:false}).limit(1).maybeSingle(),c.client.from('employee_project_assignments').select('project_id').eq('company_id',companyId).eq('employee_id',own.id).eq('status','active').lte('starts_on',defaultDate).or(`ends_on.is.null,ends_on.gte.${defaultDate}`)]);
  if(sessions.error||assignments.error)throw new Error('ATTENDANCE_UNAVAILABLE');
  const projectIds=assignments.data.map(a=>a.project_id),projects=projectIds.length?await c.client.from('projects').select('id,name').in('id',projectIds).eq('status','active'):{data:[],error:null};
  if(projects.error)throw new Error('ATTENDANCE_UNAVAILABLE');
  const currentSessionEvents=sessions.data?await c.client.from('attendance_events').select('id,employee_id,session_id,event_type,timestamp_server,timestamp_device,timezone,alerts,sync_status,distance_meters').eq('session_id',sessions.data.id).order('timestamp_server'):{data:events,error:null};
  if(currentSessionEvents.error)throw new Error('ATTENDANCE_UNAVAILABLE');
  const effective=(currentSessionEvents.data as EventRow[]).map(e=>({...e,timestamp_server:corrections.data.find(x=>x.event_id===e.id&&x.status==='APPROVED')?.corrected_timestamp??e.timestamp_server}));
  journey=<Card><Journey company={companyId} userId={c.user.id} name={own.display_name} timezone={tz} state={sessions.data?.state??'IDLE'} sessionProject={sessions.data?.project_id??null} projects={projects.data??[]} events={effective}/></Card>;
 }
 return <>{journey}<Card className="mt-6"><h2>{personal?'Mis marcaciones':'Asistencia y alertas'}</h2><form method="get" className="filters"><label>Fecha<input type="date" name="date" defaultValue={selected} required/></label><button className="button secondary">Consultar</button></form>{eventResult.data.length===1000&&<p className="notice">Se alcanzó el límite de esta consulta. Consulta fechas acotadas para revisar todo el historial.</p>}<p>{new Set(events.filter(e=>e.event_type==='CLOCK_IN').map(e=>e.employee_id)).size} trabajador(es) con inicio registrado · {events.filter(e=>e.alerts.length).length} eventos con alertas</p><div className="table-wrap"><table className="data-table"><thead><tr><th>Trabajador</th><th>Evento</th><th>Hora oficial</th><th>Alertas</th><th>Corrección</th></tr></thead><tbody>{events.map(e=>{const corrected=corrections.data.find(x=>x.event_id===e.id&&x.status==='APPROVED');return <tr key={e.id}><td>{employeeNames.data.find(x=>x.id===e.employee_id)?.display_name??'Trabajador'}</td><td>{eventLabels[e.event_type]}</td><td>{format(e.timestamp_server)}{corrected&&<p>Corregida: {format(corrected.corrected_timestamp)}</p>}</td><td>{e.alerts.map(a=><Badge key={a}>{alertLabels[a]??a}</Badge>)}{e.distance_meters!==null&&<p>{Math.round(e.distance_meters)} m del lugar esperado</p>}</td><td>{(permission.data||e.employee_id===own?.id)&&<details><summary>Solicitar revisión</summary><CorrectionForm companyId={companyId} eventId={e.id}/></details>}</td></tr>;})}</tbody></table></div>{!events.length&&<p>No hay marcaciones para esta fecha.</p>}</Card><Card className="mt-6"><h2>Correcciones auditables</h2>{corrections.data.map(x=><details key={x.id}><summary>{x.status==='REQUESTED'?'Pendiente':x.status==='APPROVED'?'Aprobada':'Rechazada'} · {format(x.original_timestamp)}</summary><p>{x.reason}</p><p>Hora solicitada: {format(x.corrected_timestamp)}</p>{permission.data&&x.status==='REQUESTED'&&x.requested_by!==c.user.id&&<ReviewCorrectionForm companyId={companyId} id={x.id}/>}</details>)}{!corrections.data.length&&<p>No hay solicitudes de corrección.</p>}<p className="muted">La hora del servidor permanece en el evento original. Las horas corregidas se muestran por separado.</p></Card></>;
}

