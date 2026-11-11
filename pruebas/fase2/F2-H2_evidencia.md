# OE-MIAPK-003 · F2-H2 · Revocación efectiva de la sesión · Evidencia (11 nov 2026)

## Respaldo previo al cambio de esquema
Ejecución 6 de `h6-respaldo.yml` (12:51 COL): 23/23 PASA. SHA-256 `b6a96015b3cac8e9802666203d1308281afdcc322f4f01e760bb90033661e8a9`. **Sin cifrar** (el cifrado llega en F2-H5).

## Mecanismo
- **Servidor** (`supabase/migrations/0007_f2h2_revocacion.sql`, SHA-256 `fbdfdbbd…3e9f`). Se aplicó con el nuevo workflow `aplicar-migracion.yml` (psql en una sola transacción, con `ON_ERROR_STOP`), porque Chrome no estaba disponible.
  - `miapk.sesion_vigente()` (security definer) responde sí o no según si el `session_id` del JWT sigue en `auth.sessions` para ese usuario.
  - `es_direccion_mfa()` la exige. Por eso **todas** las políticas RLS y las funciones sensibles (aprobar o poner vigente un documento OSI) niegan el acceso a una sesión cerrada, **aunque su JWT siga siendo criptográficamente válido** hasta su vencimiento.
  - `auth.sessions` no es legible por `anon` ni por `authenticated` (verificado).
- **Distinción respetada:** revocar la sesión no invalida el JWT. Lo que pasa es que el servidor deja de concederle permisos.
- **APK v0.4.1:**
  - «Cerrar sesión» y el cierre por inactividad llaman a `/auth/v1/logout?scope=local` antes de olvidar la sesión. Si el acceso venció, primero lo renuevan, solo para poder cerrarlo.
  - «Todos los dispositivos» usa `cerrar_mis_sesiones` y además `scope=global`.
- **Prueba en el dispositivo:** el acceso anterior se guarda **solo en memoria** y nunca se muestra. Tras el cierre, se reintenta leer `programas` y aprobar un documento OSI cada 3 s, hasta 60 s.

## Verificación en el servidor (`pruebas/fase2/f2h2_verificar.sql`, transacción revertida)
1. JWT aal2 de Dirección con una sesión inexistente: lee programas → **0**; aprobar OSI → **rechazado**.
2. JWT sin `session_id` → **0**.
3. Control con una sesión viva → **8**.
4. La misma sesión, después de borrarla → **0**.

## Prueba en el Android de Dirección (v0.4.1, vigencia del acceso: 60 min)
| Hora COL | Modo | Antes | Cierre | Con el acceso anterior |
|---|---|---|---|---|
| 13:04:29 | Cerrar sesión | 8 programas | servidor confirmó | **0 s**: programas 0 · aprobar OSI rechazado · **PASA** |
| 13:05:34 | Inactividad (15 min simulados) | 8 | servidor confirmó | **0 s**: 0 · rechazado · **PASA** |
| 13:06:26 | Todos los dispositivos | 8 | servidor cerró 3 sesiones | **0 s**: 0 · rechazado · **PASA** |

Capturas en `pruebas/fase2/f2h2_capturas/`, con su SHA-256.
APK v0.4.1, SHA-256 `aac6af9a49fa7932fbd97197a35f22f4b20b4781d2841f5aa9995f43d8a92299`.

## Límites y pendientes
- **Vigencia del JWT de 10 min: NO verificada.** El acceso dura hoy 60 min, según el token. Ajustarlo requiere el panel de Supabase, y la sesión de Dirección no estaba abierta en el navegador disponible. Queda pendiente, como segunda capa: la revocación ya no depende de él.
- La inactividad se **simuló** adelantando el reloj interno de la app. La expiración real de 15 min se probó en la Fase 1 (11:26), y ahora usa el mismo camino de revocación.
- Un JWT revocado sigue siendo aceptado por PostgREST como identidad, pero sin permisos. Las funciones públicas que no usan `es_direccion_mfa` (por ejemplo, la ingesta con credencial) no dependen de la sesión de usuario.
- Si el teléfono está sin conexión al cerrar sesión, la revocación en el servidor no se confirma; la app lo avisa.
