# Desarrollo operativo — 2 de octubre de 2026

La instrucción de continuar las fases 1–9 sustituye la pausa anterior al finalizar Fundaciones. El código sigue en este repositorio; el nombre de carpeta `fase-1` se conserva para no romper configuración y enlaces.

## Personas y proyectos

Operativo en Supabase Cloud DEV: fichas individuales, RUT módulo 11 en cliente y SQL, estados y fechas, contratos históricos sin superposición, términos auditados, cargos, centros de costo, proyectos, ubicaciones esperadas, asignaciones de trabajador y supervisor. La relación laboral no crea una cuenta de acceso automáticamente. Se separan los datos personales y contratos para que la supervisión asignada no lea sueldos ni datos personales.

Los cambios de fichas y proyectos comprueban versión y motivo. Las tablas tienen RLS y escrituras sólo mediante RPC autorizadas. Las relaciones entre entidades de empresa usan claves compuestas. Los contratos y asignaciones conservan versiones históricas; terminar un contrato no permite sobrescribir su historial.

Pendientes de mejora: gestión de vinculación/invitación de cuentas, selección paginada para volúmenes grandes, edición histórica de ubicaciones y filtros de proyectos. No afirmar Fase 2 exhaustivamente terminada mientras falten estos puntos.

## Asistencia

Operativo en DEV: inicio, colación, retorno y fin; transacciones serializadas por trabajador; una jornada abierta; idempotencia con verificación del mismo payload; hora oficial UTC de PostgreSQL; zona de visualización de empresa; hora del dispositivo separada; GPS puntual y precisión; ubicación esperada y distancia; alertas sin bloquear por ausencia de GPS o distancia; historial, vista administrativa y solicitudes de corrección. La aprobación exige otro administrador y conserva la hora original.

IndexedDB guarda hasta 50 solicitudes pendientes por cuenta/empresa. Se envían en orden con el identificador y payload originales; una respuesta perdida no genera un segundo evento. No guarda claves ni sesión. El cambio de cuenta retira la cola de la otra identidad; solicitudes de más de 48 horas se retiran con aviso. La sincronización se detiene ante un rechazo y conserva las pendientes restantes. Sólo solicita GPS al marcar. La cola no reemplaza el registro confirmado del servidor.

Limitaciones: sin proxy confiable en el entorno local, `ip` queda desconocida; no confiar en una IP declarada por el cliente. User-Agent y características del dispositivo son declaraciones para auditoría, no identidad comprobada. El modo sin conexión requiere cargar la aplicación previamente; instalación PWA y recarga completamente offline siguen en Fase 9. Corregir en la interfaz está limitado al mismo día local del evento; cambios de día y jornadas abiertas que perdieron su secuencia requieren un flujo posterior. Falta integrar bloqueo de períodos y manejo de pendientes rechazadas.

## Novedades

Esquema y formularios implementados: horas extra, gastos, reembolso, adelanto, viático, permisos, ausencias y otras novedades; borrador, envío, revisión, aprobación total/parcial, rechazo, cancelación y pagos trazados. Los pagos son registros de transferencias realizadas externamente; la app no mueve dinero. La solicitud, aprobación y pago se mantienen separados, con límite de saldo e idempotencia. Ninguna persona puede aprobar/pagar su propia solicitud.

La supervisión ve sólo novedades operativas de personas asignadas; los adelantos y gastos no se exponen por defecto. Categorías de gastos configurables y comentarios append-only. Adjuntos y comprobantes se incorporan con Storage privado en Fase 7. La estimación, deducción de adelantos y cierre todavía no están disponibles en esta revisión.

## Evidencia y configuración

Migraciones 004, 005, 006 y 007 instaladas en `Cloud9-Suacof-dev`; no volver a ejecutar el instalador completo sobre este proyecto. El instalador acumulado se reserva para un proyecto vacío. Recuperación por correo real y SMTP siguen pendientes; no bloquean el resto del desarrollo.

Comprobaciones actuales: 78 pruebas unitarias/SQL aprobadas, 20 pruebas directas contra Supabase real aprobadas; 7 pruebas anteriores de navegador y la nueva prueba de asistencia offline aprobadas. La prueba de navegador de adelanto, revisión independiente, aprobación parcial y pago ficticio también fue aprobada. La compilación de esta revisión está en verificación. Las capturas usan exclusivamente cuentas/datos ficticios de desarrollo.

El proyecto sigue siendo de desarrollo: no está desplegado como producción, no es un control de asistencia legalmente certificado y no calcula liquidaciones legales definitivas. Las fases restantes siguen abiertas.

