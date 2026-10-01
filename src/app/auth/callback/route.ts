import { NextResponse, type NextRequest } from 'next/server';
import { requestClient } from '@/server/supabase';
import { config } from '@/server/config';
import { cookies } from 'next/headers';
import { recoveryProof } from '@/server/recovery-proof';
export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get('code');
  const next = request.nextUrl.searchParams.get('next');
  const appUrl = config().APP_URL;
  if (code) {
    const client = await requestClient();
    const { data, error } = await client.auth.exchangeCodeForSession(code);
    if (!error && data.user) {
      const recovery = next === '/actualizar-contrasena';
      if (recovery) (await cookies()).set('recovery-authorized',recoveryProof(data.user.id),{httpOnly:true,secure:config().APP_ENV!=='development',sameSite:'lax',path:'/',maxAge:600});
      return NextResponse.redirect(new URL(recovery ? '/actualizar-contrasena' : '/seleccionar-empresa',appUrl));
    }
  }
  return NextResponse.redirect(new URL('/login?error=enlace',appUrl));
}
