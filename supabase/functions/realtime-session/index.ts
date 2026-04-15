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

/// 로그인 사용자 일일 통화 한도.
/// 향후 구독 티어별 차등 적용 시 user metadata 또는 별도 테이블에서 조회하도록 확장.
const DAILY_LIMIT = 10;

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

  const { count, error: countError } = await adminClient
    .from("phone_call_sessions")
    .select("*", { count: "exact", head: true })
    .eq("user_id", user.id)
    .gte("started_at", todayStartUTC.toISOString());

  if (countError) {
    console.error("Quota check failed:", countError);
    // fail-closed: 장애 시 차단해 비용 폭탄 방지
    return json({ error: "quota_check_failed" }, 503);
  }

  const usedToday = count ?? 0;
  if (usedToday >= DAILY_LIMIT) {
    return json({
      error: "daily_limit_reached",
      limit: DAILY_LIMIT,
      used: usedToday,
    }, 429);
  }

  // ---- 3) voice 파라미터 파싱 ----
  let voice = "alloy";
  try {
    const body = await req.json();
    if (typeof body.voice === "string" && ALLOWED_VOICES.has(body.voice)) {
      voice = body.voice;
    }
  } catch {
    // body 없음 — 기본값 사용
  }

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

    return json({
      ephemeral_key: clientSecret.value,
      expires_at: clientSecret.expires_at ?? null,
      model: data.model ?? "gpt-realtime-mini",
      remaining_today: DAILY_LIMIT - usedToday - 1,
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
