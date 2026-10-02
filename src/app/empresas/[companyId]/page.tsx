import Link from 'next/link';
import {visibleCompanyContext} from '@/server/authorization';
import {Shell} from '@/components/shell';
import {AccessDeniedView,Badge,Card} from '@/components/ui';
import {Attendance} from '@/components/attendance';
export const dynamic='force-dynamic';
export default async function CompanyPage({params}:{params:Promise<{companyId:string}>}){
 const {companyId}=await params,c=await visibleCompanyContext(companyId);if(!c)return <AccessDeniedView/>;
 const worker=c.membership.role_code==='EMPLOYEE';
 let dashboard=null;
 if(!worker){const [employees,projects,sessions]=await Promise.all([c.client.from('employees').select('id',{count:'exact',head:true}).eq('company_id',companyId).eq('status','active'),c.client.from('projects').select('id',{count:'exact',head:true}).eq('company_id',companyId).eq('status','active'),c.client.from('attendance_sessions').select('state').eq('company_id',companyId).neq('state','FINISHED')]);if(employees.error||projects.error||sessions.error)throw new Error('DASHBOARD_UNAVAILABLE');dashboard=<><div className="info-grid"><Card><h3>Trabajadores activos</h3><strong>{employees.count??0}</strong></Card><Card><h3>Jornadas abiertas</h3><strong>{sessions.data.length}</strong><p>{sessions.data.filter(x=>x.state==='BREAK').length} en colación</p></Card><Card><h3>Proyectos activos</h3><strong>{projects.count??0}</strong></Card></div><div className="module-grid">{[['asistencia','Asistencia y alertas'],['trabajadores','Trabajadores y contratos'],['proyectos','Proyectos y asignaciones'],['novedades','Novedades'],['remuneraciones','Remuneraciones'],['liquidaciones','Liquidaciones']].filter(([path])=>c.membership.role_code!=='SUPERVISOR'||['asistencia','proyectos','novedades'].includes(path)).map(([path,label])=><Link className="module-tile" href={`/empresas/${companyId}/${path}`} key={path}>{label}</Link>)}</div></>;}
 return <Shell {...c} section=""><div className="page-heading"><div><span className="eyebrow">{worker?'MI ESPACIO':'ESPACIO DE TRABAJO'}</span><h1>Hola, {c.profile?.display_name??'bienvenido'}</h1><p>{c.company.legal_name}</p></div><Badge>{c.company.display_name}</Badge></div>{worker?<Attendance companyId={companyId} personal/>:dashboard}</Shell>;
}
