'use client';
import { useActionState } from 'react';
import { changeMembership, deactivateCompany } from '@/modules/tenancy/actions';
import { roles, type Membership } from '@/shared/types';
export function MembershipForm({membership}:{membership:Membership}) {
  const [state,action,pending] = useActionState(changeMembership,{});
  return <form action={action} className="profile-form"><input type="hidden" name="company" value={membership.company_id}/><input type="hidden" name="membership" value={membership.id}/><input type="hidden" name="version" value={membership.version}/><label>Rol<select name="role" defaultValue={membership.role_code}>{roles.map(role=><option key={role}>{role}</option>)}</select></label><label>Estado<select name="status" defaultValue={membership.status}><option value="active">Activo</option><option value="inactive">Inactivo</option></select></label><label>Motivo<input name="reason" required minLength={5} maxLength={500}/></label>{state.error&&<p role="alert" className="notice error">{state.error}</p>}{state.success&&<p role="status" className="notice success">{state.success}</p>}<button className="button" disabled={pending}>{pending?'Guardando…':'Actualizar acceso'}</button></form>;
}
export function DeactivateForm({companyId,version}:{companyId:string;version:number}) {
  const [state,action,pending] = useActionState(deactivateCompany,{});
  return <form action={action} className="profile-form"><input type="hidden" name="company" value={companyId}/><input type="hidden" name="version" value={version}/><p className="notice">Desactivar esta empresa bloqueará el acceso a sus datos. Los registros se conservan. La reactivación requiere el procedimiento de infraestructura documentado.</p><label>Motivo<input name="reason" minLength={5} maxLength={500} required/></label><label>Escribe DESACTIVAR para confirmar<input name="confirmation" required pattern="DESACTIVAR"/></label>{state.error&&<p role="alert" className="notice error">{state.error}</p>}<button className="button" disabled={pending}>{pending?'Procesando…':'Desactivar empresa'}</button></form>;
}
