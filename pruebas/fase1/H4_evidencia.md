# OE-MIAPK-002 · H4 · Indicador E04 en vivo · Evidencia (10–11 nov 2026)

## Construido
- Migración `supabase/migrations/0003_h4_indicador_vivo.sql`: vista `miapk.v_indicadores` (security_invoker; solo Dirección aal2) con el indicador E04 n.º 1 **«PFV aceptados»**, alimentado por eventos `entrega.pfv.aceptado` de la fuente `laboratorio`: valor, valor anterior, último event_id, occurred/received, último error y estado.
- Cinco estados E04: **Pendiente** (fuente sin credencial activa) · **Error** (error del indicador posterior al último evento válido) · **Desactualizado** (fuente fuera de plazo) · **Sin datos** · **Confirmado**.
- `miapk.fuente_integrada()` (security definer, solo responde sí/no; no expone credenciales).
- Salvedades H3: comentario en `firma_verificada` (no es firma digital); columna `origen` en errores (11 previos = "prueba negativa H3"; nuevos se etiquetan solos).
- APK **v0.3.2**: tarjeta "En vivo · laboratorio" (Medición y Acceso seguro), consulta cada 10 s, muestra cambio de valor y "apareció aquí a los N s" (instante en que la APK vio el evento − `received_at` del servidor).
- Emisor `pruebas/fase1/h4_enviar.py` + workflow `h4-emisor.yml` (credencial solo por secreto). Registros en rama `resultados`, `h4_registro_1..4.jsonl`.

## Ensayo SQL (transacción revertida, sin rastro)
Sin datos → Pendiente (credencial inactiva) → Desactualizado (plazo 1 min) → evento aceptado: 1 / anterior 0 / Confirmado → duplicado: 1 / Confirmado → error posterior: 1 / Error.

## Prueba en el dispositivo real de Dirección (Android, MIAPK v0.3.2, sesión aal2)
| Hora COL | Envío | Servidor | Observado por Dirección |
|---|---|---|---|
| 10 nov 14:29:39 | PFV nuevo `lab-H4-1` | aceptado | Se actualizó sola: 0 · Sin datos → 1 · Confirmado ("los valores coinciden, se actualizó sola") |
| 10 nov 14:30:47 | Mismo PFV repetido | duplicado | El valor no cambió |
| 10 nov 14:31:00 | PFV mal formado `lab-H4-2` | rechazado (falta subject_id) | Estado Error; "último error 14:31" |
| 11 nov 07:39:35 | PFV nuevo `lab-H4-3` (medición) | aceptado | Se actualizó sola antes de recibir la instrucción; **"apareció aquí a los 1 s"** |

## Medición
Tiempo de llegada a la APK: **1 s** (medido en el dispositivo; tope por diseño ≤ 10 s por el ciclo de consulta). Requisito: < 60 s. **Cumple.**
Nota: el cálculo resta la hora del teléfono a la del servidor; un desfase de reloj de pocos segundos podría alterar la cifra, sin acercarla al límite de 60 s.
