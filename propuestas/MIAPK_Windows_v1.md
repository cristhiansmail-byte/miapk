# Propuesta · MIAPK para Windows (v1, para revisión de Magid)

**Pedido de Dirección (13 nov 2026, 12:15):** «Prepara para revisión de Magid una propuesta de migración de MIAPK a Windows, para dejar de usar la APK, con costo cero, instalación sencilla y conservación de las funciones actuales. No la ejecutes todavía».
**Estado:** propuesta. No se ha ejecutado nada.

## Recomendación
Una app de escritorio **«MIAPK.exe»** hecha con C# y **WebView2**, el motor de Edge que ya viene en Windows 10 y 11. Es el mismo diseño que la APK: una ventana que muestra el mismo `index.html` y un «puente» nativo pequeño. El cambio es solo de envoltura; la lógica, Supabase, la RLS y los hitos ya probados no se tocan.

- **Costo:** USD 0. Se compila en GitHub Actions dentro de la cuota gratuita (2.000 min/mes en repos privados; una compilación toma ~5 min). La cuenta no tiene tarjeta, así que no puede haber cobro por exceso. WebView2 y .NET no tienen costo.
- **Instalación:** un solo archivo `MIAPK.exe` (autocontenido, sin instalar .NET). Se descarga, se guarda en una carpeta y se crea un acceso directo. Para actualizar, se reemplaza el archivo, igual que hoy con la APK.
- **Funciones:** se conservan las 6 pestañas, Acceso seguro con TOTP (aal2), revocación, cierre por inactividad, cerrar todas las sesiones, indicador en vivo, OSI, caché y diagnóstico.

## Equivalencias técnicas
| Hoy en Android | En Windows |
|---|---|
| WebView + `MainActivity.java` | WebView2 + `MainForm.cs` |
| `Puente` (addJavascriptInterface) | `Puente` (AddHostObjectToScript, proxy síncrono) |
| Sesión cifrada con AES-GCM en el Android Keystore (F2-H1) | Sesión cifrada con **DPAPI** (`ProtectedData`, alcance del usuario de Windows) |
| `allowBackup=false` | Archivo en `%LOCALAPPDATA%\MIAPK`, fuera de OneDrive |
| `assets/index.html` | El mismo archivo, servido con un host virtual (`https://miapk.app.local/`) |
| APK firmada con clave fija | EXE sin firma de código (la firma cuesta dinero) |

Cambio en `index.html`: una línea para que `window.Puente` use el puente de WebView2 si existe. Todo lo demás queda igual, y la APK puede seguir funcionando durante la transición.

## Hitos propuestos
- **W1 · Envoltura y puente.** `MIAPK.exe` abre el mismo `index.html`; `Puente` (version, guardarSesion, leerSesion, borrarSesion, diagnostico) con DPAPI; workflow `build-windows.yml`; prueba de regresión `regresion_apk.mjs` extendida a Windows.
- **W2 · Paridad en la laptop de Dirección.** Repetir en Windows las pruebas de F2-H1 (sesión cifrada, nada en localStorage) y de F2-H2 (3 modos de revocación), entrada con contraseña + 1 código, indicador en vivo y OSI. Con corroboración visual de Dirección.
- **W3 · Retiro de la APK.** Con W2 aprobado por Magid y Dirección, la APK queda congelada en su última versión y deja de recibir cambios.

## Riesgos y observaciones
- **R1. El teléfono sigue siendo necesario para el código TOTP.** Google Authenticator queda en el Android. Pasar el autenticador a la misma laptop juntaría los dos factores en un solo equipo y debilitaría la doble verificación. **Recomendación:** mantener el código en el teléfono.
- **R2. Aviso de SmartScreen.** Como el EXE no está firmado, Windows mostrará «Windows protegió su PC» la primera vez. Se abre con «Más información → Ejecutar de todas formas». La firma de código tiene costo y queda fuera.
- **R3. Cuota de GitHub Actions.** Si la compilación usa runners Windows, consume minutos al doble. Se puede compilar desde Linux (`EnableWindowsTargeting`), que no tiene ese recargo. Si la cuota se agotara, GitHub detiene los workflows; no cobra sin tarjeta.
- **R4. Tamaño del EXE.** La versión autocontenida pesa ~60–70 MB. Una versión liviana pediría instalar el runtime de .NET, que es un paso más.
- **R5. Secuencia.** No se recomienda mezclar esto con F2-H4…F2-H8 a mitad de camino. Magid decide si va como solicitud de cambio a la OE-MIAPK-003 o como OE aparte, y en qué punto.

## Alternativas descartadas
- **App web instalable (PWA) en Edge:** necesita alojamiento público. GitHub Pages no es gratis en repos privados, y otros servicios gratuitos piden cuenta nueva. Además, la sesión quedaría en el almacenamiento del navegador, por debajo del nivel probado en F2-H1.
- **Electron:** mismo resultado, pero ~150 MB y más superficie de ataque.
- **Tauri:** liviano, pero se aleja más del diseño actual y la cadena de compilación es más compleja.

## Decisiones que se piden a Magid
1. Aceptar, observar o rechazar la arquitectura WebView2 + DPAPI.
2. Encuadre: solicitud de cambio a la OE-MIAPK-003 u OE nueva.
3. Momento de ejecución respecto de F2-H4…F2-H8.
4. Si se acepta R1 (el TOTP sigue en el teléfono).
