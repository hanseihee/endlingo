import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// 영어로 저장된 daily_lessons_v2 레슨을 타겟 언어로 번역하여
// translations JSONB 맵에 머지하는 Edge Function.

interface EnglishScenario {
  order: number;
  title_en: string;
  sentence_en: string;
  grammar: Array<{ pattern: string; example: string }>;
}

interface EnglishLessonRow {
  id: string;
  level: string;
  environment: string;
  theme_en: string;
  scenarios: EnglishScenario[];
  translations: Record<string, unknown>;
}

interface ScenarioTranslation {
  order: number;
  title: string;
  context: string;
  sentence: string;
  grammar_explanations: string[];
}

interface LessonTranslation {
  theme: string;
  scenarios: ScenarioTranslation[];
}

// 언어별 번역 지침. 새 언어는 여기에 한 블록만 추가하면 됨.
const LANGUAGE_RULES: Record<
  string,
  {
    nativeName: string;
    systemInstruction: string;
    toneRule: string;
    themeFormat: string;
  }
> = {
  ko: {
    nativeName: "Korean",
    systemInstruction:
      "You are a professional Korean translator specializing in natural, idiomatic Korean. Output JSON only, entirely in Korean (except preserved grammar patterns which stay in English).",
    toneRule:
      "- Use 존댓말 (해요체) consistently.\n- Prefer idiomatic Korean over literal translation.\n- Use natural Korean word order and particles.\n- Avoid translation-ese (번역투).",
    themeFormat: '"오늘의 ○○ 영어"',
  },
  ja: {
    nativeName: "Japanese",
    systemInstruction:
      "You are a professional Japanese translator specializing in natural, idiomatic Japanese. Output JSON only, entirely in Japanese (except preserved grammar patterns which stay in English).",
    toneRule:
      "- Use 丁寧語 (です・ます調) consistently.\n- Prefer idiomatic Japanese over literal translation.\n- Use natural Japanese particles and word order.\n- Avoid translation-ese (翻訳調).",
    themeFormat: '"今日の○○英語"',
  },
};

function buildTranslationPrompt(
  lesson: EnglishLessonRow,
  targetLang: string,
): string {
  const rule = LANGUAGE_RULES[targetLang];
  if (!rule) throw new Error(`Unsupported language: ${targetLang}`);

  const englishPayload = {
    theme_en: lesson.theme_en,
    environment: lesson.environment,
    level: lesson.level,
    scenarios: lesson.scenarios,
  };

  return `Translate the following English lesson into ${rule.nativeName}.
Output ONLY a JSON object matching the output schema. No extra commentary.

Translation rules:
${rule.toneRule}
- Preserve scenario "order" exactly as given.
- "grammar_explanations" is an ARRAY aligned 1:1 with the input scenarios[i].grammar array.
  For each grammar[i], write one concise ${rule.nativeName} explanation of what the pattern means
  and how it is used. Do NOT translate the "pattern" or "example" fields themselves.
- "context" is one short ${rule.nativeName} sentence describing the situation.
- "sentence" is the ${rule.nativeName} translation of sentence_en (meaning-focused, not literal).
- "title" is the ${rule.nativeName} title corresponding to title_en.
- "theme" format hint: ${rule.themeFormat}

Input (English lesson):
${JSON.stringify(englishPayload, null, 2)}

Output schema (JSON only):
{
  "theme": "...",
  "scenarios": [
    {
      "order": 1,
      "title": "...",
      "context": "...",
      "sentence": "...",
      "grammar_explanations": ["explanation for grammar[0]", "explanation for grammar[1]"]
    }
  ]
}`;
}

