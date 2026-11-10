# OE-MIAPK-002 · H3 · Motor de eventos · Evidencia (10 nov 2026)

## Diseño (migración `supabase/migrations/0002_h3_motor_eventos.sql`)
- Única puerta de entrada: `public.miapk_ingerir_evento(credencial, evento)`, `security definer`, `search_path` vacío. Ejecutable por `anon`; sin permiso para `authenticated`/`public`.
- La **fuente se deduce de la credencial**, nunca del cuerpo. La credencial se guarda solo como hash SHA-256 en `miapk.credenciales_fuente` (RLS forzado, sin políticas: nadie la lee por la API). El valor lo creó Dirección como secreto de GitHub `MIAPK_CRED_LAB`; Magda nunca lo vio.
- No se cambió ningún permiso del esquema `miapk`, ni se habilitó escritura directa. No hay claves de servicio en la APK.
- Validación E03: event_id UUID, type `dominio.entidad.accion`, external_id, subject, data objeto, `ficticio=true` obligatorio en laboratorio, occurred_at válido y no futuro.
- Idempotencia: `unique (fuente_id, external_id, type)` + PK `event_id` → `on conflict do nothing` → "duplicado".
- Inválidos → `miapk.eventos_errores` con motivo y cuerpo.
- Trazabilidad: `received_at`, `occurred_at`, `fuente_id`, `firma_verificada`, `hash_cuerpo`; bitácora encadenada por hash (append-only).
- Recálculo E04: vista `miapk.v_resumen_fuentes` (security_invoker, visible solo a Dirección aal2): eventos, errores, último evento y semáforo Sin datos / Al día / Desactualizado / Con errores recientes.

## Pruebas reproducibles (`pruebas/fase1/h3_pruebas.py`, workflow `prueba-eventos.yml`)
Ejecución 2 (GitHub Actions, 12:22 COL) · registro redactado en rama `resultados`, `h3_registro_2.jsonl` · **RESUMEN: PASA (9/9)**

| # | Prueba | Resultado |
|---|---|---|
| 1 | Evento válido | aceptado |
| 2 | Doble envío idéntico | duplicado (cuenta una vez) |
| 3 | Mismo external_id con otro event_id | duplicado |
| 4 | type inválido | rechazado · a cola de errores |
| 5 | Dato no marcado ficticio | rechazado · a cola de errores |
| 6 | Credencial falsa | rechazado |
| 7 | Suplantar la fuente "pasarela" | rechazado ("no coincide con la credencial") |
| 8 | Escritura directa a `miapk.eventos` | HTTP 401 |
| 9 | Lectura anónima de `miapk.eventos` | HTTP 401 |

Ejecución 1 (antes de registrar el hash) rechazó todo por credencial inválida, como correspondía.

## Estado verificado en el servidor
- `eventos`: 1 (laboratorio.prueba.registrada · laboratorio · lab-H3-2 · firma verificada).
- `eventos_errores`: 11 (8 credencial inválida, 1 type, 1 ficticio, 1 suplantación).
- `bitacora`: 1 entrada con hash. Fuente `laboratorio`: activa. Semáforo: "Con errores recientes" (por las pruebas negativas).
- Ensayo previo en SQL dentro de transacción revertida: aceptado → duplicado → rechazado → rechazado; sin rastro.

## APK v0.3.1
Contador por `event_id` (corrige el 400), contador de eventos con error, estado por fuente, pestañas de referencia rotuladas "Referencia · sin conexión".
