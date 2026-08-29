import { createClient } from "npm:@supabase/supabase-js@2";

type JsonRecord = Record<string, unknown>;

function envKey(listName: string, legacyName: string): string {
  const legacy = Deno.env.get(legacyName);
  if (legacy) return legacy;
  const raw = Deno.env.get(listName);
  if (!raw) return "";
  try {
    const parsed = JSON.parse(raw);
    return String(parsed.default || Object.values(parsed)[0] || "");
  } catch {
    return "";
  }
}

function allowedOrigins(): Set<string> {
  return new Set(
    String(Deno.env.get("LDM_LICENSE_ALLOWED_ORIGINS") || "")
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean),
  );
}

function corsFor(req: Request): Record<string, string> | null {
  const origin = req.headers.get("Origin") || "";
  const allowed = allowedOrigins();
  const allowNull = Deno.env.get("LDM_LICENSE_ALLOW_NULL_ORIGIN") === "true";
  if (origin && !allowed.has("*") && !allowed.has(origin) && !(origin === "null" && allowNull)) {
    return null;
  }
  return {
    "Access-Control-Allow-Origin": origin || [...allowed][0] || "https://invalid.local",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}

function respond(data: unknown, status: number, cors: Record<string, string>) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((value) => value.toString(16).padStart(2, "0")).join("");
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  bytes.forEach((value) => binary += String.fromCharCode(value));
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return bytesToHex(new Uint8Array(digest));
}

function randomToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return bytesToBase64Url(bytes);
}

async function signCertificate(payload: JsonRecord): Promise<{ payload: string; signature: string }> {
  const privateJwkRaw = Deno.env.get("LDM_LICENSE_PRIVATE_JWK") || "";
  if (!privateJwkRaw) throw new Error("LICENSE_SIGNING_KEY_NOT_CONFIGURED");
  const privateJwk = JSON.parse(privateJwkRaw);
  const key = await crypto.subtle.importKey(
    "jwk",
    privateJwk,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const payloadText = JSON.stringify(payload);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(payloadText),
  );
  return { payload: payloadText, signature: bytesToBase64Url(new Uint8Array(signature)) };
}

function safeMessage(error: unknown): string {
  const message = String((error as { message?: string })?.message || error || "UNKNOWN_ERROR");
  const known = [
    "LICENSE_KEY_INVALID", "LICENSE_NOT_STARTED", "LICENSE_EXPIRED", "LICENSE_NOT_ACTIVE",
    "PLAN_INACTIVE", "DEVICE_LIMIT_REACHED", "STORE_LIMIT_REACHED", "STORE_REFERENCE_INVALID",
    "ACTIVATION_NOT_FOUND", "LICENSE_SIGNING_KEY_NOT_CONFIGURED", "LICENSE_EXPIRY_INVALID",
    "TRIAL_ALREADY_USED", "TRIAL_IDENTITY_INVALID", "CUSTOMER_NAME_REQUIRED", "CUSTOMER_EMAIL_INVALID",
  ].find((code) => message.includes(code));
  return known || "LICENSE_SERVER_ERROR";
}

function errorStatus(code: string): number {
  if (code === "LICENSE_KEY_INVALID" || code === "ACTIVATION_NOT_FOUND") return 401;
  if (["LICENSE_NOT_STARTED", "LICENSE_EXPIRED", "LICENSE_NOT_ACTIVE", "PLAN_INACTIVE"].includes(code)) return 403;
  if (["DEVICE_LIMIT_REACHED", "STORE_LIMIT_REACHED"].includes(code)) return 409;
  if (code === "TRIAL_ALREADY_USED") return 409;
  if (["STORE_REFERENCE_INVALID", "TRIAL_IDENTITY_INVALID", "CUSTOMER_NAME_REQUIRED", "CUSTOMER_EMAIL_INVALID"].includes(code)) return 400;
  return 500;
}

function clientIp(req: Request): string {
  return String(
    req.headers.get("cf-connecting-ip") ||
    req.headers.get("x-real-ip") ||
    req.headers.get("x-forwarded-for")?.split(",")[0] ||
    "unknown",
  ).trim();
}

function asObject(data: unknown): JsonRecord {
  if (Array.isArray(data)) return (data[0] || {}) as JsonRecord;
  return (data || {}) as JsonRecord;
}

