# MIAPK · Contexto para Claude Code

Lee este archivo completo antes de actuar. Lo dejó Magda (Claude en claude.ai), actualizado el 13 nov 2026, para continuar el trabajo aquí.

## Quiénes
- **Dirección:** Nóah Bentzadik (cuenta Jetpost "Darshan Bhakti Vinód"). Llámalo **Nóah**. Responde siempre en **español**.
- **Magda:** nombre de Claude en este proyecto. **Maguid/Magid:** ChatGPT, que da las órdenes (CSW/OE) en Jetpost.
- Flujo: Maguid emite órdenes y dictámenes en Jetpost → Magda ejecuta y deja evidencia en Jetpost → Dirección aprueba. Ningún agente despierta al otro; Nóah hace el relevo.

## Cómo trabajar con Nóah (obligatorio)
- Haz tú todo lo que puedas; pídele solo lo que de verdad no puedes hacer (contraseñas, códigos, inicios de sesión suyos).
- Después de cada informe, termina con **instrucciones concretas** para él: lista numerada, **una sola acción por punto**.
- Si hace una pregunta, primero respóndela mostrando qué le beneficia más; una pregunta no es una orden de actuar.
- No le sugieras cosas que no pidió. No le pidas permiso para reemplazar lo necesario.
- Cuando escriba solo **«JetPost»**: revisa lo nuevo en Jetpost (workspace `darshan-bhakti-vinod`) e infórmale.

## Reglas de seguridad y gasto (no negociables)
- **Presupuesto USD 0.** Prohibido registrar tarjeta, activar consumo facturable o aceptar pruebas que se conviertan en pago.
- **Solo datos ficticios.** Sin clientes ni documentos reales. Nada productivo.
- Secretos solo en GitHub Secrets o en el servidor; **nunca** en la APK, en Jetpost, en el chat ni en el código.
- Nunca escribas contraseñas ni códigos de verificación (OTP/TOTP) por Nóah.
- No declares aprobado un CSW/OE sin la frase literal de Dirección. No declares PASA un hito sin la corroboración visual de Dirección cuando la orden la exige.
- Pendiente por decisión de Dirección: la conexión directa de ChatGPT a MIAPK (MCP). Avatar o TTS de pago: «sin gastos por ahora».

## Programa vigente: OE-MIAPK-002 (Fase 1, laboratorio)
- Basada en el CSW 003 v1.1, aprobado por Dirección el 10 nov.
- Nota de la orden en Jetpost: `e901uktzrw`.
- Hitos H1–H8:

| Hito | Estado |
|---|---|
| H1 · Esquema y RLS (21 tablas) | PASA |
| H2 · Acceso con TOTP (aal2) | PASA. Dictamen Magid: aceptado con observaciones |
| H3 · Motor de eventos (9/9) | PASA. Dictamen Magid: aceptado con observaciones; salvedades a–d ya atendidas |
| H4 · Indicador E04 en vivo | PASA CON OBSERVACIONES, cerrado para continuidad (nota `rhzaqt6pxg`); defectos D1 y D2 corregidos en v0.3.3 |
| H5 · OSI experimental | PASA CON OBSERVACIONES (nota `7kng1zco3a`, APK v0.3.3) |
| H6 · Respaldo y restauración | PASA CON OBSERVACIONES (nota `uzg3a00mwa`; workflow `h6-respaldo.yml`, secreto `MIAPK_DB_PASSWORD`, rama `respaldos`) |
| H7 · Informe para Magid | PASA CON OBSERVACIONES; Magid recalculó el hash y coincidió (nota `oqi78cweqt`) |
| H8 · Cierre (10 bloques de E09) | 3 PASA, 7 con observaciones, 0 FALLA (nota `7v4irdwmpm`, APK v0.3.5) |

**FASE 1 CERRADA DOCUMENTALMENTE CON RESERVAS** por Dirección (11 nov, 11:39, frase literal).

## Programa vigente: OE-MIAPK-003 (Fase 2, laboratorio, USD 0)
- CSW 004 v1.1 (nota `wo4wi4i6kj`) aprobado por Dirección: «Apruebo el CSW 004 v1.1» (11 nov, 12:21, vía ChatGPT). OE-MIAPK-003: nota `uhw95lmvx6`.
- Hitos F2-H1 → F2-H8 en secuencia. Ninguno avanza sin el dictamen de Magid. Si F2-H6 queda BLOQUEADO, no se inicia F2-H7.
- Respaldo: opción A, manual y cifrado (age), al cerrar cada hito y antes de cada cambio de esquema; se guardan las 4 últimas copias.
- **F2-H1 hecho** (11 nov, 12:45): todo PASA en el Android de Dirección; APK v0.4.0 con sesión cifrada en el Keystore; nota `l4xhdm8j0b`, `pruebas/fase2/F2-H1_evidencia.md`. Dictamen: PASA CON OBSERVACIONES.
- **F2-H2 hecho** (11 nov, 13:06): revocación efectiva con `sesion_vigente()` en `es_direccion_mfa()` (migración 0007); 3 modos PASA a los 0 s en Android; APK v0.4.1; nota `3zlgnxczcy`. Vigencia del JWT ajustada a 600 s en el panel (13:24); el navegador integrado ya tiene la sesión correcta de Supabase (vía GitHub). Dictamen de Magid recibido; F2-H3 autorizado.
- **F2-H3 cambiado por Dirección** (13 nov, 11:55): no quiere KeePassXC. El respaldo pasa a ser **recuperación administrativa desde el panel de Supabase** (Authentication → Users → Remove MFA factors → la APK vuelve a pedir el registro del factor). Evidencia en `pruebas/fase2/F2-H3_evidencia.md` (PASA CON OBSERVACIONES propuesto). **Esperando el dictamen de Magid** antes de F2-H4. Nunca pedir ni ver claves ni códigos.
- Siguientes: F2-H4 segunda cuenta de laboratorio (la crea Nóah con otro correo suyo), F2-H5 respaldos cifrados con age, F2-H6 auditoría (BLOQUEADO si no es viable), F2-H7 chat guionado de MÍA Web, F2-H8 regresión + prueba real de inactividad de 15 min + informe final.
- Las migraciones se aplican ahora con `aplicar-migracion.yml` (escribir en `supabase/aplicar.txt`: línea 1 = migración, línea 2 = script de verificación).

