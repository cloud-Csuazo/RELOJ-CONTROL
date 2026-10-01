import Link from 'next/link';
import { memberships } from '@/server/authorization';
import { Brand, CompanyLink, AccessDeniedView } from '@/components/ui';
export const dynamic = 'force-dynamic';
export default async function ConsolidatedPage(){
  const context=await memberships();
  const allowed=context.companies.filter(c=>context.memberships.some(m=>m.company_id===c.id&&m.role_code==='ADMIN_GLOBAL'));
  if(!allowed.length)return <AccessDeniedView/>;
  return <main className="selection-page"><Brand/><h1 style={{marginTop:50}}>Empresas autorizadas</h1><p className="muted">Acceso consolidado limitado a las empresas en las que tienes ADMIN_GLOBAL. Los reportes se incorporarán más adelante.</p><div className="selection-grid">{allowed.map(c=><CompanyLink key={c.id} id={c.id} name={c.legal_name} code={c.code} role="ADMIN_GLOBAL"/>)}</div><Link className="auth-back" href="/seleccionar-empresa?cambiar=1">← Volver a mis empresas</Link></main>;
}
