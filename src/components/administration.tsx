import { requirePermission } from '@/server/authorization';
import { config } from '@/server/config';
import { Card } from './ui';
import { DeactivateForm, MembershipForm } from './admin-forms';
import type { Membership } from '@/shared/types';
export async function Administration({companyId}:{companyId:string}) {
  const context=await requirePermission(companyId,'membership.read_company');
  const {data,error}=await context.client.from('user_company_memberships').select('id,company_id,user_id,role_code,status,valid_from,valid_until,version').eq('company_id',companyId).order('created_at');
  if(error)throw new Error('MEMBERSHIP_LIST_FAILED');
  const enabled=config().ENABLE_ACCESS_MANAGEMENT==='true'&&context.membership.role_code==='ADMIN_GLOBAL';
  const {data:company}=await context.client.from('companies').select('version').eq('id',companyId).single();
  const {data:logs,error:logError}=await context.client.from('audit_logs').select('id,action,entity_type,reason,created_at').eq('company_id',companyId).order('created_at',{ascending:false}).limit(30);
  if(logError)throw new Error('AUDIT_LIST_FAILED');
  return <><Card><h2>Accesos de esta empresa</h2><p className="muted">{enabled?'Sólo ADMIN_GLOBAL puede cambiar roles y estados. Cada cambio requiere un motivo.':'Tienes acceso de lectura. Los cambios requieren ADMIN_GLOBAL y gestión habilitada.'}</p>{(data as Membership[]).map(m=><details key={m.id} className="card" style={{marginTop:14,padding:18}}><summary style={{cursor:'pointer'}}>Cuenta {m.user_id.slice(0,8)} · {m.role_code} · {m.status==='active'?'Activo':'Inactivo'}</summary>{enabled&&<div style={{marginTop:20}}><MembershipForm membership={m}/></div>}</details>)}</Card><Card className="mt-6"><h2>Auditoría reciente</h2><p className="muted">Registro de cambios. La aplicación no permite editarlo ni eliminarlo.</p>{logs?.length?<div className="table-wrap"><table className="data-table"><thead><tr><th>Fecha</th><th>Entidad</th><th>Acción</th><th>Motivo</th></tr></thead><tbody>{logs.map(log=><tr key={log.id}><td>{new Intl.DateTimeFormat('es-CL',{dateStyle:'short',timeStyle:'short',timeZone:context.company.timezone}).format(new Date(log.created_at))}</td><td>{log.entity_type}</td><td>{log.action}</td><td>{log.reason??'Provisionamiento inicial'}</td></tr>)}</tbody></table></div>:<p className="muted">No tienes eventos visibles o permisos de lectura de auditoría.</p>}</Card>{enabled&&company&&<Card className="mt-6"><h2>Desactivar empresa</h2><DeactivateForm companyId={companyId} version={company.version}/></Card>}</>;
}
