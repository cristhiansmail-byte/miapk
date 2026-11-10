#!/usr/bin/env python3
"""
OE-MIA-001 · Prueba Sandbox LITE · Voz Montserrat → LiveAvatar (avatar de prueba Wayne)
Mi Sitio Web · preparada por Magda (Claude) · 10 nov 2026

Costo esperado: USD 0 (Sandbox: sin créditos, sesión ~1 minuto).
Requisitos:
  - Python 3.9+  y  pip install websockets
  - Variable de entorno LIVEAVATAR_API_KEY (clave gratuita de app.liveavatar.com).
    NUNCA escribir la clave en este archivo, en JetPost ni en un chat.
  - Salida de red a api.liveavatar.com y *.livekit.cloud
  - El archivo mia_bienvenida_pcm16_24k.raw en la misma carpeta

Uso:
  export LIVEAVATAR_API_KEY="..."      (Windows PowerShell:  $env:LIVEAVATAR_API_KEY="...")
  python3 prueba_sandbox_lite.py

El script imprime la URL y el token de espectador para ver el avatar en el navegador,
espera 20 s para que alcances a abrirlo, envía el audio de Montserrat y registra
cada evento con su tiempo en milisegundos en registro_prueba.jsonl.
"""
import asyncio, base64, json, os, sys, time, uuid, urllib.request, urllib.error

API = "https://api.liveavatar.com/v1"
SANDBOX_AVATAR_ID = "dd73ea75-1218-4ef3-92ce-606d5f7fbc0a"  # Wayne, único avatar del Sandbox
AUDIO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mia_bienvenida_pcm16_24k.raw")
CHUNK = 48000          # 1 s de PCM16 mono 24 kHz = 48 000 bytes (recomendado ~1 s, máx 1 MB)
EN_CI = bool(os.environ.get("GITHUB_ACTIONS"))
ESPERA_ESPECTADOR = 3 if EN_CI else 20 # segundos para abrir el visor antes de enviar audio
LOG = "registro_prueba.jsonl"
T0 = time.monotonic()

def log(evento, **datos):
    fila = {"t_ms": round((time.monotonic() - T0) * 1000), "evento": evento, **datos}
    print(json.dumps(fila, ensure_ascii=False))
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(json.dumps(fila, ensure_ascii=False) + "\n")

def post(path, body, headers):
    req = urllib.request.Request(API + path, data=json.dumps(body).encode(), method="POST",
                                 headers={"content-type": "application/json", "accept": "application/json", **headers})
    t = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = json.loads(r.read())
            log("http", ruta=path, estado=r.status, ms=round((time.monotonic()-t)*1000))
            return body
    except urllib.error.HTTPError as e:
        log("http", ruta=path, estado=e.code, ms=round((time.monotonic()-t)*1000), respuesta=e.read().decode(errors="replace")[:800])
        raise

async def main():
    key = os.environ.get("LIVEAVATAR_API_KEY")
    if not key:
        sys.exit("Falta LIVEAVATAR_API_KEY en el entorno.")
    try:
        import websockets
    except ImportError:
        sys.exit("Falta el paquete: pip install websockets")
    pcm = open(AUDIO, "rb").read()
    log("audio_cargado", bytes=len(pcm), segundos=round(len(pcm) / 48000, 2))

    # 1. Token de sesión LITE en Sandbox (usa X-API-KEY)
    tok = post("/sessions/token", {"mode": "LITE", "avatar_id": SANDBOX_AVATAR_ID, "is_sandbox": True},
               {"X-API-KEY": key})
    data = tok.get("data", tok)
    session_token, session_id = data["session_token"], data["session_id"]
    log("token_creado", session_id=session_id)

    # 2. Iniciar sesión (usa Bearer con el session_token, NO la API key)
    start = post("/sessions/start", {}, {"authorization": f"Bearer {session_token}"})
    s = start.get("data", start)
    ws_url = s["ws_url"]
    log("sesion_iniciada", max_duracion_s=s.get("max_session_duration"))
    log("sala_livekit", url_presente=bool(s.get("livekit_url")), token_visor_presente=bool(s.get("livekit_client_token")))
    if not EN_CI:
        print("\n=== VISOR: abre https://meet.livekit.io  → pestaña 'Custom' y pega: ===")
        print("URL   :", s.get("livekit_url"))
        print("TOKEN :", s.get("livekit_client_token"))
        print(f"(tienes {ESPERA_ESPECTADOR} s; el token de visor es temporal y no se debe compartir)\n")

    async with websockets.connect(ws_url, max_size=None) as ws:
        # 3. Esperar estado 'connected' antes de cualquier comando
        while True:
            msg = json.loads(await ws.recv())
            log("ws_recibido", **msg)
            if msg.get("type") == "session.state_updated" and msg.get("state") == "connected":
                break
        await asyncio.sleep(ESPERA_ESPECTADOR)

        # 4. Enviar el audio en trozos de ~1 s y cerrar el turno
        evento = str(uuid.uuid4())
        log("envio_inicio", event_id=evento)
        for i in range(0, len(pcm), CHUNK):
            await ws.send(json.dumps({"type": "agent.speak", "event_id": evento,
                                      "audio": base64.b64encode(pcm[i:i + CHUNK]).decode()}))
        await ws.send(json.dumps({"type": "agent.speak_end", "event_id": evento}))
        log("envio_fin", trozos=-(-len(pcm) // CHUNK))

        # 5. Registrar eventos hasta que termine de hablar o se cierre el Sandbox (~1 min)
        try:
            while True:
                msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=45))
                log("ws_recibido", **msg)
                if msg.get("type") in ("agent.speak_ended",):
                    break
        except (asyncio.TimeoutError, websockets.ConnectionClosed) as e:
            log("fin_escucha", motivo=type(e).__name__)
    log("prueba_terminada")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except Exception as e:
        log("error", tipo=type(e).__name__, detalle=str(e)[:500])
        raise
