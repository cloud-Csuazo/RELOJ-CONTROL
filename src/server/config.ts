import 'server-only';
import { z } from 'zod';

const schema = z.object({
  APP_ENV: z.enum(['development','staging','production']),
  APP_URL: z.url(), SUPABASE_URL: z.url(),
  SUPABASE_PUBLISHABLE_KEY: z.string().min(20),
  SUPABASE_SECRET_KEY: z.string().min(20),
  RATE_LIMIT_HMAC_SECRET: z.string().min(32),
  TRUSTED_PROXY: z.enum(['none','vercel']).default('none'),
  ENABLE_ACCESS_MANAGEMENT: z.enum(['true','false']).default('false')
});
export function configured() {
  return schema.safeParse(process.env).success;
}
export function config() {
  const result = schema.safeParse(process.env);
  if (!result.success) throw new Error('CONFIGURATION_REQUIRED');
  const value = result.data;
  if (value.APP_ENV !== 'development' && (!value.APP_URL.startsWith('https://') || !value.SUPABASE_URL.startsWith('https://'))) throw new Error('HTTPS_REQUIRED');
  if (value.APP_ENV === 'development' && process.env.VERCEL_ENV === 'production') throw new Error('ENVIRONMENT_MISMATCH');
  return value;
}
