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

  // 클라가 보낸 hint(is_premium). 보안상 final tier 결정에는 쓰지 않지만,
  // RC empty race를 구분하는 보조 신호로 사용한다.
  let clientHintIsPremium = false;
  try {
    const body = await req.json();
    clientHintIsPremium = body?.is_premium === true;
  } catch { /* body 없음 — 기본값 false */ }

  // ---- 2) RevenueCat REST로 실제 entitlement 조회 (retry 포함) ----
  // 클라 hint는 신뢰 근거가 아니다. 신뢰 가능한 값은 오직 RevenueCat 응답.
  // 구매 직후 RC 서버가 Apple 영수증을 아직 반영하지 못한 경우 빈 subscriber가
  // 돌아오는 race가 있어, 짧은 retry + pending 응답으로 client가 free로 강등하지
  // 않도록 보호한다.
  const rcLookup = await fetchRCSubscriberWithRetry(rcSecret, user.id);

  // RC 통신 자체가 실패한 경우(네트워크 에러, 5xx 반복). 서버 상태 변경 없이 에러.
  if (rcLookup.status === "unreachable") {
    return json({ error: "revenuecat_unreachable" }, 503);
  }

  const adminClient = createClient(supabaseUrl, serviceKey);

  // 빈 subscriber(entitlement 없음)가 계속 돌아오는 경우는 세 가지.
  // (A) 실제로 구독이 없는 사용자(free)
  // (B) DB에 기존 premium 상태가 있는데 RC가 일시 empty → "DB premium valid" 분기
  // (C) 클라가 방금 구매해서 isPremium=true hint를 보냈지만 RC가 아직 receipt 미반영
  // (B)/(C) 모두 client tier를 free로 강등하지 않도록 pending 응답.
  const { data: existingForVerify } = await adminClient
    .from("user_subscriptions")
    .select("tier, is_active, expires_at, premium_activated_at")
    .eq("user_id", user.id)
    .maybeSingle();

  if (rcLookup.status === "empty") {
    // (B) 기존 DB premium 보호
    if (existingForVerify?.tier === "premium") {
      const expiresTs = existingForVerify.expires_at ? new Date(existingForVerify.expires_at as string).getTime() : 0;
      const stillValid = !existingForVerify.expires_at || expiresTs > Date.now();
      if (stillValid) {
        console.log(`[sync-subscription] user=${user.id} RC empty but DB premium valid — returning pending`);
        return json({
          ok: true,
          verification: "pending",
          reason: "rc_empty_but_db_premium_valid",
        });
      }
    }
    // (C) 클라가 구매 직후 hint=premium을 보냈는데 RC empty
    if (clientHintIsPremium) {
      console.log(`[sync-subscription] user=${user.id} client hint=premium but RC empty — returning pending`);
      return json({
        ok: true,
        verification: "pending",
        reason: "client_premium_rc_empty",
      });
    }
  }

  let isPremium = false;
  let productId: string | null = null;
  let expiresAt: string | null = null;

  if (rcLookup.status === "found" && rcLookup.subscriber) {
    const subscriber = rcLookup.subscriber;
    const entitlement = subscriber?.entitlements?.[ENTITLEMENT_ID];
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

  // ---- 3) premium_activated_at 유지 여부 판단 (위에서 조회한 existingForVerify 재사용) ----
  // Free → Premium 전환 순간만 새로 기록. 이미 premium이면 기존 시점 유지
  // (RENEWAL로 premium_activated_at이 초기화되면 quota가 무한 리셋되는 부작용 방지).
  let premiumActivatedAt: string | null;
  if (isPremium) {
    if (existingForVerify?.tier === "premium" && existingForVerify?.premium_activated_at) {
      premiumActivatedAt = existingForVerify.premium_activated_at as string;
    } else {
      premiumActivatedAt = new Date().toISOString();
    }
  } else {
    premiumActivatedAt = null;
  }

  // ---- 4) upsert ----
  const { error: upsertError } = await adminClient
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

/**
 * RC REST `/v1/subscribers/{id}`를 호출해 subscriber 정보를 가져온다.
 *
 * 반환값:
 *  - status: "found"       → subscriber에 entitlement 포함
 *  - status: "empty"       → subscriber는 있으나 entitlement 비어있음
 *                            (purchase 직후 지연 또는 실제 free 사용자)
 *  - status: "unreachable" → 네트워크/5xx/비정상 응답
 *
 * 빈 subscriber가 돌아오는 경우 짧게 2회 재시도해 RC 서버가 영수증을
 * 받아들일 시간을 준다. 최종 empty는 free로 확정하지 않고 호출자가 판단.
 */
async function fetchRCSubscriberWithRetry(
  rcSecret: string,
  userId: string,
): Promise<
  | { status: "found"; subscriber: any }
  | { status: "empty"; subscriber: any }
  | { status: "unreachable" }
> {
  const rcUrl = `${RC_API_BASE}/subscribers/${encodeURIComponent(userId)}`;
  const maxAttempts = 3;
  let lastSubscriber: any = null;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    let response: Response;
    try {
      response = await fetch(rcUrl, {
        headers: {
          "Authorization": `Bearer ${rcSecret}`,
          "Accept": "application/json",
        },
      });
    } catch (e) {
      console.error(`[sync-subscription] RC fetch error (attempt ${attempt}):`, e);
      if (attempt === maxAttempts) return { status: "unreachable" };
      await sleep(400 * attempt);
      continue;
    }

    // 404는 "해당 id로 기록 없음" — 재시도해도 의미 없음.
    if (response.status === 404) {
      return { status: "empty", subscriber: null };
    }
    if (!response.ok) {
      const body = await response.text().catch(() => "");
      console.error(`[sync-subscription] RC ${response.status} (attempt ${attempt}): ${body.slice(0, 300)}`);
      if (attempt === maxAttempts) return { status: "unreachable" };
      await sleep(400 * attempt);
      continue;
    }

    const bodyText = await response.text();
    if (attempt === 1) {
      console.log(`[sync-subscription] RC raw body (first 1500 chars): ${bodyText.slice(0, 1500)}`);
    }
    const data = (() => { try { return JSON.parse(bodyText); } catch { return null; } })();
    const subscriber = data?.subscriber;
    lastSubscriber = subscriber;
    const entitlement = subscriber?.entitlements?.["premium"];
    console.log(`[sync-subscription] parsed (attempt ${attempt}): original_app_user_id=${subscriber?.original_app_user_id ?? "?"}, entitlements_keys=${Object.keys(subscriber?.entitlements ?? {}).join(",")}`);

    if (entitlement) {
      return { status: "found", subscriber };
    }
    // 빈 entitlement: 재시도로 RC 서버 영수증 처리 시간 확보.
    if (attempt < maxAttempts) {
      await sleep(500 * attempt);
    }
  }
  return { status: "empty", subscriber: lastSubscriber };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
