/**
 * RevenueCat Webhook Handler
 *
 * RevenueCat이 구독 이벤트(구매/갱신/취소/만료 등) 발생 시 POST로 호출.
 * user_subscriptions 테이블에 tier/상태를 upsert해 서버 측 tier 검증의 source of truth 역할.
 *
 * 인증: RevenueCat 대시보드에서 설정한 Authorization header와 REVENUECAT_WEBHOOK_SECRET 비교.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  // ---- 1) Webhook 인증 ----
  const webhookSecret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
  const authHeader = req.headers.get("Authorization");

  if (webhookSecret && authHeader !== `Bearer ${webhookSecret}`) {
    console.error("Webhook auth failed");
    return json({ error: "unauthorized" }, 401);
  }

  // ---- 2) Supabase admin client ----
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(supabaseUrl, serviceKey);

  // ---- 3) 이벤트 파싱 ----
  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const event = body?.event;
  if (!event) {
    return json({ error: "missing_event" }, 400);
  }

  const type: string = event.type ?? "UNKNOWN";
  const appUserId: string | undefined = event.app_user_id;
  const productId: string | undefined = event.product_id;
  const expiresAtMs: number | undefined = event.expiration_at_ms;
  const expiresAt = expiresAtMs ? new Date(expiresAtMs).toISOString() : null;

  if (!appUserId) {
    console.error("Webhook missing app_user_id:", JSON.stringify(event).slice(0, 300));
    return json({ error: "missing_app_user_id" }, 400);
  }

  console.log(`[Webhook] type=${type}, user=${appUserId}, product=${productId}, expires=${expiresAt}`);

  // ---- 4) Tier 결정 ----
  const activeEvents = new Set([
    "INITIAL_PURCHASE",
    "RENEWAL",
    "UNCANCELLATION",
    "NON_RENEWING_PURCHASE",
    "PRODUCT_CHANGE",
  ]);
  const cancelEvents = new Set([
    "CANCELLATION",          // 취소했지만 기간 남음
    "BILLING_ISSUE_DETECTED",
  ]);
  const expireEvents = new Set([
    "EXPIRATION",
  ]);

  let tier = "free";
  let isActive = false;

  if (activeEvents.has(type)) {
    tier = "premium";
    isActive = true;
  } else if (cancelEvents.has(type)) {
    // 취소/결제 문제지만 만료 전까지 premium 유지
    tier = "premium";
    isActive = true;
  } else if (expireEvents.has(type)) {
    tier = "free";
    isActive = false;
  } else {
    // SUBSCRIBER_ALIAS, TRANSFER 등 — 무시하고 OK 반환
    console.log(`[Webhook] ignored event type: ${type}`);
    return json({ ok: true });
  }

  // ---- 5) DB upsert ----
  const { error: upsertError } = await admin
    .from("user_subscriptions")
    .upsert({
      user_id: appUserId,
      tier,
      is_active: isActive,
      product_id: productId ?? null,
      expires_at: expiresAt,
      last_event: type,
      last_event_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    });

  if (upsertError) {
    console.error("Upsert failed:", upsertError);
    return json({ error: "db_error" }, 500);
  }

  console.log(`[Webhook] upserted user=${appUserId} tier=${tier} active=${isActive}`);
  return json({ ok: true });
});
