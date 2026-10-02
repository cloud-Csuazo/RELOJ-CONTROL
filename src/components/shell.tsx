import Link from 'next/link';
import { Building2, ChevronDown, LogOut, ShieldCheck, LayoutDashboard, Users, Clock3, MessageSquare, FolderKanban, Wallet, FileText, BarChart3, Settings, UserRound } from 'lucide-react';
import { Brand } from './ui';
import { logout } from '@/modules/identity/actions';
import type { Company, Membership, Profile } from '@/shared/types';
import type { ReactNode } from 'react';

const adminLinks = [
  ['','Dashboard',LayoutDashboard], ['trabajadores','Trabajadores',Users], ['asistencia','Asistencia',Clock3],
  ['novedades','Novedades',MessageSquare], ['proyectos','Proyectos',FolderKanban], ['remuneraciones','Remuneraciones',Wallet],
  ['liquidaciones','Liquidaciones',FileText], ['reportes','Reportes',BarChart3], ['administracion','Administración',Settings]
] as const;
const workerLinks = [['','Inicio',LayoutDashboard],['jornada','Mi jornada',Clock3],['novedades','Mis novedades',MessageSquare],['remuneracion','Mi remuneración',Wallet],['documentos','Documentos',FileText],['perfil','Perfil',UserRound]] as const;
export function Shell({ company, membership, profile, section, children }: { company: Company; membership: Membership; profile: Profile|null; section: string; children: ReactNode }) {
  const worker = membership.role_code === 'EMPLOYEE';
  const links = worker ? workerLinks : membership.role_code === 'SUPERVISOR' ? adminLinks.filter(x => ['','asistencia','novedades','proyectos'].includes(x[0])) : adminLinks;
  const name = profile?.display_name ?? 'Mi cuenta';
  return <div className={`app-shell ${worker ? 'worker-shell' : ''}`}>
    <a href="#contenido" className="skip-link">Saltar al contenido</a>
    <aside className="sidebar">
      <Brand light/>
      <Link href="/seleccionar-empresa?cambiar=1" className="company-switch"><Building2 size={20}/><span>{company.display_name}<small>Cambiar empresa</small></span><ChevronDown size={16}/></Link>
      <div className="sidebar-label">{worker ? 'MI ESPACIO' : 'ESPACIO DE TRABAJO'}</div>
      <nav aria-label={worker ? 'Portal trabajador' : 'Navegación administrativa'}>{links.map(([path,label,Icon]) => <Link key={path} href={`/empresas/${company.id}${path ? `/${path}` : ''}`} aria-current={path === section ? 'page' : undefined}><Icon size={19}/>{label}</Link>)}</nav>
      <div className="sidebar-bottom"><ShieldCheck size={18}/><span>Contexto protegido<small>Permisos por empresa</small></span></div>
    </aside>
    <div className="app-main">
      <header className="topbar"><span className="topbar-company"><Building2 size={17}/>{company.legal_name}</span><div className="account"><span className="avatar">{name.slice(0,1).toUpperCase()}</span><span>{name}<small>{membership.role_code.replaceAll('_',' ')}</small></span><form action={logout}><button className="icon-button" aria-label="Cerrar sesión" title="Cerrar sesión"><LogOut size={18}/></button></form></div></header>
      <main id="contenido" className="workspace">{children}</main>
      <footer className="app-footer">Nexo Laboral<span>{company.currency} · {company.timezone}</span></footer>
    </div>
  </div>;
}
