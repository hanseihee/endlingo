/**
 * sync-subscription
 *
 * 클라이언트가 구매/복원/로그인 시점에 호출해 본인의 구독 상태를 서버와 동기화.
 *
 * 보안: 클라 입력(body)은 무시하고, 서버가 RevenueCat REST API로 직접 재검증한 값을
 *       user_subscriptions에 반영한다. 악의적 사용자가 is_premium=true로 위조한
 *       요청을 보내도 서버는 RevenueCat의 실제 entitlement만 신뢰한다.
 *
 * 환경변수:
 *  - SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY
 *  - REVENUECAT_SECRET_API_KEY: RevenueCat Dashboard → Project Settings →
 *    API keys → Secret API keys에서 발급한 sk_... 키.
 *    Supabase에 `supabase secrets set REVENUECAT_SECRET_API_KEY=sk_...`로 등록.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ENTITLEMENT_ID = "premium";
const RC_API_BASE = "https://api.revenuecat.com/v1";

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
  const rcSecret = Deno.env.get("REVENUECAT_SECRET_API_KEY");

  if (!supabaseUrl || !anonKey || !serviceKey || !rcSecret) {
    console.error("Missing required env vars (need SUPABASE_* + REVENUECAT_SECRET_API_KEY)");
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

  // ---- 2) RevenueCat REST로 실제 entitlement 조회 ----
  // 클라가 보낸 body는 의도적으로 무시. 신뢰 가능한 값은 오직 RevenueCat 응답.
  const rcUrl = `${RC_API_BASE}/subscribers/${encodeURIComponent(user.id)}`;
  let rcResponse: Response;
  try {
    rcResponse = await fetch(rcUrl, {
      headers: {
        "Authorization": `Bearer ${rcSecret}`,
        "Accept": "application/json",
      },
    });
  } catch (e) {
    console.error("RevenueCat fetch failed:", e);
    return json({ error: "revenuecat_unreachable" }, 503);
  }

  // 404는 "해당 app_user_id로 기록 없음" 의미 — 신규/비구매 사용자. free로 취급.
  // 200은 entitlement 포함 가능한 정상 응답.
  // 그 외 상태는 신뢰할 수 없는 응답이므로 서버 상태 변경 없이 에러 반환.
  if (!rcResponse.ok && rcResponse.status !== 404) {
    const body = await rcResponse.text().catch(() => "");
    console.error(`RevenueCat ${rcResponse.status}:`, body.slice(0, 300));
    return json({ error: "revenuecat_error", status: rcResponse.status }, 503);
  }

  let isPremium = false;
  let productId: string | null = null;
  let expiresAt: string | null = null;

  if (rcResponse.ok) {
    const rcData = await rcResponse.json().catch(() => null);
    const entitlement = rcData?.subscriber?.entitlements?.[ENTITLEMENT_ID];

    if (entitlement) {
      if (entitlement.expires_date) {
        const expiresDate = new Date(entitlement.expires_date as string);
        if (!isNaN(expiresDate.getTime()) && expiresDate > new Date()) {
          isPremium = true;
          expiresAt = expiresDate.toISOString();
        }
      } else {
        // 만료 없는 non-consumable entitlement — premium 유지
        isPremium = true;
      }
      if (typeof entitlement.product_identifier === "string") {
        productId = entitlement.product_identifier;
      }
    }
  }

  const newTier = isPremium ? "premium" : "free";

  // ---- 3) 기존 row 조회로 premium_activated_at 유지 여부 판단 ----
  const admin = createClient(supabaseUrl, serviceKey);
  const { data: existing } = await admin
    .from("user_subscriptions")
    .select("tier, premium_activated_at")
    .eq("user_id", user.id)
    .maybeSingle();

  // Free → Premium 전환 순간만 새로 기록. 이미 premium이면 기존 시점 유지
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
      last_event: "CLIENT_SYNC_VERIFIED",
      last_event_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    });

  if (upsertError) {
    console.error("sync-subscription upsert failed:", upsertError);
    return json({ error: "db_error" }, 500);
  }

  console.log(`[sync-subscription] user=${user.id} tier=${newTier} expires=${expiresAt ?? "-"} activated=${premiumActivatedAt ?? "-"} (rc-verified)`);
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
