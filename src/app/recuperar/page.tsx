import Link from 'next/link';
import { Brand, Card } from '@/components/ui';
import { AuthForm } from '@/components/auth-form';
import { configured } from '@/server/config';
export const dynamic = 'force-dynamic';
export default function RecoverPage() { return <main className="center-page"><Card><Brand/><h1 style={{marginTop:30}}>Recupera tu acceso</h1><p className="muted">Te enviaremos instrucciones para crear una nueva contraseña.</p><AuthForm mode="recover" ready={configured()}/><Link className="auth-back" href="/login">← Volver a iniciar sesión</Link></Card></main>; }
