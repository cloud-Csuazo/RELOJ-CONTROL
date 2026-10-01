import { NextResponse } from 'next/server';
import { identity, companyContext } from '@/server/authorization';
import { AccessDenied } from '@/modules/tenancy/domain/authorization';
import { configured } from '@/server/config';
export const dynamic='force-dynamic';
export async function GET(_request:Request,{params}:{params:Promise<{companyId:string}>}){
  if(!configured())return NextResponse.json({error:'CONFIGURATION_REQUIRED'},{status:503});
  if(!await identity())return NextResponse.json({error:'AUTHENTICATION_REQUIRED'},{status:401});
  try{const context=await companyContext((await params).companyId);return NextResponse.json({company:context.company,role:context.membership.role_code});}
  catch(error){if(error instanceof AccessDenied)return NextResponse.json({error:'ACCESS_DENIED'},{status:403});return NextResponse.json({error:'SERVICE_UNAVAILABLE'},{status:503});}
}