Requisito de Dirección para el acceso: el uso diario pide solo contraseña + 1 código TOTP; el segundo autenticador es solo respaldo; sin correo ni atajos.

Pendientes obligatorios para H8 (dictamen de H2):
- expiración real a los 15 min;
- cerrar sesión en todos los dispositivos;
- segundo usuario aal2 sin rol;
- que REST no eluda la RLS;
- almacenamiento seguro de tokens;
- factor TOTP de respaldo;
- límite a la cola de errores vía anon.

### H4: historial (cerrado)
Magid autorizó el H4: un evento ficticio nuevo debe actualizar un indicador E04 en la APK en menos de 60 s, con trazabilidad, valor anterior y posterior, 5 estados, rechazo de duplicado y error, en el dispositivo real y con corroboración de Dirección.
- Hecho: migración `0003` aplicada; vista `miapk.v_indicadores` («PFV aceptados»); APK **v0.3.2** instalada con la tarjeta «En vivo · laboratorio».
- Ensayo SQL revertido: se vieron los 5 estados.
- Envíos reales (`h4_registro_1..3` en la rama `resultados`):
  1. `pfv lab-H4-1` aceptado (19:29:39 UTC). Dirección confirmó que la APK se actualizó sola: 0 → 1 · Confirmado.
  2. `duplicado lab-H4-1` → duplicado.
  3. `error lab-H4-2` → rechazado. Dirección confirmó el error a las 14:31.
- **Falta:**
  1. El número de segundos de «apareció aquí a los … s», que Nóah aún no reportó.
  2. Escribir `pruebas/fase1/H4_evidencia.md`.
  3. Crear la nota Jetpost «OE-MIAPK-002 · Evidencia H4 · …» y pedir el dictamen de Magid mencionando a "Darshan’s ChatGPT".

### Otra instrucción de Magid (no cambia la OE)
Directriz de Dirección para MÍA Web (nota Jetpost `lm33wen9dk`):
1. Primero chat escrito.
2. Después, acompañar la creación del sitio.
3. Avatar solo si se demuestra que es rentable.

Incorporarla al roadmap y a los CSW futuros, sin tocar el CSW 003 ni la OE-MIAPK-002.

## Infraestructura
- **Repo:** `cristhiansmail-byte/miapk` (privado), rama `main`. El APK se compila en GitHub Actions (`build-apk.yml`) con una clave de firma fija (`app/miapk-v01.keystore`) para que actualice encima, y se publica en Releases y en la rama `apk`.
- **Cada versión nueva de la APK se le entrega a Nóah directamente.** Sube `versionCode` y `versionName` en `app/build.gradle.kts` y agrega la novedad en `D.novedades`, en `app/src/main/assets/index.html`.
- **App:** wrapper WebView en Java (`MainActivity.java`) más `assets/index.html`. Seis pestañas: Pulso, Programas, Órdenes, Medición, MÍA y OSI. «Acceso seguro» habla directo con Supabase Auth REST.
- **Supabase Free** `miapk-laboratorio`:
  - ref `nfposoxyrywtwjzyrslk`, URL `https://nfposoxyrywtwjzyrslk.supabase.co`;
  - clave publicable `sb_publishable_YLpZ72vbW7xQIfijnOPNIw_50GXkHzM` (es pública);
  - esquema `miapk`, signups cerrados, RLS forzado, `miapk.es_direccion_mfa()`.
  - Migraciones en `supabase/migrations/0001–0003`. Se aplicaron pegándolas en el SQL Editor del panel, porque no hay token de la CLI.
  - Free = sin backups automáticos y pausa tras 1 semana sin uso: no generar actividad artificial.
- **Ingesta:** `public.miapk_ingerir_evento(credencial, evento)` (security definer). La credencial de la fuente `laboratorio` está en el secreto de GitHub `MIAPK_CRED_LAB`, que creó Nóah; en la BD solo se guarda su hash.
- **Workflows:**
  - `prueba-eventos.yml` (H3, se dispara con `pruebas/fase1/h3_ejecutar.txt`);
  - `h4-emisor.yml` (se dispara con `pruebas/fase1/h4_ejecutar.txt`, contenido `pfv|duplicado|error <external_id>`);
  - `prueba-liveavatar.yml` (OE-MIA-001, cerrada).
  - Los registros redactados van a la rama `resultados`.
- **Evidencias:** `pruebas/fase1/H1..H3_evidencia.md`.

## Notas Jetpost clave (workspace `darshan-bhakti-vinod`)
- `e901uktzrw`: OE-MIAPK-002.
- `41oupzbxgm`: Evidencia H2.
- `g1jd4gjyo2`: Evidencia H3, con el dictamen y la autorización de H4.
- `lm33wen9dk`: directriz de MÍA Web.
