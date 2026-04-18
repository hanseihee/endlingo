/**
 * sync-subscription
 *
 * 클라이언트가 구매/복원/로그인 직후 자신의 RevenueCat entitlement 상태를
 * 서버 `user_subscriptions`로 즉시 동기화하기 위해 호출.
 *
 * RevenueCat webhook 지연으로 서버 tier가 stale한 상태를 보정하는 것이 목적.
 * 보안상 완벽한 서버 재검증은 RevenueCat Secret API Key가 필요하지만,
 * 현 단계에서는 클라가 보낸 entitlement 정보를 신뢰한다. 악용 시에도 본인 row에만
 * 영향이 있고, webhook이 도착하면 진실로 덮어써진다.
 *
 * Body:
 * {
 *   "is_premium": boolean,       // entitlement.isActive
 *   "product_id": string | null, // entitlement.productIdentifier
 *   "expires_at_ms": number | null // entitlement.expirationDate의 epoch ms
 * }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) {
    console.error("Missing required env vars");
    return json({ error: "server_config_missing" }, 500);
  }

  // ---- 1) JWT 검증 ----
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return json({ error: "unauthorized" }, 401);
  }
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return json({ error: "unauthorized" }, 401);
  }

  // ---- 2) 파싱 ----
  let body: {
    is_premium?: unknown;
    product_id?: unknown;
    expires_at_ms?: unknown;
  } = {};
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const isPremium = body.is_premium === true;
  const productId = typeof body.product_id === "string" ? body.product_id : null;
  const expiresAtMs = typeof body.expires_at_ms === "number" ? body.expires_at_ms : null;
  const expiresAt = expiresAtMs ? new Date(expiresAtMs).toISOString() : null;

  const newTier = isPremium ? "premium" : "free";

  // ---- 3) 현재 row 조회 (premium_activated_at 유지 판단) ----
  const admin = createClient(supabaseUrl, serviceKey);
  const { data: existing } = await admin
    .from("user_subscriptions")
    .select("tier, premium_activated_at")
    .eq("user_id", user.id)
    .maybeSingle();

  // Free → Premium 전환 시점 기록. 이미 premium인 상태면 기존 값 유지
  // (RENEWAL로 premium_activated_at이 초기화되면 quota가 무한 리셋되는 부작용 방지).
  let premiumActivatedAt: string | null;
  if (isPremium) {
    if (existing?.tier === "premium" && existing?.premium_activated_at) {
      premiumActivatedAt = existing.premium_activated_at as string;
    } else {
      premiumActivatedAt = new Date().toISOString();
    }
  } else {
    premiumActivatedAt = null;
  }

  // ---- 4) upsert ----
  const { error: upsertError } = await admin
    .from("user_subscriptions")
    .upsert({
      user_id: user.id,
      tier: newTier,
      is_active: isPremium,
      product_id: productId,
      expires_at: expiresAt,
      premium_activated_at: premiumActivatedAt,
      last_event: "CLIENT_SYNC",
      last_event_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    });

  if (upsertError) {
    console.error("sync-subscription upsert failed:", upsertError);
    return json({ error: "db_error" }, 500);
  }

  console.log(`[sync-subscription] user=${user.id} tier=${newTier} activated=${premiumActivatedAt ?? "-"}`);
  return json({
    ok: true,
    tier: newTier,
    premium_activated_at: premiumActivatedAt,
  });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders() },
  });
}

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}
