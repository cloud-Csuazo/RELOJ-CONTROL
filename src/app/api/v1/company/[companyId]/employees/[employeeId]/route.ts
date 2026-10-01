import { NextResponse } from 'next/server';
import { identity, companyContext } from '@/server/authorization';
import { configured } from '@/server/config';
import { idSchema } from '@/shared/validation';
import { AccessDenied } from '@/modules/tenancy/domain/authorization';
export const dynamic='force-dynamic';
export async function GET(_request:Request,{params}:{params:Promise<{companyId:string;employeeId:string}>}){
  if(!configured())return NextResponse.json({error:'CONFIGURATION_REQUIRED'},{status:503});
  if(!await identity())return NextResponse.json({error:'AUTHENTICATION_REQUIRED'},{status:401});
  try{
    const {companyId,employeeId}=await params;
    if(!idSchema.safeParse(employeeId).success)throw new AccessDenied();
    const context=await companyContext(companyId);
    const {data,error}=await context.client.from('employees').select('id,company_id,display_name,status').eq('company_id',companyId).eq('id',employeeId).maybeSingle();
    if(error)throw new Error('EMPLOYEE_READ_FAILED');
    if(!data)throw new AccessDenied();
    return NextResponse.json({employee:data});
  }catch(error){if(error instanceof AccessDenied)return NextResponse.json({error:'ACCESS_DENIED'},{status:403});return NextResponse.json({error:'SERVICE_UNAVAILABLE'},{status:503});}
}
