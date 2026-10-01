export const roles = ['ADMIN_GLOBAL', 'COMPANY_ADMIN', 'HR', 'SUPERVISOR', 'EMPLOYEE'] as const;
export type Role = typeof roles[number];
export type Company = { id: string; legal_name: string; display_name: string; code: string; timezone: string; currency: string; status: string };
export type Membership = { id: string; company_id: string; user_id: string; role_code: Role; status: string; valid_from: string; valid_until: string | null; version: number };
export type Profile = { user_id: string; display_name: string; locale: string };
export type ActionState = { error?: string; success?: string };
