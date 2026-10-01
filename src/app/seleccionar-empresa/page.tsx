import Link from 'next/link';
import { redirect } from 'next/navigation';
import { ShieldCheck, LogOut } from 'lucide-react';
import { Brand, Badge, Card, CompanyLink } from '@/components/ui';
import { memberships } from '@/server/authorization';
import { configured } from '@/server/config';
import { logout } from '@/modules/identity/actions';
export const dynamic = 'force-dynamic';
export default async function SelectionPage({ searchParams }: { searchParams: Promise<{cambiar?: string}> }) {
  if (!configured()) redirect('/login');
  const context = await memberships();
  const query = await searchParams;
  if (context.companies.length === 1 && query.cambiar !== '1') redirect(`/empresas/${context.companies[0].id}`);
  return <main className="selection-page"><header className="selection-header"><Brand/><div className="account"><span>{context.profile?.display_name ?? 'Mi cuenta'}</span><form action={logout}><button className="icon-button" aria-label="Cerrar sesión"><LogOut size={18}/></button></form></div></header><Badge>MI ESPACIO DE TRABAJO</Badge><h1 style={{marginTop:18}}>Selecciona una empresa</h1><p className="muted">Elige el contexto en el que quieres trabajar hoy.</p>{context.companies.length ? <div className="selection-grid">{context.companies.map(company => <CompanyLink key={company.id} id={company.id} name={company.legal_name} code={company.code} role={context.memberships.find(m => m.company_id === company.id)!.role_code}/>)}</div> : <Card><h2>Tu acceso está pendiente</h2><p className="muted">No tienes empresas activas asignadas. Contacta a la persona que administra los accesos.</p></Card>}<p className="selection-note"><ShieldCheck size={17}/> Cada empresa conserva sus datos y permisos independientes.</p>{context.memberships.some(m => m.role_code === 'ADMIN_GLOBAL') && <Link className="auth-back" href="/consolidado">Ver empresas con acceso consolidado →</Link>}</main>;
}
