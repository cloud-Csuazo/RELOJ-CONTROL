import {visibleCompanyContext} from '@/server/authorization';
import {Shell} from '@/components/shell';
import {AccessDeniedView} from '@/components/ui';
import {ProjectDetail} from '@/components/project-detail';
import {idSchema} from '@/shared/validation';
export const dynamic='force-dynamic';
export default async function ProjectPage({params}:{params:Promise<{companyId:string;projectId:string}>}){const {companyId,projectId}=await params;const c=await visibleCompanyContext(companyId);if(!c||!idSchema.safeParse(projectId).success)return <AccessDeniedView/>;return <Shell {...c} section="proyectos"><div className="page-heading"><h1>Ficha del proyecto</h1></div><ProjectDetail companyId={companyId} projectId={projectId}/></Shell>;}
