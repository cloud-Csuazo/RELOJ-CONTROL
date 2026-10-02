# Informe de Fase 1

Estado al 2 de octubre de 2026: implementación conectada a Supabase Cloud de desarrollo, con pruebas de Auth, RLS y navegador aprobadas. Recuperación por correo, renovación prolongada de sesión y preparación para producción siguen pendientes. No se inició Fase 2. No se confirma un número de trabajadores como requisito de dimensionamiento.

## Arquitectura y alcance

Monolito modular Next.js con separación de componentes visuales, acciones de servidor, autorización central y persistencia PostgreSQL. Supabase Auth administra identidad y contraseñas. Las sesiones se verifican en servidor con `getUser`; las cookies son HttpOnly, SameSite=Lax y Secure fuera de desarrollo. El proxy renueva cookies y aplica CSP con nonce. Los datos privados no se comparten mediante caché pública.

Implementado: login, logout, recuperación PKCE, actualización de contraseña con comprobante firmado de recuperación de diez minutos, perfil propio, empresas, memberships, roles, permisos, selector, layouts administrativos y trabajador, navegación según permisos, administración de accesos aprobada, auditoría y API mínima protegida. Para una sola empresa activa se entra directamente; varias muestran selector; ninguna muestra acceso pendiente.

La interfaz no expone funcionalidades de fases posteriores como si estuvieran terminadas. El registro mínimo `employees` permite vincular identidad y comprobar privacidad; no incluye CRUD de trabajadores, contratos o proyectos. No incluye marcación de asistencia, novedades, cálculos, cierres, documentos, reportes ni PWA.

## Modelo de datos

| Tabla | Función y relaciones |
|---|---|
| roles | Catálogo de cinco roles |
| permissions | Catálogo de capacidades |
| role_permissions | Relación muchos a muchos entre roles y permisos |
| companies | Empresa, estado, zona horaria IANA y versión |
| profiles | Perfil privado; user_id referencia auth.users |
| user_company_memberships | Relación única empresa/usuario, rol, estado, vigencia y versión |
| employees | Vínculo laboral mínimo por empresa, usuario opcional y nombre ficticio |
| audit_logs | Eventos por empresa con actor, motivo y campos modificados |

`auth.users` pertenece a Supabase. `private.auth_rate_limits` conserva contadores compartidos de intentos. Las FKs, unicidad empresa/usuario y la unicidad del vínculo laboral evitan relaciones duplicadas. La empresa acompaña cada registro laboral. Futuros módulos deberán usar referencias compuestas por empresa cuando relacionen entidades de negocio.

## Roles y RLS

| Rol | Alcance de Fase 1 |
|---|---|
| ADMIN_GLOBAL | Administración y consolidado de sus empresas asignadas; puede cambiar roles, suspender memberships y desactivar empresas |
| COMPANY_ADMIN | Lectura administrativa en su empresa; no modifica accesos |
| HR | Lectura laboral autorizada en su empresa; sin gestión de privilegios |
| SUPERVISOR | Navegación restringida; no se concede acceso general a trabajadores sin un modelo de asignación |
| EMPLOYEE | Perfil propio y su vínculo laboral, dentro de memberships activas |

Un rol no es global a la cuenta: puede variar por empresa. ADMIN_GLOBAL tampoco obtiene acceso automático a empresas nuevas. Los helpers SQL comprueban empresa activa, usuario autenticado, membership activa y vigencia en cada consulta; suspensión no espera a que caduque el JWT. Las ocho tablas públicas tienen RLS; clientes sin sesión no leen datos empresariales. Perfil propio sólo permite modificar campos autorizados. No se permite escritura directa de roles, memberships, empresas o auditoría desde clientes autenticados.

Las RPC administrativas revalidan el permiso dentro de SQL, bloquean filas, controlan versión para cambios concurrentes, exigen motivo y protegen al último ADMIN_GLOBAL activo. No existe creación de empresas o usuarios desde la interfaz en esta fase: el alta inicial se realiza mediante el proceso controlado de infraestructura. La desactivación exige confirmación textual. Reactivación y aprovisionamiento de empresas reales necesitan un procedimiento administrativo antes del piloto.

## Seguridad y auditoría

