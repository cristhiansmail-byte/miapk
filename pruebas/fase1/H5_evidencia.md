# OE-MIAPK-002 · H5 · OSI experimental · Evidencia (11 nov 2026)

Alcance: **solo documentos ficticios**, USD 0. Sin custodia legal, sin WORM, sin inmutabilidad garantizada: quien administra el servidor puede desactivar protecciones; lo que se demuestra es que **cualquier alteración se detecta**.

## Construido (migración `supabase/migrations/0004_h5_osi_experimental.sql`)
- Ciclo Borrador → En revisión → Aprobado → Vigente (→ Sustituido al entrar una versión nueva).
- **Magda** (actor agente) redacta y envía a revisión, solo desde el panel del servidor: `osi_redactar` y `osi_enviar_a_revision` no son ejecutables por la API.
- **Dirección** aprueba y pone vigente desde la APK: `osi_aprobar` y `osi_poner_vigente` exigen `es_direccion_mfa()` (aal2) y estado correcto.
- Aprobar registra una **decisión** con el texto literal, una **aprobación** con la huella SHA-256 aprobada, una **transición** y una entrada de **bitácora** encadenada. Las cuatro tablas son de solo agregar.
- Huella SHA-256 calculada en el servidor (trigger). Fuera de borrador, el contenido no se puede modificar ni borrar (trigger `osi_proteger_t`).
- Poner vigente vuelve a comprobar que el contenido coincide con la huella aprobada.
- **Alerta:** la vista `v_osi_integridad` compara la huella actual con la registrada y la aprobada (Íntegro / ALTERADO). La APK la verifica cada 10 s y muestra la alerta en rojo.
- APK **v0.3.3** (versionCode 6), SHA-256 `91213dd8139440d444159f8e5005bd133010132f8c86c32c823d68a56fc39d23`.

## Documento de prueba
OSI-LAB-001 v1.0 «Política ficticia de escritorio limpio (PRUEBA DE LABORATORIO)», marcado como FICTICIO en su texto y en `osi_documentos.ficticio`. Huella aprobada `41d0e4c37de93390…`.

## Rechazos verificados en el servidor
1. Modificar el contenido en revisión: rechazado ("está en estado en_revision y su contenido no se puede modificar").
2. Borrar una versión: rechazado ("las versiones no se borran").
3. Aprobar sin ser Dirección aal2: rechazado ("solo Dirección con doble verificación puede aprobar").
4. Modificar el contenido vigente por la vía normal: rechazado.

## Prueba con Dirección en su Android (MIAPK v0.3.3, sesión aal2)
| Hora COL | Paso | Quién | Resultado |
|---|---|---|---|
| 08:24:14 | ∅ → Borrador → En revisión | Magda (servidor) | huella 41d0e4c3… |
| 08:35:14 | En revisión → **Aprobado** | Dirección en la APK | decisión literal «Apruebo OSI-LAB-001 versión 1.0.» |
| 08:35:17 | Aprobado → **Vigente** | Dirección en la APK | Dirección: «Dice vigente» |
| 08:37:26 | Alteración simulada saltando la protección (trigger desactivado por el administrador) | Magda | huella actual 89e2ab79… ≠ aprobada 41d0e4c3… |
| ≤ 08:48 | Alerta en la APK | Dirección | «tiene una etiqueta roja que dice alerta alterado» |
| 08:49:02 | Restauración del contenido original | Magda | huella vuelve a 41d0e4c3… |
| 08:50 | Verificación en la APK | Dirección | «Íntegro en verde» |

Bitácora encadenada: 7 entradas tras el ciclo. La alteración y su restauración se hicieron fuera de la API (como lo haría un administrador); por eso no tienen transición. Que la alerta las detecte es justamente lo que se prueba. Riesgo residual: un administrador con acceso total podría también reescribir el hash aprobado; mitigarlo exige copia externa de huellas (H6/H7).

## Defectos abiertos del dictamen H4: corregidos en v0.3.3
- D1: OE-MIAPK-002 «En ejecución», OE-MIAPK-001 «Cerrada», CSW 003 v1.1 listado; Pulso oculta las órdenes cerradas.
- D2: Medición sin «Ningún indicador tiene datos todavía»; PFV aceptados marcado «En vivo ↑».
- Regresión comprobable: `pruebas/regresion_apk.mjs` corre en cada compilación (`build-apk.yml`) y la detiene si reaparecen.
