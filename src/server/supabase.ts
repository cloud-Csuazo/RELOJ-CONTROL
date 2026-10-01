import 'server-only';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { config } from './config';

export async function requestClient() {
  const env = config();
  const store = await cookies();
  return createServerClient(env.SUPABASE_URL, env.SUPABASE_PUBLISHABLE_KEY, {
    cookieOptions: { httpOnly: true, secure: env.APP_ENV !== 'development', sameSite: 'lax', path: '/' },
    cookies: {
      getAll: () => store.getAll(),
      setAll: (values) => {
        try { values.forEach(({ name, value, options }) => store.set(name, value, { ...options, httpOnly: true, secure: env.APP_ENV !== 'development', sameSite: 'lax', path: '/' })); }
        catch { /* RSC cannot mutate cookies. proxy refreshes before rendering. */ }
      }
    }
  });
}
