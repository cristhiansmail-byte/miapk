# OE-MIAPK-002 · H8 · Cierre de Fase 1 · Matriz E09 e informe final (11 nov 2026)

Entorno de laboratorio, solo datos ficticios, **USD 0 gastados**. La Fase 1 **no está cerrada**: el cierre y cualquier paso a producción son decisión expresa de Dirección.

## Matriz de los 10 bloques E09
| # | Bloque | Resultado | Evidencia principal |
|---|---|---|---|
| 1 | Instalación y actualización | **PASA** | v0.1.0 → v0.3.5 instaladas una encima de otra en el Android de Dirección; «Actualizar» mostró la versión instalada (0.3.4, 10:49) |
| 2 | Doble verificación, expiración y cierre remoto | **PASA CON OBSERVACIONES** | Sin código: 0 datos (H2; simulación 2a). Inactividad: Dirección vio «se cerró por inactividad» (11:26). Cierre en todos los dispositivos: **falló en v0.3.4** (8 sesiones siguieron abiertas, 10:38); corregido en v0.3.5 con la función `cerrar_mis_sesiones`; 0 sesiones y bitácora (10:50:45) |
| 3 | Flujo automático de extremo a extremo | **PASA** | H4: evento nuevo visto en la APK en ≈1 s, sin teclear nada |
| 4 | Estados del dato | **PASA CON OBSERVACIONES** | Los 5 estados vistos en Android por Dirección: Sin datos y Confirmado (H4), Error (14:31), Desactualizado (10:34), Pendiente (10:35) |
| 5 | Deduplicación y corrección | **PASA** | Duplicado no cuenta (H3/H4). Corrección compensatoria: Dirección vio «Valor 1 · anterior 2 · correcciones 1» (10:33) |
| 6 | Permisos por actor | **PASA CON OBSERVACIONES** | Servidor: aal2 sin rol → 0 filas y no aprueba; Dirección aal1 → 0; anónimo sin acceso al esquema; escritura directa y funciones internas rechazadas; 3 rechazos OSI registrados en la bitácora |
| 7 | Custodia OSI | **PASA CON OBSERVACIONES** | Ciclo completo aprobado por Dirección; edición y borrado bloqueados; v1.1 sustituyó a v1.0 (10:31); alerta «ALTERADO» y retorno a «Íntegro» (H5) |
| 8 | Consulta de Magid | **PASA CON OBSERVACIONES** | H7: Magid recalculó el SHA-256 del informe, coincidencia exacta. Conexión directa (MCP) pendiente por decisión de Dirección |
| 9 | Respaldo y restauración | **PASA CON OBSERVACIONES** | H6: restauración aislada, 23/23 tablas y huella OSI coinciden |
| 10 | Rendimiento y errores | **PASA CON OBSERVACIONES** | Consulta en 225 ms (< 2 s). Sin conexión: último dato con su hora y aviso (Dirección). Fuente apagada (Pendiente) sin afectar al resto |

**Resumen:** 3 PASA · 7 PASA CON OBSERVACIONES · 0 FALLA · 0 BLOQUEADO. Una falla encontrada (bloque 2) fue corregida y repetida; se conservan ambos registros.

## Observaciones por bloque
- **B2:**
  - La expiración por inactividad cierra la sesión en el teléfono, pero la sesión del servidor sigue registrada hasta su vencimiento o hasta un cierre (11:26: 1 sesión abierta, creada 10:52).
  - Los access tokens emitidos valen hasta 1 h.
  - La sesión se guarda en el almacenamiento local de la WebView, no en el almacenamiento seguro de Android.
  - No hay factor TOTP de respaldo.
  - Los intentos de inicio fallidos quedan solo en el registro de Supabase Auth, no en la bitácora de MIAPK.
