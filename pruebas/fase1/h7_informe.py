"""H7 · arma el informe MIAPK en texto canónico (UTF-8, saltos LF) y calcula su SHA-256."""
import hashlib, json, sys
d = json.load(open(sys.argv[1])); respaldo = open(sys.argv[2]).read().split()[0] if len(sys.argv) > 2 else "no disponible"
PEND = ["Conversaciones calificadas","Tasa de comprensión confirmada","Vista previa a tiempo","Correcciones atendidas",
        "Conversión informada","Tiempo a propuesta","Tasa de aceptación de entregas","Defectos de publicación",
        "Cumplimiento de órdenes","Ingresos verificados","Costo de IA por PFV","Margen por entrega",
        "Satisfacción del cliente","Retención","Salud documental OSI"]
L = []
L.append("INFORME MIAPK PARA MAGID · OE-MIAPK-002 · H7")
L.append("Entorno: LABORATORIO · DATOS FICTICIOS · sin clientes ni operaciones reales · USD 0")
L.append(f"Corte: {d['corte_col']} (Bogotá) = {d['corte_utc']}")
L.append("Emisor: Magda (Claude), consulta de solo lectura al servidor miapk-laboratorio (Supabase Free)")
L.append("Entrega: importación asistida por JetPost (Nóah copia el relevo); no hay integración automática MIAPK-ChatGPT")
L.append("")
L.append("1. FUENTES DE DATOS (origen y frescura)")
for f in d["fuentes"]:
    L.append(f"- {f['fuente']}: confianza {f['confianza']}, integrada={'sí' if f['integrada'] else 'no'}, estado={f['estado_fuente']}, "
             f"eventos={f['eventos']}, errores atribuidos={f['errores']}, último evento={f['ultimo_evento_col'] or '—'}, semáforo={f['semaforo']}")
L.append("")
L.append("2. INDICADORES E04 (estado del dato)")
i = d["indicador"]
L.append(f"- {i['nombre']}: valor={i['valor']} (anterior {i['valor_anterior'] if i['valor_anterior'] is not None else '—'}), estado={i['estado']}, "
         f"último evento {i['ultimo_event_id']} recibido {i['ultimo_recibido_col']}, último error {i['ultimo_error_col'] or '—'}")
for n in PEND:
    L.append(f"- {n}: estado=Pendiente (sin fuente integrada; no es cero)")
L.append("")
L.append("3. EVENTOS")
L.append(f"- Total aceptados: {d['eventos_total']}")
for e in d["eventos_por_tipo"] or []:
    L.append(f"  - {e['type']}: {e['n']}")
L.append(f"- Total en cola de errores: {d['errores_total']}")
for e in d["errores_por_origen"] or []:
    L.append(f"  - origen «{e['origen']}»: {e['n']}")
L.append("")
L.append("4. OSI EXPERIMENTAL")
for o in d["osi"] or []:
    L.append(f"- {o['codigo']} v{o['version']}: estado={o['estado']}, integridad={o['integridad']}, ficticio={'sí' if o['ficticio'] else 'no'}, sha256 aprobado={o['sha256_aprobado']}")
L.append("")
L.append("5. TRAZABILIDAD")
b = d["bitacora"]
L.append(f"- Bitácora: {b['entradas']} entradas, cadena continua={'sí' if b['cadena_continua'] else 'NO'}, último hash={b['ultimo_hash']}")
L.append(f"- Decisiones de Dirección registradas: {d['decisiones_direccion']}")
L.append(f"- Programas en el servidor: {d['programas']}")
L.append("- Actores activos: " + ", ".join(f"{a['hat']} ({a['tipo']})" for a in d["actores_activos"]))
L.append(f"- Último respaldo verificado (H6): respaldo.sql sha256={respaldo}")
L.append("")
L.append("6. LÍMITES DE ESTE INFORME")
L.append("- Cifras de laboratorio con datos ficticios; no describen actividad comercial.")
L.append("- Generado por consulta directa de Magda; Magid lo recibe por JetPost, no del servidor.")
L.append("- La huella SHA-256 prueba que el texto recibido es idéntico al emitido, no que los datos sean correctos; la conciliación se hace con las consultas de pruebas/fase1/h7_datos.sql.")
L.append("FIN DEL INFORME")
texto = "\n".join(L) + "\n"
open("informe_h7.txt", "w", encoding="utf-8", newline="\n").write(texto)
h = hashlib.sha256(texto.encode("utf-8")).hexdigest()
open("informe_h7.sha256", "w").write(h + "  informe_h7.txt\n")
print(texto); print("SHA-256:", h)
