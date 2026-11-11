# OE-MIAPK-002 · H6 · Respaldo y restauración aislada · Evidencia (11 nov 2026)

Alcance: solo datos ficticios, USD 0. **No se afirma respaldo permanente ni integridad garantizada.**

## Procedimiento reproducible (`.github/workflows/h6-respaldo.yml`)
Se dispara escribiendo cualquier texto en `pruebas/fase1/h6_ejecutar.txt` y haciendo push a `main`.
1. **Exportar:** `pg_dump` 17 del esquema `miapk` desde Supabase (pooler de sesión, solo lectura). La credencial es el secreto `MIAPK_DB_PASSWORD`, creado por Dirección; Magda no la vio. Se registra el SHA-256 del archivo.
2. **Restaurar en un entorno aislado:** contenedor PostgreSQL 17 efímero dentro del runner de GitHub, sin relación con el origen. Se crean equivalentes mínimos de lo que Supabase provee fuera del esquema: roles anon/authenticated y funciones `auth.jwt()`/`auth.uid()`. Se restaura con `ON_ERROR_STOP`.
3. **Cotejar:** `h6_huellas.sql` se ejecuta en el origen y en la copia: conteo y md5 del contenido ordenado de cada tabla, huellas SHA-256 de las versiones OSI frente a la huella aprobada y continuidad de la cadena de la bitácora. `h6_cotejo.py` compara y da PASA o FALLA.
4. **Guardar:** respaldo, huellas y cotejo van a la rama privada `respaldos` del repositorio (almacenamiento externo a Supabase, gratuito).

## Resultado · ejecución 4 (11 nov, 09:45 COL) · **PASA, 0 fallas**
- Origen: PostgreSQL 17.11 (Supabase). Respaldo `respaldo.sql`, SHA-256 `6b6e130649ba8bb6bafc3cd4873e9f6af70c933dd0ac7c7e1df56c3e78684b58`.
- **23 de 23 tablas coinciden** en filas y contenido:
  - actores 2, bitacora 7, credenciales_fuente 1, decisiones 1, eventos 3, eventos_errores 12, fuentes 4, osi_aprobaciones 1, osi_documentos 1, osi_transiciones 4, osi_versiones 1, programas 8;
  - las otras 11 tablas están vacías en ambos lados.
- **OSI:** OSI-LAB-001 v1.0, vigente; huella de la copia `41d0e4c37de933906a06fee23ddba8c57823ba51d6d1c06a1dadd24c6bd070cc` = huella aprobada por Dirección.
- **Bitácora:** cadena de hashes continua en la copia.
- Carpeta `respaldo_20261111T144555Z_run4` en la rama `respaldos`.
- Ejecuciones 1–3 fallaron por autenticación: la contraseña guardada no correspondía a la confirmada en Supabase. Dirección la regeneró y la actualizó. Se agregó un diagnóstico que muestra solo la longitud recibida, nunca el valor.

## Límites (declarados)
- **Supabase Free no hace copias automáticas.** Este respaldo es manual, por ejecución. No se programó periódico para no generar actividad artificial; queda como decisión de Dirección.
- **No incluye** el esquema `auth` (usuario de Dirección y factor TOTP) ni la función `public.miapk_ingerir_evento`. Tras una pérdida total habría que recrear la cuenta y el factor, y reaplicar las migraciones 0002–0004 de `supabase/migrations/`. El código de servidor está versionado en el repositorio.
- El respaldo se guarda **sin cifrar** en la rama privada `respaldos`. Es aceptable con datos ficticios y debe cifrarse antes de cualquier dato real. Contiene el hash (no el valor) de la credencial del laboratorio.
- **Anclaje externo:** la rama `respaldos` conserva fuera de Supabase las huellas OSI aprobadas, lo que mitiga en parte el riesgo de un superadministrador que reescriba hashes en el servidor (observación de H5). Sigue sin ser WORM ni custodia legal; el titular del repositorio podría reescribir el historial.
- md5 se usa solo para cotejar tablas; las huellas de integridad OSI y del archivo son SHA-256.
- La restauración probada es en un entorno aislado, no una recuperación del proyecto productivo de Supabase.
