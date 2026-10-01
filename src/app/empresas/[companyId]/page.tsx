import { Building2, ShieldCheck, Users, Clock3, FolderKanban, MessageSquare, Wallet, FileText, ArrowRight } from 'lucide-react';
import Link from 'next/link';
import { visibleCompanyContext } from '@/server/authorization';
import { Shell } from '@/components/shell';
import { AccessDeniedView, Badge, Card } from '@/components/ui';
export const dynamic = 'force-dynamic';
export default async function CompanyPage({params}:{params:Promise<{companyId:string}>}) {
  const {companyId} = await params;
    const context = await visibleCompanyContext(companyId);
    if (!context) return <AccessDeniedView/>;
    const worker = context.membership.role_code==='EMPLOYEE';
    return <Shell {...context} section=""><div className="page-heading"><div><span className="eyebrow">{worker?'MI ESPACIO':'ESPACIO DE TRABAJO'}</span><h1>Hola, {context.profile?.display_name ?? 'bienvenido'}</h1><p>Estás en {context.company.legal_name}.</p></div><Badge>FUNDACIONES · FASE 1</Badge></div><section className="welcome-card"><div><h2>Tu espacio ya tiene una base.</h2><p>Tu identidad, tu empresa y tus permisos definen el contenido al que puedes acceder. Los módulos operativos se incorporarán en las siguientes fases.</p><Link className="button secondary" href="/seleccionar-empresa?cambiar=1">Ver mis empresas <ArrowRight size={16}/></Link></div><span className="welcome-symbol"><Building2 size={40}/></span></section><div className="info-grid"><Card><Building2 size={23}/><h3>Empresa actual</h3><p>{context.company.display_name}</p></Card><Card><ShieldCheck size={23}/><h3>Tu permiso</h3><p>{context.membership.role_code.replaceAll('_',' ')}</p></Card><Card><Users size={23}/><h3>Tu cuenta</h3><p>{context.profile?.display_name ?? 'Perfil pendiente'}</p></Card></div><div className="section-heading"><h2>{worker?'Lo que viene para tu jornada':'Módulos en próximas fases'}</h2><span className="muted" style={{fontSize:11}}>Sin datos simulados</span></div><div className="module-grid">{[[Clock3,'Asistencia','Jornada y marcaciones'],[MessageSquare,'Novedades','Solicitudes y aprobaciones'],[FolderKanban,'Proyectos','Asignaciones y costos'],[Wallet,'Remuneraciones','Estimación y cierre'],[FileText,'Documentos','Archivos privados'],[Users,'Trabajadores','Personas y contratos']].map(([Icon,title,description])=><div className="module-tile" key={String(title)}><Icon size={24}/><div><h3>{String(title)}</h3><p>{String(description)}</p></div></div>)}</div></Shell>;
}
