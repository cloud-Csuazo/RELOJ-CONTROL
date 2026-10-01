import { Card, Brand } from '@/components/ui';
import { AuthForm } from '@/components/auth-form';
import { configured } from '@/server/config';
export const dynamic = 'force-dynamic';
export default function PasswordPage() { return <main className="center-page"><Card><Brand/><h1 style={{marginTop:30}}>Nueva contraseña</h1><p className="muted">Usa una contraseña única de al menos 12 caracteres.</p><AuthForm mode="password" ready={configured()}/></Card></main>; }
