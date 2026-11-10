# MIAPK

Sistema privado de dirección, gestión y medición de **Mi Sitio Web**.

**v0.1.0** — APK Android con la interfaz de dirección (Pulso · Programas · Órdenes · Medición · MÍA · OSI) y el contenido de los documentos aprobados al 10 nov 2026. Sin servidor todavía: no calcula datos en vivo.

## Cómo se obtiene la APK
Cada cambio en `main` dispara GitHub Actions (`.github/workflows/build-apk.yml`), que compila la APK firmada y la publica en **Releases**.

## Firma
`app/miapk-v01.keystore` es una clave provisional para que las versiones nuevas se instalen encima de las anteriores. Antes de distribuir MIAPK fuera de Dirección debe reemplazarse por una clave guardada como secreto.
