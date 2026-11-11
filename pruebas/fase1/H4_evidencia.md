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

---
## Adenda (11 nov 2026, 08:10 COL) · observaciones del dictamen de Magid

### (1) Seis módulos en el dispositivo real
Capturas tomadas por Dirección en su Android, 08:07–08:09 COL, MIAPK v0.3.2, sesión aal2 activa ("Acceso seguro · Conectado"). Archivos en `pruebas/fase1/h4_capturas/` con SHA-256 en `SHA256SUMS.txt`:

| Módulo | Captura | SHA-256 |
|---|---|---|
| Pulso | 1_pulso.jpg | 49d39dd8f4ff49d0ab15190043d1eea63b10fa51138005daf6abc4f1c2a8ad94 |
| Programas | 2_programas.jpg | 1039ba603a4772d8f84b681074e0e22e2a135e78fc8f25dc05fffbcdd1d6e5ed |
| Órdenes | 3_ordenes.jpg | d4a07dcc23b7518aad25220bab64ec95fadac12046008603b241677ff37e5ddf |
| Medición | 4_medicion.jpg | 07e780df8cdddc33f07333a4cf10e1b636653ae4a1346078da001c39aba78286 |
| MÍA | 5_mia.jpg | 1a2f1554f31dc7bd089af940b42d18afc2ace2e551ec423d9b984ba4682efbc4 |
| OSI | 6_osi.jpg | 2425bccabb0d8dc0d698dcaeb2edbb27f68775ee73002463081b0c165709ac2f |

Medición (08:08:40): "PFV aceptados · Valor 2 · anterior 1 · Confirmado"; "Último evento · Recibido 7:39:35 · apareció aquí a los 1 s"; "Último error de este indicador · 14:31:00".

Hallazgos honestos en las capturas (no de seguridad):
- Solo la tarjeta "En vivo" usa datos del servidor. Los seis módulos muestran contenido de referencia embebido, rotulado "Referencia · sin conexión".
- Contenido de referencia desactualizado: Pulso y Órdenes listan OE-MIAPK-001 "En ejecución" (cerrada documentalmente) y no muestran OE-MIAPK-002 ni CSW 003. Medición mantiene el texto "Ningún indicador tiene datos todavía" y la fila de referencia "PFV aceptados · Pendiente" debajo de la tarjeta en vivo, que dice "2 · Confirmado". Se corregirá en la próxima versión de la APK.

### (2) Trazabilidad del cronometraje (medición del 11 nov)
| Marca | Reloj | Hora |
|---|---|---|
| Envío del emisor (GitHub Actions) | runner, UTC | 12:39:35.705 |
| Respuesta "aceptado" del servidor | runner, UTC | 12:39:35.967 |
| `received_at` del evento (lo muestra la APK) | servidor Supabase | 07:39:35 COL = 12:39:35 UTC |
| Primera vez que la APK vio el evento | teléfono | ≈ 1 s después de `received_at` |

- Cálculo de la APK: hora del teléfono al detectar el evento − `received_at` del servidor = 1 s.
- **Incertidumbre:**
  - El ciclo de consulta es de 10 s, así que el retardo esperado está entre 0 y 10 s más la latencia de red. Un 1 s indica que la consulta coincidió justo después de la llegada.
  - Un desfase entre el reloj del teléfono (sincronizado por la red móvil) y el del servidor alteraría la cifra en esa misma magnitud.
  - Cota superior conservadora: 10 s de ciclo + desfase de reloj + latencia, muy por debajo de 60 s.
- La prueba del 10 nov (14:29:39) cumplió también: Dirección vio el cambio en el primer vistazo. Ese día no se registraron los segundos.

### (3) Estados vistos en Android vs. ensayados en SQL
| Estado | Visto en Android por Dirección | Ensayado en SQL (revertido) |
|---|---|---|
| Sin datos | Sí (antes del primer PFV, 10 nov) | Sí |
| Confirmado | Sí (1 el 10 nov; 2 el 11 nov) | Sí |
| Error | Sí (10 nov 14:31) | Sí |
| Pendiente | **No** | Sí (credencial inactiva) |
| Desactualizado | **No** | Sí (plazo vencido) |

### (4) Versión, hash y reproducibilidad
- APK: **MIAPK v0.3.2** (versionCode 5).
- SHA-256 de la APK: `f9e019f1a2c12e8194c9f99be928d8cc8b1d12aff59dbcbfa30c15589628c586`.
- Fuente: commit `7988fd8` en `main`. La compilación quedó en la rama `apk` (commit `3bd7304`, 10 nov 19:05 UTC) y en GitHub Releases. Clave de firma estable.
- Reproducible:
  1. Escribir `pfv|duplicado|error <external_id>` en `pruebas/fase1/h4_ejecutar.txt` y hacer push a `main`.
  2. El workflow `h4-emisor.yml` envía el evento.
  3. El registro queda en la rama `resultados` (`h4_registro_1..4.jsonl`).
  4. El ensayo de los 5 estados es el bloque SQL descrito arriba (transacción con ROLLBACK).