- **B4:** el E09 pedía «un cero real → Confirmado». El modelo E04 muestra **Sin datos** cuando la fuente está al día pero sin eventos, y no inventa un cero confirmado. Falta definir con Dirección si un cero debe mostrarse como «Confirmado 0».
- **B6:**
  - La prueba de «otro usuario aal2 sin rol» y de «Dirección aal1» se hizo **simulando las credenciales en el servidor**, no con una segunda cuenta real.
  - Solo existen los actores Dirección y Magda; los demás roles de E05 aún no tienen usuarios.
  - Las lecturas rechazadas por RLS devuelven 0 filas y no se registran.
- **B7:** no es custodia legal, WORM ni inmutable: un superadministrador puede alterar el contenido. Se detecta, y las huellas aprobadas también quedan fuera de Supabase, en la rama `respaldos`.
- **B8:** la entrega es por importación asistida (Nóah hace el relevo). La huella prueba la integridad del texto, no la exactitud de los datos.
- **B9:**
  - Respaldo manual y sin cifrar (aceptable solo con datos ficticios).
  - No incluye `auth` (cuenta y TOTP de Dirección) ni la función pública de ingesta.
  - Se restauró la copia del mismo día, no la del día anterior.
  - La rama `respaldos` puede reescribirla su titular.
- **B10:** la primera consulta al volver del modo avión tardó 5,4 s. Las consultas estables tardan ≈0,2 s.

## Pendientes obligatorios de H2 (dictamen de Magid) · estado
| Pendiente | Estado |
|---|---|
| Expiración a los 15 min | Hecha en el teléfono (Dirección, 11:26). La sesión de servidor persiste hasta vencer (observación B2) |
| Cerrar en todos los dispositivos | Hecho (v0.3.5, 10:50) |
| Segundo usuario aal2 sin rol | Simulado en el servidor: 0 filas y aprobación rechazada |
| REST no elude RLS | 23 tablas con RLS forzado; anónimo sin acceso al esquema; escritura directa y funciones internas rechazadas |
| Almacenamiento seguro de tokens | **Pendiente** (WebView localStorage) |
| Factor TOTP de respaldo | **Pendiente** (decisión de Dirección) |
| Límite a la cola de errores vía anónimo | Hecho: 20 por minuto, el 21 se rechaza sin registrarse |

## Defectos y cambios durante H8
- APK v0.3.4: modo sin conexión con último dato, tiempo de consulta, correcciones, rechazos registrados.
- APK v0.3.5: cierre real de todas las sesiones. SHA-256 `55869ddc227a2250aa26651cc2f5ebaca4fa17df40d5bd94d2d4582511610fcc`.
- Migraciones `0005_h8_cierre.sql` (corrección compensatoria, rechazos registrados, límite anónimo, higiene de permisos) y `0006_h8_cerrar_sesiones.sql`.

## Propuesta de siguiente CSW (para decisión de Dirección; no se ejecuta sin aprobación)
**CSW 004 · MIAPK Fase 2 · Endurecimiento y primera fuente de negocio, en laboratorio y a USD 0.**
1. **Endurecimiento** (cierra las observaciones):
   - tokens en el almacenamiento seguro de Android;
   - cierre de la sesión del servidor al expirar por inactividad;
   - factor TOTP de respaldo;
   - respaldo cifrado y decisión sobre la frecuencia;
   - registro de intentos de inicio en la bitácora;
   - prueba con una segunda cuenta real sin rol.
2. **Primera fuente de negocio, ficticia:**
   - siguiendo la directriz MÍA Web («primero chat escrito»), un prototipo de chat de MÍA Web que emita eventos de conversación;
   - con esos eventos se alimentan los indicadores «Conversaciones calificadas» y «Tasa de comprensión confirmada», aún con datos inventados.
3. **Decisiones de Dirección antes de gastar:**
   - plan de pago del servidor;
   - dominio;
   - conexión directa con Magid (MCP);
   - avatar o voz de pago (según la puerta de rentabilidad).

   Ninguna se activa sin un CSW y autorización expresa.
