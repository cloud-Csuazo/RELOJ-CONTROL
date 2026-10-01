import 'server-only';
import { createHmac } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { config } from './config';

export async function allowAuthAttempt(kind: 'login'|'recovery'|'password', identity: string) {
  const env = config();
  const bucket = createHmac('sha256', env.RATE_LIMIT_HMAC_SECRET).update(`${kind}:${identity.toLowerCase()}`).digest('hex');
  // Privileged client exclusively for limiter RPC; never exported to data/query code.
  const limiter = createClient(env.SUPABASE_URL, env.SUPABASE_SECRET_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await limiter.rpc('take_auth_attempt', { p_bucket: bucket });
  if (error) throw new Error('RATE_LIMIT_UNAVAILABLE'); // Fail closed.
  return data === true;
}
