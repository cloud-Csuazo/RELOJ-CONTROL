import Link from 'next/link';
import type { ReactNode } from 'react';
import { Building2, ArrowUpRight, ShieldCheck } from 'lucide-react';

export function Brand({ light = false }: { light?: boolean }) {
  return <Link href="/" className={`brand ${light ? 'brand-light' : ''}`} aria-label="Nexo Laboral, inicio"><span className="brand-mark">N</span><span>Nexo<span className="brand-sub">LABORAL</span></span></Link>;
}
export function Card({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <section className={`card ${className}`}>{children}</section>;
}
export function Badge({ children }: { children: ReactNode }) { return <span className="badge">{children}</span>; }
export function AccessDeniedView() {
  return <main className="center-page"><Card><ShieldCheck size={36}/><h1>Acceso denegado</h1><p>No tienes permisos para acceder a este contenido.</p><Link className="button" href="/seleccionar-empresa">Volver a mis empresas</Link></Card></main>;
}
export function CompanyLink({ id, name, code, role }: { id: string; name: string; code: string; role: string }) {
  return <Link className="company-card" href={`/empresas/${id}`}><span className="company-icon"><Building2 size={28}/></span><span><span className="eyebrow">{code}</span><h2>{name}</h2><span className="muted">{role.replaceAll('_',' ')}</span></span><ArrowUpRight className="company-arrow" size={22}/></Link>;
}
