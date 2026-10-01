import 'server-only';
import { redirect } from 'next/navigation';
import { requestClient } from './supabase';
import { idSchema } from '@/shared/validation';
import type { Company, Membership, Profile } from '@/shared/types';
import { AccessDenied, activeMembership } from '@/modules/tenancy/domain/authorization';

export async function identity() {
  const client = await requestClient();
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return null;
  const { data: profile, error: profileError } = await client.from('profiles').select('user_id,display_name,locale').eq('user_id', data.user.id).maybeSingle();
  if (profileError) throw new Error('PROFILE_UNAVAILABLE');
  return { client, user: data.user, profile: profile as Profile | null };
}
export async function requireIdentity() {
  const result = await identity();
  if (!result) redirect('/login');
  return result;
}
export async function memberships() {
  const context = await requireIdentity();
  const { data, error } = await context.client.from('user_company_memberships')
    .select('id,company_id,user_id,role_code,status,valid_from,valid_until,version')
    .eq('user_id',context.user.id).eq('status','active');
  if (error) throw new Error('MEMBERSHIPS_UNAVAILABLE');
  const items = (data as Membership[]).filter(m => activeMembership(m, context.user.id, m.company_id));
  const { data: companies, error: companiesError } = await context.client.from('companies')
    .select('id,legal_name,display_name,code,timezone,currency,status').eq('status','active').order('legal_name');
  if (companiesError) throw new Error('COMPANIES_UNAVAILABLE');
  return { ...context, memberships: items, companies: (companies as Company[]).filter(c => items.some(m => m.company_id === c.id)) };
}
export async function companyContext(companyId: string) {
  if (!idSchema.safeParse(companyId).success) throw new AccessDenied();
  const context = await requireIdentity();
  const { data: company, error: companyError } = await context.client.from('companies')
    .select('id,legal_name,display_name,code,timezone,currency,status').eq('id',companyId).maybeSingle();
  const { data: membership, error } = await context.client.from('user_company_memberships')
    .select('id,company_id,user_id,role_code,status,valid_from,valid_until,version')
    .eq('company_id',companyId).eq('user_id',context.user.id).maybeSingle();
  if (companyError || error) throw new Error('CONTEXT_UNAVAILABLE');
  if (!company || !membership || !activeMembership(membership as Membership, context.user.id, companyId) || company.status !== 'active') throw new AccessDenied();
  return { ...context, company: company as Company, membership: membership as Membership };
}
export async function requirePermission(companyId: string, permission: string) {
  const context = await companyContext(companyId);
  const { data, error } = await context.client.from('role_permissions').select('permission_code')
    .eq('role_code',context.membership.role_code).eq('permission_code',permission).maybeSingle();
  if (error) throw new Error('PERMISSIONS_UNAVAILABLE');
  if (!data) throw new AccessDenied();
  return context;
}
export async function visibleCompanyContext(companyId: string) {
  try { return await companyContext(companyId); }
  catch (error) { if (error instanceof AccessDenied) return null; throw error; }
}
