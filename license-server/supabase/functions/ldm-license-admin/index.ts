import { createClient } from "npm:@supabase/supabase-js@2";

type JsonRecord = Record<string, unknown>;
type CorsHeaders = Record<string, string>;

const VERSION = "23.2.0";

function configuredOrigins(): Set<string> {
  return new Set(
    String(Deno.env.get("LDM_LICENSE_ALLOWED_ORIGINS") || "")
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean),
  );
}

function corsFor(req: Request): CorsHeaders | null {
  const origin = req.headers.get("Origin") || "";
  const allowed = configuredOrigins();
  const allowNull = Deno.env.get("LDM_LICENSE_ALLOW_NULL_ORIGIN") === "true";
  if (origin && !allowed.has("*") && !allowed.has(origin) && !(origin === "null" && allowNull)) return null;
  return {
    "Access-Control-Allow-Origin": origin || [...allowed][0] || "https://invalid.local",
    "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}

function respond(data: unknown, status: number, cors: CorsHeaders): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function adminEmails(): Set<string> {
  return new Set(
    String(Deno.env.get("LDM_LICENSE_ADMIN_EMAILS") || "")
      .split(",")
      .map((email) => email.trim().toLowerCase())
      .filter(Boolean),
  );
}

function messageOf(error: unknown): string {
  return String((error as { message?: string })?.message || error || "UNKNOWN_ERROR");
}

function safeErrorCode(error: unknown): string {
  const message = messageOf(error);
  const known = [
    "ADMIN_AUTH_REQUIRED",
    "ADMIN_ACCESS_DENIED",
    "ADMIN_ALLOWLIST_NOT_CONFIGURED",
    "LICENSE_NOT_FOUND",
    "LICENSE_RENEWAL_REQUIRED",
    "ACTIVE_ACTIVATION_NOT_FOUND",
    "INVALID_LICENSE_STATUS",
    "ACTION_INVALID",
    "LICENSE_ID_INVALID",
    "ACTIVATION_ID_INVALID",
  ];
  return known.find((code) => message.includes(code)) || "LICENSE_ADMIN_SERVER_ERROR";
}

function statusFor(code: string): number {
  if (code === "ADMIN_AUTH_REQUIRED") return 401;
  if (code === "ADMIN_ACCESS_DENIED") return 403;
  if (["LICENSE_NOT_FOUND", "ACTIVE_ACTIVATION_NOT_FOUND"].includes(code)) return 404;
  if (code === "LICENSE_RENEWAL_REQUIRED") return 409;
  if (code === "LICENSE_ADMIN_SERVER_ERROR" || code === "ADMIN_ALLOWLIST_NOT_CONFIGURED") return 500;
  return 400;
}

function uuid(value: unknown, code: string): string {
  const text = String(value || "").trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text)) {
    throw new Error(code);
  }
  return text;
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const cors = corsFor(req);
  if (!cors) {
    return new Response(JSON.stringify({ error: "ORIGIN_NOT_ALLOWED", requestId }), {
      status: 403,
      headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
    });
  }
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return respond({ error: "METHOD_NOT_ALLOWED", requestId }, 405, cors);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  const allowlist = adminEmails();
  if (!supabaseUrl || !serviceKey) {
    return respond({ error: "LICENSE_ADMIN_SERVER_NOT_CONFIGURED", requestId }, 500, cors);
  }
  if (!allowlist.size) return respond({ error: "ADMIN_ALLOWLIST_NOT_CONFIGURED", requestId }, 500, cors);

  const bearer = String(req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
  if (!bearer) return respond({ error: "ADMIN_AUTH_REQUIRED", requestId }, 401, cors);

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const { data: authData, error: authError } = await admin.auth.getUser(bearer);
  const user = authData?.user;
  const email = String(user?.email || "").trim().toLowerCase();
  if (authError || !user || !email) return respond({ error: "ADMIN_AUTH_REQUIRED", requestId }, 401, cors);
  if (!allowlist.has(email)) return respond({ error: "ADMIN_ACCESS_DENIED", requestId }, 403, cors);

  const body = await req.json().catch(() => ({})) as JsonRecord;
  const action = String(body.action || "dashboard").trim().toLowerCase();

  async function audit(
    auditAction: string,
    licenseId: string | null,
    activationId: string | null,
    detail: JsonRecord = {},
  ) {
    const { error } = await admin.from("license_admin_audit").insert({
      actor_user_id: user.id,
      actor_email: email,
      action: auditAction,
      license_id: licenseId,
      activation_id: activationId,
      detail: { ...detail, request_id: requestId },
    });
    if (error) console.error(requestId, "AUDIT_WRITE_FAILED", error.message);
  }

  try {
    if (action === "health") {
      return respond({ ok: true, service: "ldm-license-admin", version: VERSION, adminEmail: email, requestId }, 200, cors);
    }

    if (action === "dashboard" || action === "list_licenses") {
      const [licensesResult, trialsResult, auditResult] = await Promise.all([
        admin.from("license_customer_monitor").select("*").order("starts_at", { ascending: false }).limit(1000),
        admin.from("license_trial_monitor").select("*").order("trial_started_at", { ascending: false }).limit(500),
        admin.from("license_admin_audit").select("id,actor_email,action,license_id,activation_id,detail,created_at")
          .order("created_at", { ascending: false }).limit(40),
      ]);
      if (licensesResult.error) throw licensesResult.error;
      if (trialsResult.error) throw trialsResult.error;
      if (auditResult.error) throw auditResult.error;

      const licenses = licensesResult.data || [];
      const now = Date.now();
      const summary = licenses.reduce((result: Record<string, number>, item: JsonRecord) => {
        result.total += 1;
        const expiresAt = item.expires_at ? new Date(String(item.expires_at)).getTime() : null;
        const effectiveExpired = item.is_lifetime !== true && expiresAt !== null && expiresAt <= now;
        const status = effectiveExpired ? "expired" : String(item.status || "unknown");
        if (status === "active") result.active += 1;
        if (status === "suspended") result.suspended += 1;
        if (status === "expired") result.expired += 1;
        if (item.is_trial === true && status === "active") result.trial += 1;
        result.devices += Number(item.active_devices || 0);
        return result;
      }, { total: 0, active: 0, trial: 0, suspended: 0, expired: 0, devices: 0 });

      return respond({
        ok: true,
        adminEmail: email,
        summary,
        licenses,
        trials: trialsResult.data || [],
        audit: auditResult.data || [],
        requestId,
      }, 200, cors);
    }

    if (action === "list_devices") {
      const licenseId = uuid(body.licenseId, "LICENSE_ID_INVALID");
      const { data, error } = await admin.from("license_activations")
        .select("id,license_id,store_ref,device_name,platform,app_version,status,first_activated_at,last_validated_at,deactivated_at")
        .eq("license_id", licenseId)
        .order("last_validated_at", { ascending: false });
      if (error) throw error;
      return respond({ ok: true, devices: data || [], requestId }, 200, cors);
    }

    if (action === "set_status") {
      const licenseId = uuid(body.licenseId, "LICENSE_ID_INVALID");
      const status = String(body.status || "").trim().toLowerCase();
      if (!["active", "suspended"].includes(status)) throw new Error("INVALID_LICENSE_STATUS");
      const reason = String(body.reason || (status === "suspended" ? "Ditangguhkan oleh developer" : "Diaktifkan oleh developer"))
        .trim().slice(0, 240);
      const { data, error } = await admin.rpc("ldm_set_license_status", {
        p_license_id: licenseId,
        p_status: status,
        p_reason: reason,
      });
      if (error) throw error;
      await audit(status === "suspended" ? "license_suspended" : "license_activated", licenseId, null, { reason });
      return respond({ ok: true, result: data, requestId }, 200, cors);
    }

    if (action === "deactivate_device") {
      const activationId = uuid(body.activationId, "ACTIVATION_ID_INVALID");
      const { data, error } = await admin.rpc("ldm_admin_deactivate_activation", { p_activation_id: activationId });
      if (error) throw error;
      const result = (Array.isArray(data) ? data[0] : data || {}) as JsonRecord;
      const licenseId = result.license_id ? String(result.license_id) : null;
      await audit("device_deactivated", licenseId, activationId, {
        store_ref: result.store_ref || null,
        device_name: result.device_name || null,
      });
      return respond({ ok: true, result, requestId }, 200, cors);
    }

    return respond({ error: "ACTION_INVALID", requestId }, 400, cors);
  } catch (error) {
    const code = safeErrorCode(error);
    console.error(requestId, "License admin request failed", code, messageOf(error));
    return respond({
      error: code,
      detail: code === "LICENSE_ADMIN_SERVER_ERROR" ? "Periksa Edge Function Logs memakai Request ID." : undefined,
      requestId,
    }, statusFor(code), cors);
  }
});
