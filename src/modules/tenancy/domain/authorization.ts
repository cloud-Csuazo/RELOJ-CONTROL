import type { Membership } from '@/shared/types';
export function activeMembership(membership: Membership, userId: string, companyId: string, now = Date.now()): boolean {
  return membership.user_id === userId && membership.company_id === companyId && membership.status === 'active'
    && new Date(membership.valid_from).getTime() <= now
    && (membership.valid_until === null || new Date(membership.valid_until).getTime() > now);
}
export class AccessDenied extends Error {
  constructor() { super('ACCESS_DENIED'); this.name = 'AccessDenied'; }
}
