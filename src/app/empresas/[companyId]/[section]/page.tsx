import { FolderClock } from 'lucide-react';
import { notFound } from 'next/navigation';
import { visibleCompanyContext } from '@/server/authorization';
import { Shell } from '@/components/shell';
import { AccessDeniedView, Card, Badge } from '@/components/ui';
import { ProfileForm } from '@/components/profile-form';
import { Administration } from '@/components/administration';
import { Workforce } from '@/components/workforce';
import { Attendance } from '@/components/attendance';
import { Novelties } from '@/components/novelties';
export const dynamic = 'force-dynamic';
const titles:Record<string,string>={trabajadores:'Trabajadores',asistencia:'Asistencia',jornada:'Mi jornada',novedades:'Novedades',proyectos:'Proyectos',remuneraciones:'Remuneraciones',remuneracion:'Mi remuneración',liquidaciones:'Liquidaciones',reportes:'Reportes',administracion:'Administración',documentos:'Documentos',perfil:'Perfil'};
export default async function ModulePage({params,searchParams}:{params:Promise<{companyId:string;section:string}>;searchParams:Promise<{q?:string;status?:string;page?:string;date?:string;month?:string}>}) {
  const {companyId,section}=await params;
  if(!titles[section]) notFound();
    const context=await visibleCompanyContext(companyId);
    if(!context)return <AccessDeniedView/>;
    if(context.membership.role_code==='EMPLOYEE'&&!['jornada','novedades','remuneracion','documentos','perfil'].includes(section)) return <AccessDeniedView/>;
    if(context.membership.role_code==='SUPERVISOR'&&!['asistencia','novedades','proyectos','perfil'].includes(section)) return <AccessDeniedView/>;
    return <Shell {...context} section={section}><div className="page-heading"><div><span className="eyebrow">{context.company.display_name}</span><h1>{titles[section]}</h1></div><Badge>Espacio de trabajo</Badge></div>{section==='perfil'&&context.profile ? <Card><ProfileForm profile={context.profile}/></Card> : section==='administracion' ? <Administration companyId={companyId}/> : ['trabajadores','proyectos'].includes(section)?<Workforce companyId={companyId} section={section} search={await searchParams}/>:['asistencia','jornada'].includes(section)?<Attendance companyId={companyId} personal={section==='jornada'} date={(await searchParams).date}/>:section==='novedades'?<Novelties companyId={companyId} search={await searchParams}/>:<Card className="placeholder"><FolderClock size={35}/><h2>Este módulo se incorporará en una próxima fase</h2><p>La estructura de navegación está preparada. Todavía no hay operaciones de {titles[section].toLowerCase()} disponibles.</p><p>Empresa y permisos se verifican también cuando ingresas directamente por URL.</p></Card>}</Shell>;
}

