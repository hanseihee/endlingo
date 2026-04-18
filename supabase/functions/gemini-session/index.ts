import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * Gemini Live API용 세션 등록 + quota 관리.
 *
 * 클라이언트가 Gemini API key로 직접 인증하므로 ephemeral key는 발급하지 않습니다.
 * 이 Edge Function은 quota 관리 + pending row 삽입만 수행합니다.
 *
 * 환경변수:
 *  - SUPABASE_URL, SUPABASE_ANON_KEY: 사용자 JWT 검증용
 *  - SUPABASE_SERVICE_ROLE_KEY: quota 카운트용 (RLS 우회)
 */

const TIER_LIMITS: Record<string, { dailySeconds: number; maxSingleSeconds: number }> = {
  free:    { dailySeconds: 120, maxSingleSeconds: 120 },
  premium: { dailySeconds: 600, maxSingleSeconds: 600 },
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: corsHeaders(),
    });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
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
    return json({ error: "unauthorized", message: "login required" }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return json({ error: "unauthorized", message: "login required" }, 401);
  }

  // ---- 2) 일일 quota 체크 ----
  const adminClient = createClient(supabaseUrl, serviceKey);
  const now = new Date();
  const todayStartUTC = new Date(Date.UTC(
    now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 0, 0, 0,
  ));

  // 통화 응답 전·도중 비정상 종료(앱 강제종료/네트워크 단절 등)로 남은 pending row를
  // premium 최대 통화 시간(10분)보다 넉넉하게 보고, 15분 경과 시 expired로 강제 전환.
  // 기존 cron은 24시간 이후에만 정리하므로 같은 날 재시도가 call_in_progress로 막혔음.
  const STALE_PENDING_MS = 15 * 60 * 1000;
  const staleThreshold = new Date(Date.now() - STALE_PENDING_MS).toISOString();
  const { error: staleCleanupError } = await adminClient
    .from("phone_call_sessions")
    .update({
      status: "expired",
      duration_seconds: 0,
      completed_at: new Date().toISOString(),
    })
    .eq("user_id", user.id)
    .eq("status", "pending")
    .lt("started_at", staleThreshold);
  if (staleCleanupError) {
    console.error("Stale pending cleanup failed:", staleCleanupError);
    // cleanup 실패는 치명적이지 않음 — 정상 로직 계속 진행
  }

  // 구독 상태 선조회 — quota 계산 기준 시점 결정을 위해 필요.
  const { data: subData } = await adminClient
    .from("user_subscriptions")
    .select("tier, is_active, expires_at, premium_activated_at")
    .eq("user_id", user.id)
    .maybeSingle();

  // 서버 tier 판정을 먼저 수행 (effectiveStart와 quota 합산 모두에서 사용).
  // tier=premium이라고 해도 is_active=false(환불/취소)나 expires_at 경과는 free로 다운그레이드.
  const serverTier = (
    subData?.tier === "premium" &&
    subData?.is_active !== false &&
    (!subData.expires_at || new Date(subData.expires_at as string) > new Date())
  ) ? "premium" : "free";

  // 합산 기준 시점 결정:
  // - Premium인 경우: Free → Premium 전환 이후 세션만 합산 (깨끗한 quota 재시작)
  // - Free인 경우: UTC 오늘 전체
  const effectiveStart = (() => {
    if (serverTier === "premium" && subData?.premium_activated_at) {
      const activatedAt = new Date(subData.premium_activated_at as string);
      return activatedAt > todayStartUTC ? activatedAt : todayStartUTC;
    }
    return todayStartUTC;
  })();

  const { data: usageData, error: usageError } = await adminClient
    .from("phone_call_sessions")
    .select("duration_seconds, status, started_at, tier_at_session")
    .eq("user_id", user.id)
    .gte("started_at", effectiveStart.toISOString());

  if (usageError) {
    console.error("Quota check failed:", usageError);
    return json({ error: "quota_check_failed" }, 503);
  }

  // 동시 통화 방지: effectiveStart와 무관하게 오늘 전체에서 pending row 확인.
  // (전환 시점 직전에 시작된 pending row도 차단해야 하므로)
  const { data: pendingData } = await adminClient
    .from("phone_call_sessions")
    .select("id")
    .eq("user_id", user.id)
    .eq("status", "pending")
    .gte("started_at", todayStartUTC.toISOString());
  if ((pendingData?.length ?? 0) > 0) {
    return json({ error: "call_in_progress", message: "이미 진행 중인 통화가 있습니다" }, 429);
  }

  // Free quota는 tier_at_session='free' 세션만 합산 — Premium 시기 통화는 제외.
  // Premium quota는 effectiveStart(=premium_activated_at) 이후 모든 세션 합산.
  const usedSeconds = (usageData || [])
    .filter((r: { tier_at_session?: string }) =>
      serverTier === "premium" || r.tier_at_session !== "premium"
    )
    .reduce(
      (sum: number, r: { duration_seconds: number }) => sum + (r.duration_seconds || 0),
      0
    );

  // ---- 3) 요청 파라미터 파싱 ----
  let scenarioId = "unknown";
  let scenarioTitle = "Phone Call";
  let personaName = "AI";
  let personaEmoji = "📞";
  try {
    const body = await req.json();
    if (typeof body.scenario_id === "string") scenarioId = body.scenario_id;
    if (typeof body.scenario_title === "string") scenarioTitle = body.scenario_title;
    if (typeof body.persona_name === "string") personaName = body.persona_name;
    if (typeof body.persona_emoji === "string") personaEmoji = body.persona_emoji;
  } catch {
    // body 없음 — 기본값 사용
  }

  // ---- 4) tier 검증 (위에서 결정한 serverTier 재사용) ----
  const limits = TIER_LIMITS[serverTier] || TIER_LIMITS.free;
  if (usedSeconds >= limits.dailySeconds) {
    return json({
      error: "daily_limit_reached",
      tier: serverTier,
      daily_limit_seconds: limits.dailySeconds,
      used_seconds: usedSeconds,
    }, 429);
  }
  const remainingSeconds = limits.dailySeconds - usedSeconds;
  const maxDuration = Math.min(remainingSeconds, limits.maxSingleSeconds);

  // ---- 5) pending row 삽입 ----
  const { data: insertedRow, error: insertError } = await adminClient
    .from("phone_call_sessions")
    .insert({
      user_id: user.id,
      scenario_id: scenarioId,
      scenario_title: scenarioTitle,
      persona_name: personaName,
      persona_emoji: personaEmoji,
      duration_seconds: 0,
      started_at: new Date().toISOString(),
      status: "pending",
      transcript: [],
      tier_at_session: serverTier,
    })
    .select("id")
    .single();

  // pending row insert 실패 시 200으로 넘기면 동시통화 차단과 quota 합산이
  // 모두 뚫리므로 500으로 실패시키고 클라이언트가 통화를 시작하지 못하게 한다.
  if (insertError || !insertedRow?.id) {
    console.error("pending session insert failed:", insertError);
    return json({ error: "session_register_failed" }, 500);
  }

  return json({
    provider: "gemini",
    tier: serverTier,
    max_duration_seconds: maxDuration,
    remaining_seconds_today: remainingSeconds - maxDuration,
    session_id: insertedRow.id,
  });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders(),
    },
  });
}

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}
