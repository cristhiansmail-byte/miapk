# OE-MIAPK-002 · H1 · Evidencia (10 nov 2026)

Proyecto Supabase: `miapk-laboratorio` (ref `nfposoxyrywtwjzyrslk`), organización "Mi Sitio Web", plan **Free $0/mes**.
Creado desde la cuenta de Dirección (inicio de sesión con GitHub `cristhiansmail-byte`). No se pidió medio de pago.

## Esquema aplicado
`supabase/migrations/0001_h1_esquema_rls.sql` ejecutado en el SQL Editor del proyecto.
Resultado: `H1_OK · tablas 21 · tablas_con_rls 21 · politicas 21`.

## Capa 1 · API pública (clave publicable, sin sesión)
GET/POST a `/rest/v1/{programas,eventos,actores}` con `Accept-Profile: miapk` → **HTTP 406 PGRST106** "Invalid schema: miapk" (el esquema no está expuesto a la API).

## Capa 2 · Base de datos (simulación de roles dentro de una transacción revertida)
| Prueba | Filas visibles |
|---|---|
| anon lee programas | RECHAZADO |
| Dirección SIN doble factor (aal1) | 0 |
| Otro usuario CON doble factor | 0 |
| Dirección CON doble factor (aal2) | 8 |
| Dirección escribe directo | RECHAZADO (solo funciones de servidor) |
| Alterar bitácora | RECHAZADO (solo agregar) |

La prueba se ejecutó con `begin … rollback`: no quedó ningún dato de prueba.
Validación previa en PostgreSQL 16 local con resultados idénticos.
