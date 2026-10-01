'use server';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { headers } from 'next/headers';
import { z } from 'zod';
import { config } from '@/server/config';
import { requirePermission, requireIdentity } from '@/server/authorization';
import { idSchema, profileSchema } from '@/shared/validation';
import { roles, type ActionState } from '@/shared/types';
import { logEvent } from '@/server/logger';
import { AccessDenied } from './domain/authorization';

async function checkOrigin() {
  if ((await headers()).get('origin') !== new URL(config().APP_URL).origin) throw new AccessDenied();
}
export async function saveProfile(_state: ActionState, form: FormData): Promise<ActionState> {
  const parsed = profileSchema.safeParse({display_name:form.get('display_name'),locale:form.get('locale')});
  if (!parsed.success) return {error:'Revisa tu nombre y el idioma.'};
  try {
    await checkOrigin();
    const context = await requireIdentity();
    const {data,error} = await context.client.from('profiles').update(parsed.data).eq('user_id',context.user.id).select('user_id').maybeSingle();
    if (error || !data) return {error:'No pudimos guardar tu perfil.'};
    revalidatePath('/empresas','layout');
    return {success:'Perfil actualizado.'};
  } catch { logEvent('profile_update_failed','warn'); return {error:'No pudimos guardar tu perfil.'}; }
}
const changeSchema = z.object({ company:z.uuid(), membership:z.uuid(), role:z.enum(roles), status:z.enum(['active','inactive']), version:z.coerce.number().int().positive(), reason:z.string().trim().min(5).max(500) });
export async function changeMembership(_state: ActionState, form: FormData): Promise<ActionState> {
  const parsed = changeSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return {error:'Revisa los datos y escribe un motivo de al menos 5 caracteres.'};
  try {
    await checkOrigin();
    if (config().ENABLE_ACCESS_MANAGEMENT !== 'true') return {error:'La gestión de accesos está deshabilitada en este entorno.'};
    const context = await requirePermission(parsed.data.company,'membership.manage');
    const {error} = await context.client.rpc('change_membership',{p_company:parsed.data.company,p_membership:parsed.data.membership,p_role:parsed.data.role,p_status:parsed.data.status,p_version:parsed.data.version,p_reason:parsed.data.reason});
    if (error) {
      logEvent('membership_change_denied','warn');
      return {error:error.code==='40001' ? 'Este acceso cambió. Actualiza la página antes de intentar nuevamente.' : error.code==='23514' ? 'Debe conservarse al menos un ADMIN_GLOBAL activo en esta empresa.' : 'No pudimos cambiar el acceso. Revisa los permisos y el estado.'};
    }
    revalidatePath(`/empresas/${parsed.data.company}`,'layout');
    return {success:'Acceso actualizado y registrado en auditoría.'};
  } catch { logEvent('membership_change_denied','warn'); return {error:'Acceso denegado.'}; }
}
export async function deactivateCompany(_state: ActionState, form: FormData): Promise<ActionState> {
  const parsed = z.object({company:idSchema,version:z.coerce.number().int().positive(),reason:z.string().trim().min(5).max(500),confirmation:z.literal('DESACTIVAR')}).safeParse(Object.fromEntries(form));
  if (!parsed.success) return {error:'Escribe DESACTIVAR y un motivo de al menos 5 caracteres.'};
  try {
    await checkOrigin();
    if (config().ENABLE_ACCESS_MANAGEMENT !== 'true') return {error:'La gestión de empresas está deshabilitada.'};
    const context = await requirePermission(parsed.data.company,'company.deactivate');
    const {error} = await context.client.rpc('deactivate_company',{p_company:parsed.data.company,p_version:parsed.data.version,p_reason:parsed.data.reason});
    if (error) return {error:'No pudimos desactivar la empresa. Actualiza la página y revisa los permisos.'};
  } catch { logEvent('company_deactivation_denied','warn'); return {error:'Acceso denegado.'}; }
  redirect('/seleccionar-empresa');
}
