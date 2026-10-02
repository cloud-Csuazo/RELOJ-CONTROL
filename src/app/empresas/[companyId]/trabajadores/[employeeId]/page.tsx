import {visibleCompanyContext} from '@/server/authorization';
import {Shell} from '@/components/shell';
import {AccessDeniedView} from '@/components/ui';
import {EmployeeDetail} from '@/components/employee-detail';
import {idSchema} from '@/shared/validation';
export const dynamic='force-dynamic';
export default async function EmployeePage({params}:{params:Promise<{companyId:string;employeeId:string}>}){const {companyId,employeeId}=await params;const c=await visibleCompanyContext(companyId);if(!c||!idSchema.safeParse(employeeId).success)return <AccessDeniedView/>;return <Shell {...c} section="trabajadores"><div className="page-heading"><h1>Ficha del trabajador</h1></div><EmployeeDetail companyId={companyId} employeeId={employeeId}/></Shell>;}
