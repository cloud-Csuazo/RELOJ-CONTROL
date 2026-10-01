import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

export async function proxy(request: NextRequest) {
  const nonce = Buffer.from(crypto.randomUUID()).toString('base64');
  const development = process.env.APP_ENV === 'development' || !process.env.APP_ENV;
  const csp = `default-src 'self'; script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${development ? " 'unsafe-eval'" : ''}; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'${development ? ' ws:' : ''}; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'`;
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set('x-nonce', nonce);
  requestHeaders.set('Content-Security-Policy', csp);
  const makeResponse = () => {
    requestHeaders.set('cookie', request.headers.get('cookie') ?? '');
    const result = NextResponse.next({ request: { headers: requestHeaders } });
    result.headers.set('Cache-Control', 'private, no-store');
    result.headers.set('Content-Security-Policy', csp);
    return result;
  };
  let response = makeResponse();
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) return response;
  const secure = process.env.APP_ENV !== 'development';
  const supabase = createServerClient(url,key,{
    cookieOptions: { httpOnly: true, secure, sameSite: 'lax', path: '/' },
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (cookies) => {
        cookies.forEach(({name,value}) => request.cookies.set(name,value));
        response = makeResponse();
        cookies.forEach(({name,value,options}) => response.cookies.set(name,value,{...options,httpOnly:true,secure,sameSite:'lax',path:'/'}));
      }
    }
  });
  // Refresh before RSC; actual authorization also occurs in each protected read/action.
  await supabase.auth.getUser();
  return response;
}
export const config = { matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'] };
