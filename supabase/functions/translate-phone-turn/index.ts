import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * 전화영어 중 실시간 번역.
 * 한 발화(turn) 단위로 OpenAI gpt-5.4-mini 또는 Gemini 3.1 Flash Lite에 번역 요청.
 *
 * Request: {
 *   text: "English sentence",
 *   native_language: "ko" | "ja" | "vi" | "en",
 *   provider?: "openai" | "gemini"   // default: openai
 * }
 * Response: { translation: "번역문" }
 */

const LANG_NAMES: Record<string, string> = {
  ko: "Korean",
  ja: "Japanese",
  vi: "Vietnamese",
  en: "English",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors() });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const openaiKey = Deno.env.get("OPENAI_API_KEY");
  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) {
    return json({ error: "server_config_missing" }, 500);
  }

  // 인증: access token에서 user 추출
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return json({ error: "unauthorized" }, 401);

  // body
  let text = "";
  let language = "ko";
  let provider = "openai";
  try {
    const body = await req.json();
    if (typeof body.text === "string") text = body.text.trim();
    if (typeof body.native_language === "string" && body.native_language in LANG_NAMES) {
      language = body.native_language;
    }
    if (body.provider === "gemini" || body.provider === "openai") {
      provider = body.provider;
    }
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!text || text.length > 600) return json({ error: "invalid_text" }, 400);

  const langName = LANG_NAMES[language];
  const systemPrompt = `You translate a single English sentence into ${langName}. Respond with ONLY the ${langName} translation. No quotes, no brackets, no explanations. Keep it natural and conversational.`;

  try {
    const translation = provider === "gemini"
      ? await translateWithGemini(geminiKey, systemPrompt, text)
      : await translateWithOpenAI(openaiKey, systemPrompt, text);
    return json({ translation });
  } catch (err) {
    console.error(`Translate (${provider}) failed:`, err);
    return json({ error: String(err) }, 502);
  }
});

async function translateWithOpenAI(apiKey: string | undefined, systemPrompt: string, text: string): Promise<string> {
  if (!apiKey) throw new Error("OPENAI_API_KEY missing");
  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-5.4-mini",
      max_completion_tokens: 200,
      temperature: 0.3,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: text },
      ],
    }),
  });
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`openai_${response.status}: ${detail.slice(0, 200)}`);
  }
  const data = await response.json();
  return (data.choices?.[0]?.message?.content ?? "").trim();
}

async function translateWithGemini(apiKey: string | undefined, systemPrompt: string, text: string): Promise<string> {
  if (!apiKey) throw new Error("GEMINI_API_KEY missing");
  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=${apiKey}`;
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: systemPrompt }] },
      contents: [{ role: "user", parts: [{ text }] }],
      generationConfig: {
        temperature: 0.3,
        maxOutputTokens: 200,
      },
    }),
  });
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`gemini_${response.status}: ${detail.slice(0, 200)}`);
  }
  const data = await response.json();
  const content = data.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  return content.trim();
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...cors() },
  });
}

function cors(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}
