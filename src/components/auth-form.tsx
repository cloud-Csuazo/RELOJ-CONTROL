'use client';
import Link from 'next/link';
import { useActionState } from 'react';
import { ArrowRight, LockKeyhole } from 'lucide-react';
import { login, recover, updatePassword } from '@/modules/identity/actions';
import type { ActionState } from '@/shared/types';

export function AuthForm({ mode, ready }: { mode: 'login'|'recover'|'password'; ready: boolean }) {
  const action = mode === 'login' ? login : mode === 'recover' ? recover : updatePassword;
  const [state, formAction, pending] = useActionState<ActionState, FormData>(action, {});
  return <form action={formAction} className="auth-form">
    {mode !== 'password' && <label>Correo electrónico<input name="email" type="email" autoComplete="email" placeholder="tu@empresa.cl" required maxLength={254}/></label>}
    {mode !== 'recover' && <label>{mode === 'password' ? 'Nueva contraseña' : 'Contraseña'}<input name="password" type="password" autoComplete={mode === 'login' ? 'current-password' : 'new-password'} required minLength={mode === 'password' ? 12 : 1} maxLength={128}/></label>}
    {mode === 'password' && <label>Confirmar contraseña<input name="confirmation" type="password" autoComplete="new-password" minLength={12} maxLength={128} required/></label>}
    {mode === 'login' && <Link className="forgot-link" href="/recuperar">¿Olvidaste tu contraseña?</Link>}
    {!ready && <p className="notice" role="status">Entorno pendiente de configuración. Conecta Supabase para habilitar el acceso.</p>}
    {state.error && <p className="notice error" role="alert">{state.error}</p>}
    {state.success && <p className="notice success" role="status">{state.success}</p>}
    <button className="button" disabled={pending || !ready}>{pending ? 'Procesando…' : mode === 'login' ? 'Iniciar sesión' : mode === 'recover' ? 'Enviar instrucciones' : 'Guardar contraseña'}<ArrowRight size={18}/></button>
    <p className="form-footnote"><LockKeyhole size={14}/> Acceso privado para tu organización</p>
  </form>;
}
