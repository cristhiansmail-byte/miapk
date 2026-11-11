"""H6 · cotejo de huellas entre el origen (Supabase) y la copia restaurada (entorno aislado)."""
import json, sys
o = json.load(open(sys.argv[1])); r = json.load(open(sys.argv[2]))
res = {"tablas": [], "osi": [], "fallas": 0}
ro = {t["tabla"]: t for t in r["tablas"] or []}
for t in o["tablas"] or []:
    c = ro.get(t["tabla"], {})
    ok = c.get("filas") == t["filas"] and c.get("md5") == t["md5"]
    res["tablas"].append({"tabla": t["tabla"], "filas_origen": t["filas"], "filas_copia": c.get("filas"), "coincide": ok})
    res["fallas"] += 0 if ok else 1
for v in o["osi"] or []:
    c = next((x for x in r["osi"] or [] if x["codigo"] == v["codigo"] and x["version"] == v["version"]), {})
    ok = c.get("sha256_contenido") == v["sha256_contenido"] and (v["sha256_aprobado"] is None or c.get("sha256_contenido") == v["sha256_aprobado"])
    res["osi"].append({"codigo": v["codigo"], "version": v["version"], "estado": v["estado"], "sha256_aprobado": v["sha256_aprobado"],
                       "sha256_copia": c.get("sha256_contenido"), "coincide": ok})
    res["fallas"] += 0 if ok else 1
res["bitacora_cadena_ok_copia"] = r.get("bitacora_cadena_ok")
if not r.get("bitacora_cadena_ok"): res["fallas"] += 1
res["resultado"] = "PASA" if res["fallas"] == 0 else "FALLA"
print(json.dumps(res, ensure_ascii=False, indent=1))
json.dump(res, open("h6_cotejo.json", "w"), ensure_ascii=False, indent=1)
sys.exit(0 if res["fallas"] == 0 else 1)
