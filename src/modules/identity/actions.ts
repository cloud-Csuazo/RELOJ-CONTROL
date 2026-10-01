'use server';
import { redirect } from 'next/navigation';
import { headers, cookies } from 'next/headers';
import { config, configured } from '@/server/config';
import { requestClient } from '@/server/supabase';
import { allowAuthAttempt } from '@/server/rate-limit';
import { logEvent } from '@/server/logger';
import { emailSchema, loginSchema, passwordSchema } from '@/shared/validation';
import type { ActionState } from '@/shared/types';
import { validRecoveryProof } from '@/server/recovery-proof';

async function sameOrigin() {
  const origin = (await headers()).get('origin');
  if (origin !== new URL(config().APP_URL).origin) throw new Error('INVALID_ORIGIN');
}
export async function login(_previous: ActionState, form: FormData): Promise<ActionState> {
  if (!configured()) return { error: 'Falta configurar el entorno de Supabase. Revisa las instrucciones de instalación.' };
  const parsed = loginSchema.safeParse({ email: form.get('email'), password: form.get('password') });
  if (!parsed.success) return { error: 'Revisa el correo y la contraseña.' };
  try {
    await sameOrigin();
    if (!await allowAuthAttempt('login',parsed.data.email)) return { error: 'Demasiados intentos. Inténtalo nuevamente en 15 minutos.' };
    const supabase = await requestClient();
    const { error } = await supabase.auth.signInWithPassword(parsed.data);
    if (error) { logEvent('login_denied','warn'); return { error: 'No pudimos iniciar sesión. Revisa tus datos.' }; }
    logEvent('login_success');
  } catch { logEvent('login_unavailable','error'); return { error: 'No pudimos conectarnos. Inténtalo nuevamente.' }; }
  redirect('/seleccionar-empresa');
}
export async function recover(_previous: ActionState, form: FormData): Promise<ActionState> {
  if (!configured()) return { error: 'Falta configurar Supabase y el envío de correo.' };
  const parsed = emailSchema.safeParse(form.get('email'));
  if (!parsed.success) return { error: 'Ingresa un correo válido.' };
  try {
    await sameOrigin();
    if (await allowAuthAttempt('recovery',parsed.data)) {
      const supabase = await requestClient();
      const { error } = await supabase.auth.resetPasswordForEmail(parsed.data, { redirectTo: `${config().APP_URL}/auth/callback?next=/actualizar-contrasena` });
      if (error) logEvent('recovery_provider_error','warn');
    }
  } catch { logEvent('recovery_unavailable','error'); return { error: 'No pudimos procesar la solicitud. Inténtalo nuevamente.' }; }
  return { success: 'Si el correo tiene una cuenta, recibirás las instrucciones para recuperar el acceso.' };
}
export async function updatePassword(_previous: ActionState, form: FormData): Promise<ActionState> {
  const parsed = passwordSchema.safeParse(form.get('password'));
  if (!parsed.success) return { error: 'Usa una contraseña de entre 12 y 128 caracteres.' };
  if (form.get('password') !== form.get('confirmation')) return { error: 'Las contraseñas no coinciden.' };
  try {
    await sameOrigin();
    const supabase = await requestClient();
    const { data } = await supabase.auth.getUser();
    const recovery = (await cookies()).get('recovery-authorized')?.value;
    if (!data.user || !validRecoveryProof(recovery,data.user.id)) return { error: 'Abre un enlace de recuperación válido para cambiar tu contraseña.' };
    if (!await allowAuthAttempt('password',data.user.id)) return { error: 'Demasiados intentos. Espera 15 minutos.' };
    const { error } = await supabase.auth.updateUser({ password: parsed.data });
    if (error) return { error: 'No pudimos cambiar la contraseña. Solicita un nuevo enlace.' };
    (await cookies()).delete('recovery-authorized');
    await supabase.auth.signOut({ scope: 'global' });
    logEvent('password_updated');
  } catch { logEvent('password_update_failed','error'); return { error: 'No pudimos cambiar la contraseña.' }; }
  redirect('/login?updated=1');
}
export async function logout() {
  await sameOrigin();
  const supabase = await requestClient();
  const { error } = await supabase.auth.signOut({scope:'local'});
  if (error) logEvent('logout_provider_error','warn');
  const store = await cookies();
  store.getAll().filter(c => c.name.startsWith('sb-') || c.name === 'recovery-authorized').forEach(c => store.delete(c.name));
  redirect('/login');
}
