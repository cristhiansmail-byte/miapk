"""OE-MIAPK-002 · H3 · Pruebas reproducibles del motor de eventos (laboratorio, USD 0).
La credencial llega solo por la variable MIAPK_CRED_LAB (secreto de GitHub); nunca se imprime."""
import hashlib, json, os, sys, time, uuid, urllib.request, urllib.error, datetime as dt

URL = "https://nfposoxyrywtwjzyrslk.supabase.co"
KEY = "sb_publishable_YLpZ72vbW7xQIfijnOPNIw_50GXkHzM"   # clave pública (ya va en la APK)
CRED = os.environ.get("MIAPK_CRED_LAB", "")
UA = "MIAPK-pruebas-H3/1.0"
registro = []

def log(**k):
    k["t"] = dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds")
    registro.append(k); print(json.dumps(k, ensure_ascii=False))

def http(metodo, ruta, cuerpo=None, extra=None):
    h = {"apikey": KEY, "Content-Type": "application/json", "User-Agent": UA}
    h.update(extra or {})
    req = urllib.request.Request(URL + ruta, method=metodo, headers=h,
                                 data=None if cuerpo is None else json.dumps(cuerpo).encode())
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        txt = e.read().decode(errors="replace")
        try: return e.code, json.loads(txt)
        except Exception: return e.code, txt[:300]

def ingerir(evento, cred=None):
    return http("POST", "/rest/v1/rpc/miapk_ingerir_evento",
                {"p_credencial": CRED if cred is None else cred, "p_evento": evento})

def evento_base(ext):
    return {"event_id": str(uuid.uuid4()), "type": "laboratorio.prueba.registrada",
            "occurred_at": dt.datetime.now(dt.timezone.utc).isoformat(), "external_id": ext,
            "subject_entity": "prueba", "subject_id": ext, "data": {"ficticio": True, "nota": "evento de prueba H3"}}

if len(CRED) < 32:
    log(prueba="0 credencial", resultado="FALLA", detalle="Falta el secreto MIAPK_CRED_LAB o tiene menos de 32 caracteres")
else:
    log(prueba="0 credencial", resultado="OK", hash_sha256=hashlib.sha256(CRED.encode()).hexdigest(),
        detalle="Solo el hash; el valor nunca se imprime")

    run = os.environ.get("GITHUB_RUN_NUMBER", str(int(time.time())))
    ext = f"lab-H3-{run}"
    e1 = evento_base(ext)
    casos = [
        ("1 evento válido", lambda: ingerir(e1), "aceptado"),
        ("2 doble envío idéntico", lambda: ingerir(e1), "duplicado"),
        ("3 mismo external_id con otro event_id", lambda: ingerir({**e1, "event_id": str(uuid.uuid4())}), "duplicado"),
        ("4 type inválido", lambda: ingerir({**evento_base(ext + "-x"), "type": "TipoMalo"}), "rechazado"),
        ("5 dato no marcado ficticio", lambda: ingerir({**evento_base(ext + "-y"), "data": {"cliente": "real"}}), "rechazado"),
        ("6 credencial falsa", lambda: ingerir(evento_base(ext + "-z"), cred="credencial-falsa-" + "0" * 32), "rechazado"),
        ("7 suplantar otra fuente", lambda: ingerir({**evento_base(ext + "-w"), "fuente_id": "pasarela"}), "rechazado"),
    ]
    for nombre, f, esperado in casos:
        st, r = f()
        estado = r.get("estado") if isinstance(r, dict) else None
        log(prueba=nombre, http=st, respuesta=r, esperado=esperado,
            resultado="OK" if estado == esperado else "FALLA")

    # 8. Escritura directa a la tabla (sin pasar por el motor) debe ser rechazada.
    st, r = http("POST", "/rest/v1/eventos", evento_base(ext + "-d"), {"Content-Profile": "miapk"})
    log(prueba="8 escritura directa a miapk.eventos", http=st, respuesta=r, esperado="401/403",
        resultado="OK" if st in (401, 403) else "FALLA")
    # 9. Lectura anónima de eventos debe ser rechazada.
    st, r = http("GET", "/rest/v1/eventos?select=event_id", None, {"Accept-Profile": "miapk"})
    log(prueba="9 lectura anónima de miapk.eventos", http=st, respuesta=r, esperado="401/403",
        resultado="OK" if st in (401, 403) else "FALLA")

ok = all(x.get("resultado") == "OK" for x in registro)
log(prueba="RESUMEN", resultado="PASA" if ok else "FALLA",
    total=len(registro) - 1, fallas=sum(1 for x in registro if x.get("resultado") == "FALLA"))
open("h3_registro.jsonl", "w").write("\n".join(json.dumps(x, ensure_ascii=False) for x in registro) + "\n")
