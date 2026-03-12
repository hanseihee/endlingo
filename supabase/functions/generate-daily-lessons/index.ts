import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"];
const ENVIRONMENTS = ["school", "work", "travel", "daily", "business"];

const LEVEL_GUIDE: Record<string, string> = {
  A1: `입문 레벨. 시나리오당 2문장. 기본 1000단어 이내. 현재시제, be동사, 단순 의문문만 사용. 아주 짧고 쉬운 문장.`,
  A2: `초급 레벨. 시나리오당 2~3문장. 일상 어휘. 과거시제, can/will, 간단한 접속사(and, but) 사용.`,
  B1: `중급 레벨. 시나리오당 3문장. 현재완료, if절, 관계대명사(who, which, that) 사용. 자연스러운 일상 영어.`,
  B2: `중고급 레벨. 시나리오당 3~4문장. 가정법, 분사구문, 복문 사용. 다양한 표현과 어휘.`,
  C1: `고급 레벨. 시나리오당 4문장. 도치, 강조구문, 관용표현 사용. 비즈니스/학술 뉘앙스 포함.`,
  C2: `최상급 레벨. 시나리오당 4~5문장. 원어민 수준 관용어, 문화적 맥락, 미묘한 뉘앙스 차이 설명 포함.`,
};

const ENV_THEMES: Record<string, string> = {
  school: "학교: 수업 질문, 과제 제출, 스터디 그룹, 도서관, 교수님 면담, 캠퍼스 생활",
  work: "직장: 업무 보고, 미팅 조율, 문제 보고, 이메일, 동료와 대화, 점심 약속",
  travel: "여행: 공항 체크인, 호텔 체크인/아웃, 길 묻기, 레스토랑 주문, 쇼핑, 관광지",
  daily: "일상: 카페 주문, 택배 수령, 이웃 대화, 전화 통화, 약속 잡기, 병원/은행",
  business: "비즈니스: 프레젠테이션, 협상, 계약 논의, 보고서 작성, 클라이언트 응대, 컨퍼런스",
};

function buildPrompt(level: string, environment: string, date: string): string {
  return `당신은 한국인을 위한 영어 교육 전문가입니다.
아래 조건에 맞는 영어 학습 콘텐츠를 JSON으로 생성하세요.

조건:
- 레벨: ${level} (${LEVEL_GUIDE[level]})
- 환경: ${ENV_THEMES[environment]}
- 날짜: ${date}
- 시나리오 수: 정확히 3개

요구사항:
1. 테마는 해당 환경에서 실제로 마주치는 상황이어야 합니다
2. 3개의 시나리오는 서로 다른 상황이되 하나의 테마로 자연스럽게 연결되어야 합니다
3. 영어 문장은 ${level} 수준의 문법을 자연스럽게 포함해야 합니다
4. 문법 포인트는 시나리오당 2~3개:
   - pattern: 영어 문법 패턴이나 구동사를 영어로 표기 (예: "Work on + noun", "Look forward to + -ing", "Have been + -ing")
   - explanation: 한국어로 쉽고 친절하게 해당 패턴의 의미와 사용법 설명
   - example: 해당 패턴을 사용한 짧은 영어 예문 1개 (시나리오 문장과 다른 예문)
5. 구동사(phrasal verb)가 문장에 사용되었다면 반드시 문법 포인트에 포함하세요
6. 번역은 자연스러운 한국어로 해주세요
7. context는 한국어로 이 상황이 어떤 상황인지 한 줄로 설명

반드시 아래 JSON 형식만 출력하세요. 다른 텍스트 없이 JSON만 출력:
{
  "theme_ko": "오늘의 ○○ 영어",
  "theme_en": "Daily ○○ English",
  "scenarios": [
    {
      "order": 1,
      "title_ko": "시나리오 제목 (한국어)",
      "title_en": "Scenario Title (English)",
      "context": "이 상황에 대한 한국어 설명",
      "sentence_en": "English sentences here.",
      "sentence_ko": "한국어 번역",
      "grammar": [
        { "pattern": "Work on + noun", "explanation": "~에 대해 작업하다. 특정 과제나 프로젝트에 집중할 때 사용합니다.", "example": "She is working on her homework." }
      ]
    },
    {
      "order": 2,
      "title_ko": "...",
      "title_en": "...",
      "context": "...",
      "sentence_en": "...",
      "sentence_ko": "...",
      "grammar": [{ "pattern": "...", "explanation": "...", "example": "..." }]
    },
    {
      "order": 3,
      "title_ko": "...",
      "title_en": "...",
      "context": "...",
      "sentence_en": "...",
      "sentence_ko": "...",
      "grammar": [{ "pattern": "...", "explanation": "...", "example": "..." }]
    }
  ]
}`;
}

async function generateLesson(
  apiKey: string,
  level: string,
  environment: string,
  date: string,
): Promise<Record<string, unknown> | null> {
  const prompt = buildPrompt(level, environment, date);

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      max_tokens: 2048,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: "You are a JSON-only response bot. Always respond with valid JSON." },
        { role: "user", content: prompt },
      ],
    }),
  });

  if (!response.ok) {
    const err = await response.text();
    console.error(`OpenAI API error for ${level}/${environment}: ${err}`);
    return null;
  }

  const result = await response.json();
  const text = result.choices?.[0]?.message?.content;
  if (!text) {
    console.error(`No content in response for ${level}/${environment}`);
    return null;
  }

  try {
    return JSON.parse(text);
  } catch {
    console.error(`Failed to parse JSON for ${level}/${environment}: ${text.slice(0, 200)}`);
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

    // KST 기준 오늘 날짜
    const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Seoul" });

    // 요청 body에서 특정 레벨 지정 가능 (없으면 전체)
    let targetLevel: string | null = null;
    try {
      const body = await req.json();
      targetLevel = body.level || null;
    } catch {
      // body 없으면 전체 레벨
    }

    const levelsToGenerate = targetLevel ? [targetLevel] : LEVELS;

    // 이미 생성된 레슨 확인
    const { data: existing } = await supabase
      .from("daily_lessons")
      .select("level, environment")
      .eq("date", today);

    const existingSet = new Set(
      (existing || []).map((e: { level: string; environment: string }) => `${e.level}_${e.environment}`),
    );

    let generated = 0;
    let skipped = 0;
    let failed = 0;

    for (const level of levelsToGenerate) {
      // 같은 레벨의 5개 환경을 동시 생성 (병렬)
      const promises = ENVIRONMENTS.map(async (env) => {
        const key = `${level}_${env}`;
        if (existingSet.has(key)) {
          skipped++;
          return;
        }

        const lesson = await generateLesson(openaiKey, level, env, today);
        if (!lesson) {
          failed++;
          return;
        }

        const { error } = await supabase.from("daily_lessons").insert({
          date: today,
          level: level,
          environment: env,
          theme_ko: lesson.theme_ko,
          theme_en: lesson.theme_en,
          scenarios: lesson.scenarios,
        });

        if (error) {
          console.error(`Insert error for ${key}: ${error.message}`);
          failed++;
        } else {
          generated++;
          console.log(`Generated: ${key}`);
        }
      });

      await Promise.all(promises);
    }

    return new Response(
      JSON.stringify({
        date: today,
        generated,
        skipped,
        failed,
        total: levelsToGenerate.length * ENVIRONMENTS.length,
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
