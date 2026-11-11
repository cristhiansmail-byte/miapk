// Regresión de la APK (defectos abiertos del dictamen H4). Falla la compilación si reaparecen.
import { readFileSync } from "node:fs";
const html = readFileSync(new URL("../app/src/main/assets/index.html", import.meta.url), "utf8");
const lit = html.slice(html.indexOf("const D = ") + 10, html.indexOf("\n};", html.indexOf("const D = ")) + 2);
const D = Function('"use strict"; return (' + lit + ");")();
const fallas = [];
const ok = (cond, msg) => { console.log((cond ? "OK   " : "FALLA") + " · " + msg); if (!cond) fallas.push(msg); };
const o2 = D.ordenes.find(o => o.id === "OE-MIAPK-002");
ok(o2 && o2.e === "En ejecución", "D1: OE-MIAPK-002 aparece y está En ejecución");
ok(D.ordenes.find(o => o.id === "OE-MIAPK-001")?.e === "Cerrada", "D1: OE-MIAPK-001 figura como Cerrada");
ok(D.csw.some(c => c[0] === "CSW 003 v1.1"), "D1: CSW 003 v1.1 figura en la lista de CSW");
ok(D.osi.some(d => d[0] === "OE-MIAPK-002"), "D1: OE-MIAPK-002 figura en la lista OSI");
ok(/o\.e=="Cerrada"\?"":/.test(html), "D1: Pulso oculta las órdenes cerradas en «Órdenes activas»");
ok(!html.includes("Ningún indicador tiene datos todavía"), "D2: Medición ya no dice «Ningún indicador tiene datos todavía»");
ok(html.includes('k==0?pill("En vivo ↑","ok")') && D.indicadores[0][0] === "PFV aceptados", "D2: la fila de referencia de PFV aceptados ya no dice Pendiente");
ok(!/localStorage\.setItem\("miapk_sesion"/.test(html), "F2-H1: la sesión ya no se escribe en localStorage");
ok(html.includes("MIAPK.guardarSesion(") && html.includes("MIAPK.borrarSesion()"), "F2-H1: la sesión usa el almacén nativo cifrado");
const man = readFileSync(new URL("../app/src/main/AndroidManifest.xml", import.meta.url), "utf8");
ok(man.includes('android:allowBackup="false"') && man.includes("dataExtractionRules"), "F2-H1: copias de Android desactivadas");
ok(/async function accSalir\(\)\{[^\n]*revocarCon\(viejo,"local"\)/.test(html), "F2-H2: «Cerrar sesión» revoca la sesión en el servidor");
ok(/INACTIVIDAD_MS\)\{[^\n]*revocarCon\(viejo,"local"\)/.test(html), "F2-H2: el cierre por inactividad revoca en el servidor");
if (fallas.length) { console.error(fallas.length + " regresión(es)"); process.exit(1); }
console.log("Regresión de la APK: PASA");
