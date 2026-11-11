"""OE-MIAPK-002 · H4 · Emisor de eventos ficticios para la prueba del indicador en vivo.
Uso: lee h4_ejecutar.txt -> «<accion> <external_id>», acción = pfv | duplicado | error.
La credencial llega solo por MIAPK_CRED_LAB (secreto de GitHub) y nunca se imprime."""
import json, os, uuid, urllib.request, urllib.error, datetime as dt
URL = "https://nfposoxyrywtwjzyrslk.supabase.co"
KEY = "sb_publishable_YLpZ72vbW7xQIfijnOPNIw_50GXkHzM"
partes = open("h4_ejecutar.txt").read().split(); accion, ext = partes[:2]; causa = partes[2] if len(partes) > 2 else None
ahora = dt.datetime.now(dt.timezone.utc)
ev = {"event_id": str(uuid.uuid4()), "type": "entrega.pfv.aceptado", "occurred_at": ahora.isoformat(),
      "external_id": ext, "subject_entity": "entrega", "subject_id": "ENT-FICTICIA-" + ext,
      "origen": "prueba H4", "data": {"ficticio": True, "cliente": "Cliente Ficticio S.A.S.", "nota": "PFV aceptado de prueba H4"}}
if accion == "correccion":
    ev["type"] = "entrega.pfv.revertido"; ev["causation_id"] = causa; ev["origen"] = "prueba H8"; ev["data"]["nota"] = "Corrección: se revierte el PFV " + str(causa)
if accion == "error":
    ev.pop("subject_id")          # evento inválido a propósito
req = urllib.request.Request(URL + "/rest/v1/rpc/miapk_ingerir_evento", method="POST",
    headers={"apikey": KEY, "Content-Type": "application/json", "User-Agent": "MIAPK-H4/1.0"},
    data=json.dumps({"p_credencial": os.environ.get("MIAPK_CRED_LAB", ""), "p_evento": ev}).encode())
try:
    with urllib.request.urlopen(req, timeout=30) as r: st, resp = r.status, json.loads(r.read())
except urllib.error.HTTPError as e: st, resp = e.code, e.read().decode(errors="replace")[:300]
reg = {"accion": accion, "external_id": ext, "enviado_utc": ahora.isoformat(timespec="milliseconds"),
       "respondido_utc": dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds"), "http": st, "respuesta": resp}
print(json.dumps(reg, ensure_ascii=False))
open("h4_registro.jsonl", "w").write(json.dumps(reg, ensure_ascii=False) + "\n")
