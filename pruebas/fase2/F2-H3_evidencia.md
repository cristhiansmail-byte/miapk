# OE-MIAPK-003 · F2-H3 · Respaldo del segundo factor

**Estado propuesto:** PASA CON OBSERVACIONES, sujeto al dictamen de Magid (cambia el mecanismo pedido).
**Fecha:** 13 nov 2026 · Laboratorio · USD 0 · solo datos ficticios.

## Decisión de Dirección
Dirección no tiene un segundo teléfono ni tableta. Se intentó un segundo autenticador TOTP en la laptop (KeePassXC, APK v0.4.2), pero Dirección lo descartó por la carga operativa: «no quiero tener que usar keepass» y luego «sigamos por esta vía» (13 nov, 11:55).

**Mecanismo adoptado:** recuperación administrativa desde el panel de Supabase, en lugar de un segundo autenticador.

## Procedimiento de recuperación (solo si se pierde el teléfono)
1. Dirección entra a supabase.com con su cuenta de GitHub. El panel tiene su propio control de acceso, separado de MIAPK.
2. Va a Authentication → Users → su usuario → Danger zone → **Remove MFA factors**.
3. En el teléfono nuevo abre MIAPK y entra con su contraseña. Como ya no hay factores verificados, la APK abre «Paso 2 · Activa tu doble verificación» (código existente, `index.html`, rama `fs.length == 0`).
4. Registra el autenticador nuevo y verifica con un código. La sesión vuelve a aal2.

## Verificaciones hechas
| Comprobación | Resultado |
|---|---|
| La opción «Remove MFA factors» existe en el panel del proyecto `miapk-laboratorio` (no se ejecutó) | PASA · captura `f2h3_capturas/1_panel_remove_mfa.jpg` |
| Sin factores verificados, la APK pide registrar uno nuevo antes de dar aal2 | PASA por revisión de código (v0.4.2) |
| El uso diario sigue siendo contraseña + 1 código TOTP, sin correo ni atajos | PASA |
| No hay ninguna vía de recuperación dentro de la APK ni por correo | PASA |

## Observaciones
- O1. No hay un segundo autenticador. Mientras dure la recuperación, alguien que tenga la contraseña podría registrar su propio factor. Se mitiga porque la ventana es corta y solo la abre Dirección desde el panel.
- O2. La recuperación depende del acceso de Dirección a su cuenta de GitHub, que también es el acceso al panel.
- O3. La tarjeta «Autenticador de respaldo» y el enlace «Perdí mi autenticador principal» de la v0.4.2 quedan sin uso. Se pueden retirar en una versión posterior.
- O4. No se ejecutó un simulacro real de «Remove MFA factors». Se puede hacer en F2-H8 si Magid lo pide.
- No se mostró, guardó ni compartió ninguna clave ni código.
