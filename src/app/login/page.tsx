import { ShieldCheck, Building2 } from 'lucide-react';
import { Brand, Badge } from '@/components/ui';
import { AuthForm } from '@/components/auth-form';
import { configured } from '@/server/config';
export const dynamic = 'force-dynamic';
export default async function LoginPage({ searchParams }: { searchParams: Promise<{updated?: string; error?: string}> }) {
  const query = await searchParams;
  return <main className="auth-page"><section className="auth-story"><Brand light/><div className="story-body"><span className="eyebrow" style={{color:'#bce2d5'}}>TU EQUIPO. UN SOLO LUGAR.</span><h1>El trabajo diario,<br/><span>mejor conectado.</span></h1><p>Un espacio simple para conectar a tu equipo con la administración de tu empresa.</p><div className="story-points"><span><ShieldCheck size={18}/> Acceso protegido</span><span><Building2 size={18}/> Contexto por empresa</span></div></div><span className="story-foot">Nexo Laboral · Plataforma interna</span></section><section className="auth-panel"><div className="auth-inner"><div className="mobile-brand"><Brand/></div><Badge>BIENVENIDO A TU ESPACIO</Badge><h1>Inicia sesión</h1><p>Ingresa con tu cuenta para acceder a las empresas que tienes asignadas.</p>{query.updated && <p className="notice success">Contraseña actualizada. Inicia sesión nuevamente.</p>}{query.error && <p className="notice error">El enlace no es válido o ha vencido. Solicita uno nuevo.</p>}<AuthForm mode="login" ready={configured()}/></div></section></main>;
}
