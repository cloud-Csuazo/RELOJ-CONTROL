import { z } from 'zod';
export const idSchema = z.uuid();
export const loginSchema = z.object({ email: z.email().max(254).transform(v => v.trim().toLowerCase()), password: z.string().min(1).max(256) });
export const emailSchema = z.email().max(254).transform(v => v.trim().toLowerCase());
export const passwordSchema = z.string().min(12, 'Usa al menos 12 caracteres.').max(128);
export const profileSchema = z.object({ display_name: z.string().trim().min(2).max(100), locale: z.enum(['es-CL','en']) });
export function safeNext(path: unknown): string {
  return typeof path === 'string' && /^\/empresas\/[a-f0-9-]{36}(?:\/|$)/.test(path) && !path.includes('\\') ? path : '/seleccionar-empresa';
}
