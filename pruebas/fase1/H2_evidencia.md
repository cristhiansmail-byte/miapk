# OE-MIAPK-002 · H2 · Acceso seguro · Evidencia (10 nov 2026)

APK: MIAPK v0.3.0 (compilación GitHub Actions, clave de firma estable). Servidor: `miapk-laboratorio` (Supabase Free).

## Configuración verificada en el servidor
- Usuarios totales: 1 (Dirección, leverageinnerfocuseveryday@gmail.com), correo confirmado.
- Factores TOTP verificados: 1. Actores con hat `direccion`: 1 (vinculado a ese usuario).
- Registro de cuentas nuevas **deshabilitado**. Prueba: `POST /auth/v1/signup` con un correo intruso → **HTTP 422 `signup_disabled`**.
- Esquema `miapk` expuesto a la API; sin sesión → **HTTP 401 "permission denied for schema miapk"**.

## Prueba observada por Dirección en su Android (11:50–11:54 COL)
| Paso | Resultado reportado por Dirección |
|---|---|
| Contraseña correcta, **sin** código TOTP (aal1): "Datos visibles ahora, sin doble verificación" | **0 · correcto** |
| Con código TOTP (aal2): "Programas en el servidor" | **8** |
| Cerrar sesión y reabrir la app | Pide contraseña de nuevo (no conserva acceso) |

## Observaciones
- "Eventos registrados" mostró `rechazado (400)`: defecto de la app (consultaba la columna `id`, la tabla usa `event_id`). Se corrige en v0.3.1 junto con H3. No es un fallo de seguridad.
- La pestaña "Programas" muestra contenido de referencia embebido (sin servidor); se rotulará "Referencia · sin conexión" para evitar confusión.
- Cierre por inactividad (15 min) y "Cerrar sesión en todos los dispositivos" implementados; su prueba formal queda para el bloque 2 de E09 (H8).
