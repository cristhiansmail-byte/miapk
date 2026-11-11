# OE-MIAPK-003 · F2-H1 · Sesión en el espacio protegido de Android · Evidencia (11 nov 2026)

## Respaldo previo a los cambios
Ejecución 5 de `h6-respaldo.yml` (12:26 COL): 23/23 tablas PASA. SHA-256 `ea04c4311f17490d7bd51d1045cb0ca3fbe4ba82f4043bc34b64eecb4b9b9c8c`. Carpeta `respaldo_20261111T172651Z_run5` en la rama `respaldos`. **Sin cifrar**: el cifrado llega en F2-H5. Contiene solo datos ficticios; no se presenta como cumplimiento de F2-H5.

## Mecanismo (APK v0.4.0, versionCode 9)
- `MainActivity.java`: clave AES-256 en el **Android Keystore** (alias `miapk_sesion_v1`, GCM, no exportable). La sesión se guarda solo como texto cifrado (IV + texto cifrado, en Base64) en SharedPreferences privadas.
- La WebView pide la sesión al puente nativo (`leerSesion`) y la mantiene **solo en memoria**. Ya no escribe nada en `localStorage`.
- Migración automática: si existía `miapk_sesion` en `localStorage` (v0.3.5 o anterior), se cifra, se pasa al Keystore y se borra de la WebView.
- Cerrar sesión borra el texto cifrado **y elimina la clave** del Keystore.
- `allowBackup=false`, `fullBackupContent=false` y `dataExtractionRules`: nada de la app sale en la copia en la nube ni en la transferencia entre dispositivos.
- Botón «Diagnóstico de seguridad». Revisa localStorage, sessionStorage, cookies e IndexedDB buscando patrones de token. Del lado nativo informa: clave en el Keystore, hardware seguro, clave no exportable, tamaño del texto cifrado, si hay texto legible en los archivos y la bandera de respaldo. **Nunca muestra secretos.**
- Regresión automática en la compilación: la sesión no se escribe en localStorage, se usa el almacén nativo y las copias de Android están desactivadas.

## Prueba en el Android de Dirección
| Hora COL | Estado | Resultado |
|---|---|---|
| 12:43:29 | Con sesión abierta | 8/8 PASA. localStorage sin tokens (1 clave revisada: caché de datos ficticios). Sin cookies ni IndexedDB. Sesión cifrada de 1 144 bytes (AES-256-GCM). Clave no exportable, **en hardware seguro: true**. Ningún token legible en los archivos. Copias desactivadas |
| 12:44:52 | Tras cerrar la app por completo y reabrirla | 8/8 PASA; **la sesión se reanudó sin pedir contraseña** (el diagnóstico la reporta abierta) |
| 12:45:35 | Tras «Cerrar sesión» | 7/7 PASA. Almacén vacío; localStorage con 0 claves (también se borró la caché) |

Capturas en `pruebas/fase2/f2h1_capturas/`, con sus SHA-256 en `SHA256SUMS.txt`.
APK v0.4.0, SHA-256 `a3665ba33788a1fe3f05e684bc172d4f41faf73e47922f63d79fc384356663ca`.

## Amenazas y límites verificables
- Protege el **almacenamiento**, no un dispositivo comprometido: con root o malware activo se puede leer la memoria de la app mientras está abierta.
- La inspección se hace **desde la propia app**. No se hizo una extracción forense externa del sistema de archivos (requiere root o ADB con depuración); el diagnóstico nativo revisa todos los valores del archivo de preferencias de la sesión.
- La caché de datos en vivo (indicador y OSI, ficticios, sin tokens) sigue en localStorage y se borra al cerrar sesión.
- **Cerrar sesión** borra todo lo local, pero **todavía no revoca la sesión en el servidor**. Eso corresponde a F2-H2.
