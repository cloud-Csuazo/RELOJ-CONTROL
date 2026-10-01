# RELOJ-CONTROL — Fase 1

Fundaciones de una aplicación multiempresa para SUACOF Solutions SpA y CLOUD 9 SpA. Nombre visual provisional: Nexo Laboral. No incluye todavía asistencia, remuneraciones ni liquidaciones.

Next.js, TypeScript, Tailwind, Supabase Auth y PostgreSQL con RLS. Una identidad puede tener distintos roles en empresas diferentes. Cada consulta normal utiliza la sesión del usuario; la clave secreta del servidor se reserva al limitador de intentos y al script explícito de datos ficticios.

## Inicio

Requiere Node 24 y pnpm 11.19.0. No requiere Docker para usar Supabase Cloud.

1. Seguir `docs/SUPABASE-CLOUD.md` y preparar un proyecto separado de desarrollo.
2. Copiar `.env.example` a `.env.local` y completar los valores localmente.
3. Ejecutar `pnpm install --frozen-lockfile`.
4. Ejecutar `pnpm run seed:users --confirm-development` sólo en ese proyecto ficticio.
5. Ejecutar `pnpm dev` y abrir http://127.0.0.1:3000.

Acceso ficticio: `global@example.test`, contraseña `Local-Fixture-Only-2026!`. También existen admin, supervisor, suacof, cloud9, colega, multi e inactivo con el dominio `example.test` y esa contraseña. Son cuentas de pruebas; no usar en producción. El script inicializa perfiles y membresías, y nunca debe usarse con personas reales.

## Comprobaciones

```sh
pnpm lint
pnpm typecheck
pnpm test
pnpm build
pnpm test:e2e
```

En Windows las pruebas de navegador utilizan Edge instalado; en otros sistemas ejecutar antes `pnpm exec playwright install chromium`. Las pruebas SQL ejecutan las migraciones reales en PostgreSQL mediante PGlite. El navegador usa un doble de contrato exclusivo de pruebas para Auth y consulta esa base con RLS. No prueba la infraestructura de Supabase Cloud. Después de configurar el proyecto y los fixtures ejecutar `pnpm test:live` y `pnpm test:e2e:live`.

## Archivos

- `src/server`: sesiones, autorización, configuración y limitador.
- `src/modules`: autenticación y administración por empresa.
- `src/app`: páginas, layouts y API protegida.
- `src/proxy.ts`: renovación de cookies y política CSP.
- `supabase/migrations`: cambios versionados de esquema y permisos.
- `supabase/development-setup.sql`: instalación inicial para un proyecto vacío de desarrollo; generar con `pnpm cloud:sql`.
- `tests`: pruebas unitarias, SQL, navegador y conexión Cloud.
- `screenshots`: capturas verificadas de escritorio y móvil.
- `docs/INFORME-FASE-1.md`: arquitectura, decisiones, alcance, resultados y pendientes.
- `docs/GITHUB.md`: publicación del código.

Los comandos `db:start/reset/stop` son una alternativa futura con Docker; no forman parte del flujo Cloud elegido. No hay despliegue ni aplicación automática de migraciones. Detener el desarrollo funcional antes de Fase 2 hasta validar la integración real.