Los triggers escriben cambios de empresas y memberships dentro de la misma transacción y toman el actor de `auth.uid()`, sin confiar en un actor enviado por navegador. Se registran rol, estado, versión y motivo; no se vuelcan contraseñas ni remuneraciones. Clientes autenticados, incluido ADMIN_GLOBAL, no pueden insertar, editar ni eliminar eventos. Un administrador de infraestructura con privilegios de base de datos conserva capacidad técnica de alterar datos: append-only no equivale a inmutabilidad frente al propietario de PostgreSQL.

La clave secreta se importa exclusivamente desde servidor para el limitador compartido y desde el seed administrativo. Las lecturas de negocio utilizan el JWT y RLS. Limitador de cinco intentos por correo/operación cada quince minutos, HMAC para no conservar correo en el contador y denegación si falla el servicio. Sin dependencia de memoria de una sola instancia. Mensajes de login y recuperación genéricos. Acciones validan origen y payload; callbacks permiten sólo destinos fijos; logs contienen eventos y requestId, sin volcar errores privados.

## Decisiones de esta fase

1. Supabase Cloud separado de desarrollo, por elección del usuario; Docker opcional y no utilizado.
2. Gestión de privilegios sólo ADMIN_GLOBAL dentro de empresas asignadas, regla aprobada explícitamente. COMPANY_ADMIN conserva lectura administrativa.
3. Claves API modernas publicable/secreta y variables de entorno sin secretos versionados.
4. Fuente versionada de esquema en tres migraciones; instalador SQL sólo para un proyecto vacío ficticio.
5. Código publicado en GitHub RELOJ-CONTROL, rama main. Publicación no despliega aplicación ni modifica Supabase.
6. Sin nuevas funciones de Fase 2 hasta verificar las fundaciones contra el backend real.

## Validación

- 38 pruebas unitarias/SQL aprobadas, cero omitidas. Incluyen empresas A/B, IDs conocidos, perfiles, trabajador propio/otro de su misma empresa y otra empresa, ADMIN_GLOBAL sólo asignado, roles distintos por empresa, membership inactiva/expirada/futura, escalamiento de privilegios, auditoría inalterable, RPC positivas y negativas, concurrencia, último administrador y limitador.
- 10 pruebas de navegador aprobadas: login válido e inválido, selector, ingreso directo, manipulación de empresa, trabajador ajeno, administrador ajeno, inactivo, logout y recuperación con respuesta genérica. Doble de Auth exclusivo de pruebas; PostgreSQL ejecuta RLS real.
- TypeScript, lint y compilación de producción aprobados.
- Auditoría de dependencias de producción: no se encontraron vulnerabilidades conocidas en la revisión realizada.
- Capturas escritorio/móvil en `screenshots/`; verificado sin desbordamiento horizontal a 390 px. Pantallas: login, selector, administración y portal trabajador.
- Supabase Cloud de desarrollo conectado mediante `.env.local`, excluido de Git. Ocho cuentas ficticias creadas; diez pruebas directas de Auth/RLS y cinco pruebas de navegador Cloud aprobadas, sin omisiones. Login válido e inválido, aislamiento bidireccional, privacidad de trabajador, permisos administrativos, roles por empresa, memberships inactivas, escalamiento y auditoría protegida verificados contra el servicio real.
- Registro público y acceso anónimo deshabilitados; confirmación de correo habilitada. No se copiaron secretos al código ni a la documentación.

## Riesgos y condiciones antes del piloto

Comprobar Auth real, renovación, expiración y recuperación por correo con SMTP; revisar MFA de administradores; completar procedimiento de alta, baja y recuperación del último administrador; comprobar respaldos y restauración; revisar privilegios del equipo de infraestructura y protección de secretos. Medir disponibilidad, costos y volumen con uso real. Antes de asistencia formal se debe revisar la normativa aplicable y el proceso operacional; esta fase no declara cumplimiento legal automático ni calcula liquidaciones.

La integración Cloud básica está verificada. El cierre completo de Fase 1 depende de probar recuperación con entrega real de correo y los restantes escenarios de sesión. El SMTP y la validación de producción no se consideran resueltos por estas quince pruebas Cloud.
