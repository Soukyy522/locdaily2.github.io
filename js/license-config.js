/*
 * Konfigurasi publik lisensi LocDailyMar.
 * Private key dan service/secret key TIDAK BOLEH ditaruh di file ini.
 */
window.LDM_LICENSE_CONFIG = Object.freeze({
    enabled: true,
    serverUrl: https://baecaqtojsdjnzcbpsaf.supabase.co/functions/v1/ldm-license",
    appVersion: "23.1.0",
    publicSigningJwk: {
  "key_ops": [
    "verify"
  ],
  "ext": true,
  "kty": "EC",
  "x": "nYXwUiZ4kl5HP1XVtVAYSomyjsmrRPrA8si_G1ebPck",
  "y": "ObEW0CSnFhGzLeRecHeJGC38J49VVAaT40AYwdlETaQ",
  "crv": "P-256"
}
});
