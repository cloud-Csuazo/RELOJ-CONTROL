import {z} from 'zod';
export function normalizeRut(value:string){return value.replace(/[.\s]/g,'').toUpperCase();}
export function validRut(value:string){const rut=normalizeRut(value);if(!/^\d{7,8}-[\dK]$/.test(rut))return false;const [body,digit]=rut.split('-');if(Number(body)===0)return false;let sum=0,factor=2;for(let i=body.length-1;i>=0;i--){sum+=Number(body[i])*factor;factor=factor===7?2:factor+1;}const check=11-sum%11;return digit===(check===11?'0':check===10?'K':String(check));}
const optionalText=(max:number)=>z.string().trim().max(max).default('');
const date=z.union([z.iso.date(),z.literal('')]).default('');
const uuid=z.union([z.uuid(),z.literal('')]).default('');
const status=z.enum(['active','inactive']).default('active');
export const workforceData=z.discriminatedUnion('kind',[
 z.object({kind:z.literal('employee'),display_name:z.string().trim().min(2).max(100),status,job_title:optionalText(120),hired_on:date,ended_on:date,user_id:uuid,rut:optionalText(12).transform(normalizeRut).refine(v=>!v||validRut(v),'RUT inválido'),email:z.union([z.email(),z.literal('')]).default(''),phone:optionalText(40),address:optionalText(300),born_on:date}),
 z.object({kind:z.literal('cost_center'),code:z.string().trim().min(1).max(40),name:z.string().trim().min(2).max(120),status}),
 z.object({kind:z.literal('project'),code:z.string().trim().min(1).max(40),name:z.string().trim().min(2).max(160),status:z.enum(['active','inactive','completed']),client_name:optionalText(160),description:optionalText(2000),starts_on:date,ends_on:date,cost_center_id:uuid}),
 z.object({kind:z.literal('contract'),employee_id:z.uuid(),contract_type:z.enum(['indefinite','fixed_term','project']),job_title:z.string().trim().min(2).max(120),starts_on:z.iso.date(),ends_on:date,weekly_minutes:z.coerce.number().int().min(1).max(10080),base_salary:z.string().regex(/^\d{1,12}$/).refine(v=>/^\d{1,12}$/.test(v)&&BigInt(v)<=100000000000n),schedule:optionalText(1000)}),
 z.object({kind:z.literal('project_assignment'),employee_id:z.uuid(),project_id:z.uuid(),starts_on:z.iso.date(),ends_on:date}),
 z.object({kind:z.literal('supervisor_assignment'),employee_id:z.uuid(),supervisor_user_id:z.uuid(),starts_on:z.iso.date(),ends_on:date}),
 z.object({kind:z.literal('location'),project_id:z.uuid(),name:z.string().trim().min(2).max(160),address:optionalText(300),latitude:z.coerce.number().min(-90).max(90),longitude:z.coerce.number().min(-180).max(180),radius_meters:z.coerce.number().int().min(1).max(100000)})
]);
