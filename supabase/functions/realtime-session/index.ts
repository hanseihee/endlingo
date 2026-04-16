import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * OpenAI Realtime API용 ephemeral client_secret 발급.
 *
 * 보안 설계:
 *  1. Authorization 헤더에서 사용자 JWT 추출 (로그인 필수)
 *  2. phone_call_sessions 테이블에서 오늘 통화 수 조회
 *  3. 일일 한도(DAILY_LIMIT) 초과 시 429 거부
 *  4. OpenAI 세션 생성 및 ephemeral_key 반환
 *
 * 환경변수:
 *  - OPENAI_API_KEY: OpenAI 호출용
 *  - SUPABASE_URL, SUPABASE_ANON_KEY: 사용자 JWT 검증용
 *  - SUPABASE_SERVICE_ROLE_KEY: quota 카운트용 (RLS 우회)
 */

const ALLOWED_VOICES = new Set([
  "alloy", "ash", "ballad", "coral", "echo", "sage", "shimmer", "verse",
]);

/// 티어별 일일 통화 한도 (초 기준).
/// iOS SubscriptionService.Tier와 동기화. 클라이언트가 전달하는 tier를 신뢰(MVP).
/// 향후 RevenueCat REST API 또는 user_subscriptions 테이블로 서버 측 검증 예정.
const TIER_LIMITS: Record<string, { dailySeconds: number; maxSingleSeconds: number }> = {
  free:    { dailySeconds: 60,  maxSingleSeconds: 60  },
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

  // ---- 환경 변수 ----
  const openaiKey = Deno.env.get("OPENAI_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!openaiKey || !supabaseUrl || !anonKey || !serviceKey) {
    console.error("Missing required env vars");
    return json({ error: "server_config_missing" }, 500);
  }

  // ---- 1) JWT 검증: 로그인한 사용자만 ----
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return json({ error: "unauthorized", message: "login required" }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return json({
      error: "unauthorized",
      message: "login required",
      detail: authError?.message,
    }, 401);
  }

  // ---- 2) 일일 통화 quota 체크 ----
  const adminClient = createClient(supabaseUrl, serviceKey);
  const now = new Date();
  const todayStartUTC = new Date(Date.UTC(
    now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 0, 0, 0,
  ));

  // ---- 2b) 오늘 사용한 총 시간(초) 집계 ----
  const { data: usageData, error: usageError } = await adminClient
    .from("phone_call_sessions")
    .select("duration_seconds")
    .eq("user_id", user.id)
    .gte("started_at", todayStartUTC.toISOString());

  if (usageError) {
    console.error("Quota check failed:", usageError);
    return json({ error: "quota_check_failed" }, 503);
  }

  const usedSeconds = (usageData || []).reduce(
    (sum: number, r: { duration_seconds: number }) => sum + (r.duration_seconds || 0),
    0
  );

  // ---- 3) 요청 파라미터 파싱 ----
  let voice = "alloy";
  let scenarioId = "unknown";
  let scenarioTitle = "Phone Call";
  let personaName = "AI";
  let personaEmoji = "📞";
  let clientTier = "free";
  try {
    const body = await req.json();
    if (typeof body.voice === "string" && ALLOWED_VOICES.has(body.voice)) {
      voice = body.voice;
    }
    if (typeof body.scenario_id === "string") scenarioId = body.scenario_id;
    if (typeof body.scenario_title === "string") scenarioTitle = body.scenario_title;
    if (typeof body.persona_name === "string") personaName = body.persona_name;
    if (typeof body.persona_emoji === "string") personaEmoji = body.persona_emoji;
    if (typeof body.tier === "string" && body.tier in TIER_LIMITS) clientTier = body.tier;
  } catch {
    // body 없음 — 기본값 사용
  }

  // ---- 3b) 시간 기반 quota 체크 ----
  const limits = TIER_LIMITS[clientTier] || TIER_LIMITS.free;
  if (usedSeconds >= limits.dailySeconds) {
    return json({
      error: "daily_limit_reached",
      tier: clientTier,
      daily_limit_seconds: limits.dailySeconds,
      used_seconds: usedSeconds,
    }, 429);
  }
  const remainingSeconds = limits.dailySeconds - usedSeconds;
  const maxDuration = Math.min(remainingSeconds, limits.maxSingleSeconds);

  // ---- 4) OpenAI 세션 발급 ----
  try {
    const response = await fetch("https://api.openai.com/v1/realtime/sessions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openaiKey}`,
        "Content-Type": "application/json",
        "OpenAI-Beta": "realtime=v1",
      },
      body: JSON.stringify({
        // 비용 최적화: gpt-realtime-mini 사용 (gpt-realtime 대비 오디오 약 70% 저렴).
        // 시나리오 롤플레이/CEFR 가이드 준수는 충분히 수행 — 품질 저하 시 gpt-realtime으로 복원.
        model: "gpt-realtime-mini",
        voice,
        modalities: ["audio", "text"],
      }),
    });

    if (!response.ok) {
      const errText = await response.text();
      console.error(`OpenAI session error ${response.status}: ${errText}`);
      return json({ error: `openai_error_${response.status}`, detail: errText }, 502);
    }

    const data = await response.json();
    const clientSecret = data?.client_secret;
    if (!clientSecret?.value) {
      console.error(`Unexpected OpenAI response: ${JSON.stringify(data).slice(0, 500)}`);
      return json({ error: "client_secret_missing" }, 502);
    }

    // ---- 5) phone_call_sessions에 pending row 선삽입 (quota 회피 차단) ----
    // OpenAI 호출 성공 직후 row를 만들어두면, iOS가 통화를 즉시 끊거나 기록 저장에
    // 실패해도 사용자의 일일 quota는 정확히 소진됨. iOS는 통화 종료 시 이 row를
    // UPDATE로 완성한다. 장시간 pending 상태 row는 별도 cleanup job으로 정리.
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
      })
      .select("id")
      .single();

    if (insertError) {
      console.error("pending session insert failed:", insertError);
      // pending row 실패해도 ephemeral key는 반환 (사용자 경험 우선).
      // 대신 클라이언트가 session_id 없이 동작하므로 이번 통화는 record() 경로로 fallback.
    }

    return json({
      ephemeral_key: clientSecret.value,
      expires_at: clientSecret.expires_at ?? null,
      model: data.model ?? "gpt-realtime-mini",
      tier: clientTier,
      max_duration_seconds: maxDuration,
      remaining_seconds_today: remainingSeconds - maxDuration,
      session_id: insertedRow?.id ?? null,
    });
  } catch (err) {
    console.error("Realtime session fetch failed:", err);
    return json({ error: String(err) }, 500);
  }
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
