'use client';
import { useActionState } from 'react';
import { saveProfile } from '@/modules/tenancy/actions';
import type { Profile } from '@/shared/types';
export function ProfileForm({profile}:{profile:Profile}) {
  const [state, action, pending] = useActionState(saveProfile,{});
  return <form action={action} className="profile-form"><label>Nombre visible<input name="display_name" defaultValue={profile.display_name} required minLength={2} maxLength={100}/></label><label>Preferencia de idioma<select name="locale" defaultValue={profile.locale}><option value="es-CL">Español (Chile)</option><option value="en">Inglés (preferencia guardada; interfaz en español)</option></select></label>{state.error && <p className="notice error" role="alert">{state.error}</p>}{state.success && <p className="notice success" role="status">{state.success}</p>}<button className="button" disabled={pending}>{pending?'Guardando…':'Guardar perfil'}</button></form>;
}
