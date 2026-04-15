/**
 * OpenAI Realtime API용 ephemeral client_secret 발급.
 *
 * 플로우:
 *  1. iOS 앱이 anon key로 이 Edge Function을 호출 (voice 파라미터 포함)
 *  2. Function이 서버의 OPENAI_API_KEY로 OpenAI에 session 생성 요청
 *  3. 반환된 ephemeral key는 수 분 내 만료되며 iOS 앱이 WebSocket 인증에 사용
 *
 * 보안:
 *  - 실제 OpenAI API key는 Supabase 환경 변수에만 존재, 클라이언트 노출 없음
 *  - ephemeral key는 만료되므로 유출되더라도 피해 범위 제한적
 */

const ALLOWED_VOICES = new Set([
  "alloy", "ash", "ballad", "coral", "echo", "sage", "shimmer", "verse",
]);

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

  const openaiKey = Deno.env.get("OPENAI_API_KEY");
  if (!openaiKey) {
    return json({ error: "OPENAI_API_KEY not set" }, 500);
  }

  let voice = "alloy";
  try {
    const body = await req.json();
    if (typeof body.voice === "string" && ALLOWED_VOICES.has(body.voice)) {
      voice = body.voice;
    }
  } catch {
    // body 없으면 기본값
  }

  try {
    const response = await fetch("https://api.openai.com/v1/realtime/sessions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openaiKey}`,
        "Content-Type": "application/json",
        "OpenAI-Beta": "realtime=v1",
      },
      body: JSON.stringify({
        model: "gpt-realtime",
        voice,
        modalities: ["audio", "text"],
      }),
    });

    if (!response.ok) {
      const errText = await response.text();
      console.error(`OpenAI session error ${response.status}: ${errText}`);
      return json({ error: `OpenAI API error: ${response.status}`, detail: errText }, 502);
    }

    const data = await response.json();
    // OpenAI 응답 스키마:
    //   { client_secret: { value: "ek_...", expires_at: <unix> }, model: "gpt-realtime", ... }
    const clientSecret = data?.client_secret;
    if (!clientSecret?.value) {
      console.error(`Unexpected OpenAI response: ${JSON.stringify(data).slice(0, 500)}`);
      return json({ error: "client_secret missing in OpenAI response" }, 502);
    }

    return json({
      ephemeral_key: clientSecret.value,
      expires_at: clientSecret.expires_at ?? null,
      model: data.model ?? "gpt-realtime",
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
