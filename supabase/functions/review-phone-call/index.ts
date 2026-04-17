import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * 통화 종료 후 사용자 발화 피드백 생성 (Gemini 3.1 Flash Lite).
 * 어색하거나 잘못된 문장을 자연스러운 영어로 교정 + 네이티브 언어로 설명.
 *
 * Request:
 *   {
 *     transcript: [{ speaker: "user"|"assistant", text: string }, ...],
 *     native_language: "ko" | "ja" | "vi" | "en",
 *     level: "A1" | "A2" | ... | "C2"
 *   }
 * Response: { issues: [{ original, improved, explanation }, ...] }  (0~5개)
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

  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) {
    return json({ error: "server_config_missing" }, 500);
  }

  // 인증
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return json({ error: "unauthorized" }, 401);

  // body
  interface Turn { speaker: string; text: string; }
  let transcript: Turn[] = [];
  let language = "ko";
  let level = "A2";
  try {
    const body = await req.json();
    if (Array.isArray(body.transcript)) {
      transcript = body.transcript
        .filter((t: unknown) =>
          t && typeof t === "object" &&
          typeof (t as Turn).speaker === "string" &&
          typeof (t as Turn).text === "string"
        )
        .slice(0, 60);
    }
    if (typeof body.native_language === "string" && body.native_language in LANG_NAMES) {
      language = body.native_language;
    }
    if (typeof body.level === "string") level = body.level;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const userLines = transcript
    .filter((t) => t.speaker === "user" && t.text.trim().length > 0)
    .map((t) => t.text.trim());

  if (userLines.length === 0) {
    return json({ issues: [] });
  }

  const langName = LANG_NAMES[language];
  const numbered = userLines.map((l, i) => `${i + 1}. ${l}`).join("\n");

  const systemPrompt = `You are an English teacher reviewing a learner's side of a phone conversation. Respond with valid JSON only.`;

  const userPrompt = `The learner's CEFR level is ${level}.
Find up to 5 of the learner's sentences that were awkward, unnatural, or grammatically incorrect.
Skip sentences that are already fine or too short to evaluate.
For each issue, provide:
- "original": the exact original sentence
- "improved": a natural, native-sounding version appropriate to a ${level} learner
- "explanation": a concise explanation in ${langName} (under 40 words)

If all sentences are fine or there are too few turns to evaluate, return an empty array.

Return JSON in this exact shape:
{ "issues": [ { "original": "...", "improved": "...", "explanation": "..." } ] }

Learner's sentences:
${numbered}`;

  try {
    const content = await reviewWithGemini(geminiKey, systemPrompt, userPrompt);

    try {
      const parsed = JSON.parse(content);
      const issues = Array.isArray(parsed.issues) ? parsed.issues : [];
      const clean = issues
        .filter((x: unknown) =>
          x && typeof x === "object" &&
          typeof (x as Record<string, unknown>).original === "string" &&
          typeof (x as Record<string, unknown>).improved === "string" &&
          typeof (x as Record<string, unknown>).explanation === "string"
        )
        .slice(0, 5);
      return json({ issues: clean });
    } catch {
      console.error("Failed to parse review JSON:", content.slice(0, 300));
      return json({ issues: [] });
    }
  } catch (err) {
    console.error("Review failed:", err);
    return json({ error: String(err) }, 502);
  }
});

async function reviewWithGemini(apiKey: string | undefined, systemPrompt: string, userPrompt: string): Promise<string> {
  if (!apiKey) throw new Error("GEMINI_API_KEY missing");
  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=${apiKey}`;
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: systemPrompt }] },
      contents: [{ role: "user", parts: [{ text: userPrompt }] }],
      generationConfig: {
        temperature: 0.4,
        maxOutputTokens: 1500,
        responseMimeType: "application/json",
      },
    }),
  });
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`gemini_${response.status}: ${detail.slice(0, 200)}`);
  }
  const data = await response.json();
  return data.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}";
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
