import 'server-only';
import {companyContext} from '@/server/authorization';
export async function workforceContext(companyId:string,search:{q?:string;status?:string;page?:string}={}){
 const c=await companyContext(companyId);
 const page=Math.max(1,Math.min(10000,Number.parseInt(search.page??'1',10)||1));
 let employeesQuery=c.client.from('employees').select('id,display_name,status,job_title,hired_on,ended_on,version',{count:'exact'}).eq('company_id',companyId);
 if(search.status==='active'||search.status==='inactive')employeesQuery=employeesQuery.eq('status',search.status);
 const q=(search.q??'').trim().slice(0,80);
 if(q){const rut=q.replace(/[.\s]/g,'').toUpperCase();if(/^\d{7,8}-[\dK]$/.test(rut)){const result=await c.client.from('employee_personal_data').select('employee_id').eq('company_id',companyId).eq('rut',rut);if(result.error)throw new Error('WORKFORCE_UNAVAILABLE');employeesQuery=employeesQuery.in('id',(result.data??[]).map(r=>r.employee_id));}else employeesQuery=employeesQuery.ilike('display_name',`%${q.replace(/[%_]/g,'')}%`);}
 const responses=await Promise.all([
  employeesQuery.order('display_name').order('id').range((page-1)*25,page*25-1),
  c.client.from('projects').select('id,code,name,client_name,description,starts_on,ends_on,cost_center_id,status,version').eq('company_id',companyId).order('name').limit(100),
  c.client.from('cost_centers').select('id,code,name,status,version').eq('company_id',companyId).order('name').limit(100),
  c.client.from('employee_project_assignments').select('id,employee_id,project_id,starts_on,ends_on,status,version').eq('company_id',companyId).order('starts_on',{ascending:false}).limit(100),
  c.client.from('role_permissions').select('permission_code').eq('role_code',c.membership.role_code).eq('permission_code','workforce.manage').maybeSingle()
 ]);
 if(responses.some(r=>r.error))throw new Error('WORKFORCE_UNAVAILABLE');
 return {...c,employees:responses[0].data??[],employeeCount:responses[0].count??0,page,projects:responses[1].data??[],centers:responses[2].data??[],assignments:responses[3].data??[],canManage:!!responses[4].data};
}
