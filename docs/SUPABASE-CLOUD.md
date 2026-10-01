# Conectar Supabase Cloud de desarrollo

## 1. Crear el proyecto

En Supabase, crear una organización si aún no existe y un proyecto llamado, por ejemplo, `reloj-control-development`. Elegir la región y guardar la contraseña de base de datos en un gestor de contraseñas. No enviarla por chat. Este proyecto debe contener exclusivamente datos ficticios. Mantener producción en otro proyecto.

## 2. Instalar el esquema

En SQL Editor del proyecto vacío, pegar y ejecutar el contenido completo de `supabase/development-setup.sql`. Este archivo combina las dos migraciones versionadas y el seed de empresas. Ejecutarlo una sola vez sobre una base vacía. Para regenerarlo: `pnpm cloud:sql`. No volver a ejecutar el instalador sobre una base ya instalada; futuros cambios se aplican como nuevas migraciones.

Se crean ocho tablas públicas de aplicación, todas con RLS, y el limitador privado. Supabase mantiene `auth.users`. No crear manualmente tablas equivalentes ni desactivar RLS para solucionar errores.

## 3. Configurar Auth

En Authentication, habilitar el proveedor Email con contraseña y deshabilitar el registro público de usuarios y los usuarios anónimos. Establecer contraseña mínima de 12 caracteres. Mantener confirmación de correo para usuarios reales. El seed usa la API administrativa para crear cuentas ficticias ya confirmadas.

En URL Configuration:

- Site URL: `http://127.0.0.1:3000`.
- Redirect URLs: `http://127.0.0.1:3000/auth/callback` y `http://127.0.0.1:3000/auth/callback?next=/actualizar-contrasena`.

Utilizar esa misma dirección al abrir la app; no alternar localhost y 127.0.0.1. Para recuperación, abrir el enlace en el mismo navegador donde se solicitó: se usa PKCE. No añadir comodines de producción.

El correo SMTP predeterminado de Supabase limita los destinatarios a miembros del equipo del proyecto. Para enviar recuperación a otras personas, configurar SMTP propio en Authentication. Las direcciones `example.test` son ficticias y no reciben correos. La entrega y recuperación deben probarse con una cuenta real controlada por ti, separada de los fixtures, antes del piloto. No solicitar ni pegar credenciales SMTP en este chat.

## 4. Variables locales

Copiar `.env.example` como `.env.local` en la raíz del código. Obtener URL y clave publicable desde Connect/Settings → API Keys. Crear una clave secreta de backend para este proyecto de desarrollo. Usar las claves modernas `sb_publishable_...` y `sb_secret_...`.

```dotenv
APP_ENV=development
APP_URL=http://127.0.0.1:3000
SUPABASE_URL=https://REF_DEL_PROYECTO.supabase.co
SUPABASE_PUBLISHABLE_KEY=CLAVE_PUBLICABLE_DEL_PROYECTO
SUPABASE_SECRET_KEY=CLAVE_SECRETA_SOLO_SERVIDOR
RATE_LIMIT_HMAC_SECRET=VALOR_ALEATORIO_GENERADO_LOCALMENTE
TRUSTED_PROXY=none
ENABLE_ACCESS_MANAGEMENT=true
DEV_SUPABASE_PROJECT_REF=REF_DEL_PROYECTO
```

`REF_DEL_PROYECTO` es el texto anterior a `.supabase.co`. Generar HMAC en la terminal:

```sh
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

Guardar el resultado sólo en `.env.local`. Nunca usar prefijo `NEXT_PUBLIC` para secretos. `TRUSTED_PROXY=none` conserva el limitador por correo normalizado, sin confiar en IP enviada por el cliente; no se implementa limitación por IP en esta fase. La gestión de accesos está habilitada por la regla aprobada y continúa protegida por permisos y RLS. No hace falta la contraseña PostgreSQL para iniciar esta app.

## 5. Poblar y verificar

```sh
pnpm install --frozen-lockfile
pnpm run seed:users --confirm-development
pnpm dev
```

Entrar con las cuentas ficticias documentadas en README. En otra terminal, tras detener el navegador de pruebas si fuera necesario:

```sh
pnpm test:live
pnpm test:e2e:live
```

Las pruebas Cloud rechazan entornos distintos de development y referencias de proyecto inconsistentes. No se ejecutaron aún: requieren tu proyecto configurado. Probar manualmente la recuperación con correo real, renovación de sesión, caducidad, reinicio del navegador y suspensión desde una segunda sesión. Restaurar fixtures sólo en el proyecto ficticio si se alteran durante pruebas.

## 6. Otros entornos

Se incluyen `.env.staging.example` y `.env.production.example`; no se conectaron esos entornos. Mantener proyectos, claves, SMTP, datos y URLs separados. No usar el instalador con fixtures en producción. La configuración de Vercel, dominios, respaldo, observabilidad, MFA y validación de producción se revisará antes de desplegar; no se publicó la aplicación.

Fuentes oficiales: [claves API](https://supabase.com/docs/guides/getting-started/api-keys), [URLs de redirección](https://supabase.com/docs/guides/auth/redirect-urls), [SMTP](https://supabase.com/docs/guides/auth/auth-smtp).