async function translateLesson(
  apiKey: string,
  lesson: EnglishLessonRow,
  targetLang: string,
): Promise<LessonTranslation | null> {
  const rule = LANGUAGE_RULES[targetLang];
  if (!rule) return null;

  const prompt = buildTranslationPrompt(lesson, targetLang);

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: "gpt-5-mini",
      max_completion_tokens: 8192,
      reasoning_effort: "low",
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: rule.systemInstruction },
        { role: "user", content: prompt },
      ],
    }),
  });

  if (!response.ok) {
    const err = await response.text();
    console.error(`OpenAI API error for ${lesson.level}/${lesson.environment}/${targetLang}: ${err}`);
    return null;
  }

  const result = await response.json();
  const text = result.choices?.[0]?.message?.content;
  if (!text) {
    console.error(`No content for ${lesson.level}/${lesson.environment}/${targetLang}`);
    return null;
  }

  try {
    const parsed = JSON.parse(text) as LessonTranslation;
    // 구조 검증
    if (
      typeof parsed.theme !== "string" ||
      !Array.isArray(parsed.scenarios) ||
      parsed.scenarios.length !== lesson.scenarios.length
    ) {
      console.error(
        `Schema mismatch for ${lesson.level}/${lesson.environment}/${targetLang}: expected ${lesson.scenarios.length} scenarios`,
      );
      return null;
    }
    return parsed;
  } catch {
    console.error(
      `Failed to parse JSON for ${lesson.level}/${lesson.environment}/${targetLang}: ${text.slice(0, 200)}`,
    );
    return null;
  }
}

Deno.serve(async (req) => {
  try {
    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) {
      return new Response(JSON.stringify({ error: "OPENAI_API_KEY not set" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Seoul" });

    let targetLanguage = "ko";
    let targetDate: string | null = null;
    let targetLevel: string | null = null;
    let forceRetranslate = false;
    try {
      const body = await req.json();
      targetLanguage = body.language || "ko";
      targetDate = body.date || null;
      targetLevel = body.level || null;
      forceRetranslate = body.forceRetranslate === true;
    } catch {
      // 본문 없으면 기본값
    }

    if (!LANGUAGE_RULES[targetLanguage]) {
      return new Response(
        JSON.stringify({
          error: `Unsupported language: ${targetLanguage}`,
          supported: Object.keys(LANGUAGE_RULES),
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const dateToUse = targetDate || today;

    // 번역 대상 쿼리: 해당 날짜의 레슨 중 타겟 언어 번역이 없는 행만 (forceRetranslate 시 전체)
    let query = supabase
      .from("daily_lessons_v2")
      .select("id, level, environment, theme_en, scenarios, translations")
      .eq("date", dateToUse);

    if (targetLevel) {
      query = query.eq("level", targetLevel);
    }

    const { data: lessons, error: fetchError } = await query;

    if (fetchError) {
      console.error(`Fetch error: ${fetchError.message}`);
      return new Response(JSON.stringify({ error: fetchError.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (!lessons || lessons.length === 0) {
      return new Response(
        JSON.stringify({
          phase: "translate",
          date: dateToUse,
          language: targetLanguage,
          message: "No English lessons found for this date. Run generate-english-lessons first.",
          translated: 0,
        }),
        { headers: { "Content-Type": "application/json" } },
      );
    }

    // forceRetranslate 아니면 이미 번역된 행 스킵
    const targets = lessons.filter((l) => {
      if (forceRetranslate) return true;
      return !(l.translations && targetLanguage in l.translations);
    });

    let translated = 0;
    let skipped = lessons.length - targets.length;
    let failed = 0;

    // 동시성 제한: 한 번에 5개씩 처리 (rate limit 배려)
    const CONCURRENCY = 5;
    for (let i = 0; i < targets.length; i += CONCURRENCY) {
      const batch = targets.slice(i, i + CONCURRENCY);
      const results = await Promise.all(
        batch.map(async (lesson) => {
          const translation = await translateLesson(openaiKey, lesson as EnglishLessonRow, targetLanguage);
          if (!translation) {
            return { ok: false, lesson };
          }

          // 서버 측 JSONB concat으로 원자적 머지 (병렬 호출 race condition 방지)
          const { error } = await supabase.rpc("merge_lesson_translation", {
            p_id: lesson.id,
            p_lang: targetLanguage,
            p_payload: translation,
          });

          if (error) {
            console.error(`Update error for ${lesson.level}/${lesson.environment}/${targetLanguage}: ${error.message}`);
            return { ok: false, lesson };
          }

          console.log(`Translated ${targetLanguage}: ${lesson.level}/${lesson.environment}`);
          return { ok: true, lesson };
        }),
      );

      for (const r of results) {
        if (r.ok) translated++;
        else failed++;
      }
    }

    return new Response(
      JSON.stringify({
        phase: "translate",
        date: dateToUse,
        language: targetLanguage,
        translated,
        skipped,
        failed,
        total: lessons.length,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("Unexpected error:", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