Deno.serve(async (req) => {
  const cors = corsFor(req);
  if (!cors) return new Response(JSON.stringify({ error: "ORIGIN_NOT_ALLOWED" }), { status: 403 });
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return respond({ error: "METHOD_NOT_ALLOWED" }, 405, cors);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const secretKey = envKey("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY");
  const devicePepper = Deno.env.get("LDM_LICENSE_DEVICE_PEPPER") || "";
  if (!supabaseUrl || !secretKey || devicePepper.length < 32) {
    return respond({ error: "LICENSE_SERVER_NOT_CONFIGURED" }, 500, cors);
  }

  const admin = createClient(supabaseUrl, secretKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const body = await req.json().catch(() => ({})) as JsonRecord;
  const action = String(body.action || "").toLowerCase();
  const installationId = String(body.installationId || "").trim();
  const installationHash = installationId ? await sha256(`${devicePepper}:${installationId}`) : "";
  const ipHash = await sha256(`${devicePepper}:ip:${clientIp(req)}`);
  let licenseId: string | null = null;
  let createdTrialLicenseId: string | null = null;
  let keyPrefix = "";

  async function log(outcome: "success" | "failed" | "blocked", reason: string) {
    await admin.from("license_validation_events").insert({
      license_id: licenseId,
      action: ["activate", "validate", "deactivate", "start_trial"].includes(action) ? action : "validate",
      outcome,
      key_prefix: keyPrefix || null,
      installation_hash: installationHash || null,
      ip_hash: ipHash,
      reason: String(reason || "").slice(0, 160),
    }).then(() => undefined).catch(() => undefined);
  }

  try {
    if (!["activate", "validate", "deactivate", "start_trial"].includes(action)) {
      return respond({ error: "ACTION_INVALID" }, 400, cors);
    }
    if (installationId.length < 16 || installationId.length > 120) {
      return respond({ error: "INSTALLATION_ID_INVALID" }, 400, cors);
    }

    const tenMinutesAgo = new Date(Date.now() - 10 * 60 * 1000).toISOString();
    const { data: recentFailures } = await admin
      .from("license_validation_events")
      .select("id")
      .eq("ip_hash", ipHash)
      .in("outcome", ["failed", "blocked"])
      .gte("created_at", tenMinutesAgo)
      .limit(12);
    if ((recentFailures || []).length >= 12) {
      await log("blocked", "RATE_LIMITED");
      return respond({ error: "TOO_MANY_ATTEMPTS", retryAfterSeconds: 600 }, 429, cors);
    }

    if (action === "start_trial") {
      const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
      const { data: recentTrials } = await admin
        .from("license_validation_events")
        .select("id")
        .eq("ip_hash", ipHash)
        .eq("action", "start_trial")
        .eq("outcome", "success")
        .gte("created_at", oneDayAgo)
        .limit(3);
      if ((recentTrials || []).length >= 3) {
        await log("blocked", "TRIAL_IP_LIMIT_REACHED");
        return respond({ error: "TRIAL_IP_LIMIT_REACHED", retryAfterSeconds: 86400 }, 429, cors);
      }
    }

    let license: JsonRecord;
    let activationToken = String(body.activationToken || "").trim();

    if (action === "activate" || action === "start_trial") {
      let licenseKey = String(body.licenseKey || "").trim().toUpperCase();
      const storeRef = String(body.storeRef || "").trim();
      if (storeRef.length < 3 || storeRef.length > 100) {
        return respond({ error: "STORE_REFERENCE_INVALID" }, 400, cors);
      }
      if (action === "start_trial") {
        const customerName = String(body.customerName || "").trim();
        const customerEmail = String(body.customerEmail || "").trim().toLowerCase();
        const whatsapp = String(body.whatsapp || "").trim();
        if (body.trialConsent !== true) {
          return respond({ error: "TRIAL_CONSENT_REQUIRED" }, 400, cors);
        }
        if (customerName.length < 3 || customerName.length > 120) {
          return respond({ error: "CUSTOMER_NAME_REQUIRED" }, 400, cors);
        }
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(customerEmail) || customerEmail.length > 160) {
          return respond({ error: "CUSTOMER_EMAIL_INVALID" }, 400, cors);
        }
        const { data: trialData, error: trialError } = await admin.rpc("ldm_start_trial", {
          p_customer_name: customerName,
          p_customer_email: customerEmail,
          p_identity_hash: await sha256(`${devicePepper}:trial:${customerEmail}`),
          p_installation_hash: installationHash,
          p_whatsapp: whatsapp || null,
        });
        if (trialError) throw trialError;
        const trial = asObject(trialData);
        licenseKey = String(trial.license_key || "").toUpperCase();
        licenseId = String(trial.license_id || "") || null;
        createdTrialLicenseId = licenseId;
      }
      if (!/^LDM-[A-F0-9-]{35}$/.test(licenseKey)) {
        keyPrefix = licenseKey.slice(0, 12);
        await log("failed", "LICENSE_KEY_FORMAT_INVALID");
        return respond({ error: "LICENSE_KEY_FORMAT_INVALID" }, 400, cors);
      }
      keyPrefix = licenseKey.slice(0, 12);
      activationToken = randomToken();
      const { data, error } = await admin.rpc("ldm_license_activate", {
        p_key_hash: await sha256(licenseKey),
        p_installation_hash: installationHash,
        p_activation_token_hash: await sha256(activationToken),
        p_store_ref: storeRef,
        p_device_name: String(body.deviceName || "Perangkat LocDailyMar"),
        p_platform: String(body.platform || "browser"),
        p_app_version: String(body.appVersion || "unknown"),
      });
      if (error) throw error;
      license = asObject(data);
    } else {
      if (activationToken.length < 32) {
        await log("failed", "ACTIVATION_TOKEN_INVALID");
        return respond({ error: "ACTIVATION_TOKEN_INVALID" }, 401, cors);
      }
      if (action === "deactivate") {
        const { data, error } = await admin.rpc("ldm_license_deactivate", {
          p_activation_token_hash: await sha256(activationToken),
          p_installation_hash: installationHash,
        });
        if (error) throw error;
        await log("success", "DEACTIVATED");
        return respond({ ok: true, result: data }, 200, cors);
      }
      const { data, error } = await admin.rpc("ldm_license_validate", {
        p_activation_token_hash: await sha256(activationToken),
        p_installation_hash: installationHash,
        p_app_version: String(body.appVersion || "unknown"),
      });
      if (error) throw error;
      license = asObject(data);
    }

    licenseId = String(license.license_id || "") || null;
    const now = Date.now();
    const isLifetime = license.is_lifetime === true;
    const licenseExpiresAt = isLifetime
      ? null
      : new Date(String(license.license_expires_at)).getTime();
    if (!isLifetime && (!licenseExpiresAt || Number.isNaN(licenseExpiresAt))) {
      throw new Error("LICENSE_EXPIRY_INVALID");
    }
    const graceMs = Number(license.offline_grace_days || 0) * 86400000;
    const graceUntil = new Date(
      isLifetime ? now + graceMs : Math.min(licenseExpiresAt as number, now + graceMs),
    ).toISOString();
    const certificate = await signCertificate({
      version: 1,
      issuer: "LocDailyMar License Authority",
      licenseId,
      customerName: license.customer_name,
      planCode: license.plan_code,
      planName: license.plan_name,
      isLifetime,
      isTrial: license.is_trial === true,
      trialEndsAt: license.trial_ends_at || null,
      features: license.features,
      maxDevices: license.max_devices,
      maxStores: license.max_stores,
      storeRef: license.store_ref,
      installationHash,
      issuedAt: new Date(now).toISOString(),
      onlineCheckAfter: new Date(now + 12 * 60 * 60 * 1000).toISOString(),
      offlineGraceUntil: graceUntil,
      licenseExpiresAt: isLifetime ? null : new Date(licenseExpiresAt as number).toISOString(),
    });

    await log("success", action === "start_trial" ? "TRIAL_STARTED" : action === "activate" ? "ACTIVATED" : "VALIDATED");
    return respond({
      ok: true,
      activationToken: ["activate", "start_trial"].includes(action) ? activationToken : undefined,
      certificate,
    }, 200, cors);
  } catch (error) {
    const code = safeMessage(error);
    console.error("License request failed:", code);
    await log("failed", code);
    if (action === "start_trial" && createdTrialLicenseId) {
      await admin.from("licenses").delete().eq("id", createdTrialLicenseId)
        .then(() => undefined).catch(() => undefined);
    }
    return respond({ error: code }, errorStatus(code), cors);
  }
});
