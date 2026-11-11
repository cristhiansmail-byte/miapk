package com.misitioweb.miapk;

import android.app.Activity;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyInfo;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.GCMParameterSpec;
import org.json.JSONObject;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/** MIAPK — contenedor nativo de la interfaz de dirección (contenido local, sin servidor). */
public class MainActivity extends Activity {
    private WebView web;

    // ---- Almacén de sesión cifrado con una clave del Android Keystore (no exportable) ----
    private static final String ALIAS = "miapk_sesion_v1";
    private static final String PREFS = "miapk_sesion_cifrada";

    private SecretKey clave(boolean crear) throws Exception {
        KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
        ks.load(null);
        if (ks.containsAlias(ALIAS)) return ((KeyStore.SecretKeyEntry) ks.getEntry(ALIAS, null)).getSecretKey();
        if (!crear) return null;
        KeyGenerator kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        kg.init(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build());
        return kg.generateKey();
    }

    private SharedPreferences prefs() { return getSharedPreferences(PREFS, MODE_PRIVATE); }

    /** Puente de la interfaz con la parte nativa. */
    public class Puente {
        @JavascriptInterface
        public boolean guardarSesion(String json) {
            try {
                Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
                c.init(Cipher.ENCRYPT_MODE, clave(true));
                byte[] ct = c.doFinal(json.getBytes(StandardCharsets.UTF_8));
                prefs().edit()
                        .putString("iv", Base64.encodeToString(c.getIV(), Base64.NO_WRAP))
                        .putString("ct", Base64.encodeToString(ct, Base64.NO_WRAP))
                        .commit();
                return true;
            } catch (Exception e) {
                return false;
            }
        }

        @JavascriptInterface
        public String leerSesion() {
            try {
                SharedPreferences p = prefs();
                String iv = p.getString("iv", null), ct = p.getString("ct", null);
                SecretKey k = clave(false);
                if (iv == null || ct == null || k == null) return "";
                Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
                c.init(Cipher.DECRYPT_MODE, k, new GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)));
                return new String(c.doFinal(Base64.decode(ct, Base64.NO_WRAP)), StandardCharsets.UTF_8);
            } catch (Exception e) {
                return "";
            }
        }

        @JavascriptInterface
        public void borrarSesion() {
            prefs().edit().clear().commit();
            try {
                KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
                ks.load(null);
                if (ks.containsAlias(ALIAS)) ks.deleteEntry(ALIAS);
            } catch (Exception ignored) { }
        }

        /** Diagnóstico sin secretos: nunca devuelve tokens ni la clave, solo hechos verificables. */
        @JavascriptInterface
        public String diagnostico() {
            JSONObject r = new JSONObject();
            try {
                SecretKey k = clave(false);
                r.put("clave_en_keystore", k != null);
                if (k != null) {
                    try {
                        SecretKeyFactory f = SecretKeyFactory.getInstance(k.getAlgorithm(), "AndroidKeyStore");
                        KeyInfo info = (KeyInfo) f.getKeySpec(k, KeyInfo.class);
                        r.put("clave_en_hardware_seguro", info.isInsideSecureHardware());
                    } catch (Exception e) { r.put("clave_en_hardware_seguro", "no determinable"); }
                    r.put("clave_exportable", k.getEncoded() != null);
                }
                String ct = prefs().getString("ct", null);
                r.put("sesion_cifrada_guardada", ct != null);
                r.put("bytes_cifrados", ct == null ? 0 : Base64.decode(ct, Base64.NO_WRAP).length);
                boolean claro = false;
                for (Object v : prefs().getAll().values()) {
                    String t = String.valueOf(v);
                    if (t.contains("eyJ") || t.contains("refresh_token") || t.contains("access_token")) claro = true;
                    try {
                        String d = new String(Base64.decode(t, Base64.NO_WRAP), StandardCharsets.ISO_8859_1);
                        if (d.contains("eyJ") || d.contains("refresh_token")) claro = true;
                    } catch (Exception ignored) { }
                }
                r.put("token_legible_en_archivos", claro);
                r.put("respaldo_android_permitido", (getApplicationInfo().flags & ApplicationInfo.FLAG_ALLOW_BACKUP) != 0);
            } catch (Exception e) {
                try { r.put("error", e.getClass().getSimpleName()); } catch (Exception ignored) { }
            }
            return r.toString();
        }

        @JavascriptInterface
        public String version() {
            try {
                return getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
            } catch (Exception e) {
                return "desconocida";
            }
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        web = new WebView(this);
        web.setBackgroundColor(Color.parseColor("#19324A"));
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(true);
        web.addJavascriptInterface(new Puente(), "MIAPK");
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
                Uri u = req.getUrl();
                String esquema = u.getScheme();
                if ("http".equals(esquema) || "https".equals(esquema)) {
                    // Los enlaces externos (p. ej. actualizaciones) se abren en el navegador del teléfono.
                    startActivity(new Intent(Intent.ACTION_VIEW, u));
                    return true;
                }
                return false;
            }
        });
        setContentView(web);
        if (savedInstanceState != null) {
            web.restoreState(savedInstanceState);
        } else {
            web.loadUrl("file:///android_asset/index.html");
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        web.saveState(out);
    }

    @Override
    public void onBackPressed() {
        web.evaluateJavascript("window.miapkBack && window.miapkBack()", r -> {
            if (!"true".equals(r)) MainActivity.super.onBackPressed();
        });
    }
}
