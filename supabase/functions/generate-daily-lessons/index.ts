import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"];
const ENVIRONMENTS = ["school", "work", "travel", "daily", "business"];

const LEVEL_GUIDE: Record<string, Record<string, string>> = {
  ko: {
    A1: `입문 레벨. 시나리오당 2문장. 기본 1000단어 이내. 현재시제, be동사, 단순 의문문만 사용. 아주 짧고 쉬운 문장.`,
    A2: `초급 레벨. 시나리오당 2~3문장. 일상 어휘. 과거시제, can/will, 간단한 접속사(and, but) 사용.`,
    B1: `중급 레벨. 시나리오당 3문장. 현재완료, if절, 관계대명사(who, which, that) 사용. 자연스러운 일상 영어.`,
    B2: `중고급 레벨. 시나리오당 3~4문장. 가정법, 분사구문, 복문 사용. 다양한 표현과 어휘.`,
    C1: `고급 레벨. 시나리오당 4문장. 도치, 강조구문, 관용표현 사용. 비즈니스/학술 뉘앙스 포함.`,
    C2: `최상급 레벨. 시나리오당 4~5문장. 원어민 수준 관용어, 문화적 맥락, 미묘한 뉘앙스 차이 설명 포함.`,
  },
  ja: {
    A1: `入門レベル。シナリオごとに2文。基本1000語以内。現在時制、be動詞、単純な疑問文のみ使用。非常に短くて簡単な文。`,
    A2: `初級レベル。シナリオごとに2〜3文。日常語彙。過去時制、can/will、簡単な接続詞(and, but)使用。`,
    B1: `中級レベル。シナリオごとに3文。現在完了、if節、関係代名詞(who, which, that)使用。自然な日常英語。`,
    B2: `中上級レベル。シナリオごとに3〜4文。仮定法、分詞構文、複文使用。多様な表現と語彙。`,
    C1: `上級レベル。シナリオごとに4文。倒置、強調構文、慣用表現使用。ビジネス/学術的ニュアンス含む。`,
    C2: `最上級レベル。シナリオごとに4〜5文。ネイティブレベルの慣用句、文化的背景、微妙なニュアンスの違いの説明含む。`,
  },
};

const ENV_TOPICS: Record<string, string[]> = {
  school: [
    "수업 중 질문하기, 교수님께 이메일 쓰기",
    "과제 마감 연장 요청, 팀 프로젝트 역할 분담",
    "스터디 그룹 모집, 시험 범위 확인",
    "도서관에서 자료 찾기, 참고문헌 질문",
    "수강 신청, 수업 변경 상담",
    "학교 동아리 가입, 행사 참여",
    "기숙사 생활, 룸메이트와 규칙 정하기",
    "졸업 요건 확인, 진로 상담",
    "실험실/연구실에서의 대화, 실습 보고서",
    "교환학생 지원, 유학 준비",
    "학교 식당에서 주문, 친구와 점심",
    "발표 준비, 피드백 받기",
    "시험 끝난 후 친구들과 계획 짜기",
    "교내 아르바이트, 조교 업무",
    "학교 행정실에서 서류 발급",
    "온라인 수업 접속 문제, 줌 에티켓",
    "학점 이의 신청, 성적표 확인",
    "논문 주제 선정, 지도교수 상담",
    "학교 체육관 이용, 운동 동아리",
    "캠퍼스 투어, 신입생에게 학교 소개",
    "학과 MT 계획, 장소와 활동 정하기",
    "복수전공/부전공 신청 상담",
    "학교 보건실 방문, 건강 상담",
    "학생회 선거, 공약 토론",
    "교내 카페에서 공부, 자리 맡기",
    "학교 셔틀버스 시간 확인, 통학 이야기",
    "장학금 신청, 추천서 부탁",
    "학교 축제 준비, 부스 운영",
    "해외 대학 지원, 자기소개서 작성",
    "수업 중 토론, 찬반 의견 나누기",
  ],
  work: [
    "업무 진행 상황 보고, 주간 미팅",
    "새 프로젝트 브레인스토밍, 아이디어 제안",
    "동료에게 도움 요청, 협업 조율",
    "상사에게 휴가 요청, 일정 조정",
    "신입사원 온보딩, 업무 인수인계",
    "업무 실수 보고, 해결 방안 논의",
    "점심 메뉴 정하기, 회식 계획",
    "재택근무 관련 소통, 화상회의 매너",
    "연봉 협상, 성과 면담",
    "퇴근 후 동료와 가벼운 대화",
    "사무용품 주문, 시설 문의",
    "고객 불만 처리, 서비스 개선 논의",
    "부서 이동, 새 팀 적응",
    "마감 기한 조정, 우선순위 정하기",
    "회의실 예약, 일정 충돌 해결",
    "출장 보고서 작성, 경비 정산",
    "팀 빌딩 활동, 워크숍 기획",
    "사내 메신저로 업무 요청, 톤 맞추기",
    "프리랜서/외주 업체와 소통",
    "사내 커피머신 고장, 시설팀에 연락",
    "새로운 소프트웨어 도입, 사용법 교육",
    "야근 상황 공유, 업무 분담 요청",
    "동료의 승진 축하, 선물 고르기",
    "월요일 아침 회의, 주간 목표 설정",
    "금요일 오후, 한 주 마무리 대화",
    "회사 복지 제도 문의, HR 상담",
    "사내 동호회 활동, 가입 안내",
    "업무 자동화 제안, 효율 개선",
    "고객 미팅 준비, 자료 검토",
    "회사 이벤트 기획, 역할 분담",
  ],
  travel: [
    "공항 체크인, 보안 검색대 통과",
    "호텔 체크인/아웃, 객실 문제 해결",
    "현지 맛집에서 주문, 음식 추천 받기",
    "길을 잃었을 때 도움 요청, 지도 보기",
    "관광지 입장권 구매, 가이드 투어",
    "렌터카 빌리기, 주유소에서 대화",
    "기차/버스표 구매, 환승 방법 묻기",
    "쇼핑몰에서 할인 문의, 환불/교환",
    "현지인과 문화 이야기, 추천 장소 묻기",
    "숙소 예약 변경, 취소 요청",
    "여행 중 아플 때 약국/병원 방문",
    "공항 면세점 쇼핑, 면세 한도 확인",
    "해외에서 은행/환전소 이용",
    "에어비앤비 호스트와 소통, 체크인 방법",
    "여행 사진 찍어달라고 부탁, 현지 축제 참여",
    "짐 분실 신고, 항공사 클레임",
    "크루즈/페리 탑승, 선상 활동",
    "트레킹/하이킹 가이드와 대화",
    "해변에서 장비 대여, 액티비티 예약",
    "귀국 전 기념품 쇼핑, 포장 요청",
    "비행기 안에서 승무원과 대화, 기내식 선택",
    "공항 라운지 이용, 와이파이 연결",
    "택시/우버 호출, 목적지 설명",
    "호스텔 체크인, 다른 여행자와 인사",
    "여행 보험 관련 문의, 사고 접수",
    "현지 시장/야시장 구경, 흥정하기",
    "박물관/미술관 관람, 오디오 가이드 대여",
    "스쿠버다이빙/스노클링 안전 교육",
    "캠핑장 예약, 장비 대여",
    "와이너리/양조장 투어, 시음",
  ],
  daily: [
    "카페에서 음료 주문, 커스텀 요청",
    "택배 수령, 배송 문제 문의",
    "이웃과 인사, 소음 문제 이야기",
    "전화로 예약하기, 일정 변경",
    "병원 접수, 증상 설명",
    "은행에서 계좌 개설, 송금 문의",
    "마트에서 장보기, 계산대 대화",
    "미용실 예약, 스타일 설명",
    "운동/헬스장 등록, 트레이너와 대화",
    "반려동물 병원 방문, 증상 설명",
    "집 수리 요청, 관리사무소 연락",
    "중고 물품 거래, 가격 흥정",
    "세탁소 이용, 옷 수선 요청",
    "우체국에서 소포 보내기",
    "자동차 정비소, 고장 설명",
    "약국에서 약 구매, 복용법 확인",
    "음식 배달 주문, 리뷰 남기기",
    "도서관 이용, 도서 대출/반납",
    "친구와 영화/공연 계획",
    "새 집으로 이사, 인터넷 설치",
    "주말 브런치, 친구와 레스토랑 방문",
    "헬스장에서 요가/필라테스 수업 등록",
    "동네 빵집에서 빵 고르기, 추천 받기",
    "주민센터 방문, 서류 발급",
    "자전거 타이어 수리, 자전거 가게",
    "네일샵 예약, 디자인 고르기",
    "집에서 요리, 레시피 공유",
    "주말 등산, 산행 코스 추천",
    "아이 학교 상담, 선생님과 대화",
    "동네 산책, 강아지 산책 중 이웃 만남",
  ],
  business: [
    "프레젠테이션 발표, 질의응답 대응",
    "해외 거래처와 화상회의, 시차 조율",
    "계약 조건 협상, 수정 요청",
    "분기 실적 보고, 매출 분석",
    "신규 사업 제안, 투자 유치 피칭",
    "비즈니스 네트워킹, 명함 교환",
    "출장 일정 잡기, 경비 정산",
    "컨퍼런스 참석, 발표자 소개",
    "해외 파트너와 만찬, 비즈니스 매너",
    "프로젝트 킥오프 미팅, 목표 설정",
    "위기 관리, 고객사 클레임 대응",
    "인사 평가, 팀원 피드백 전달",
    "사내 교육/워크숍 진행",
    "공급업체 선정, 견적 비교",
    "합작 투자 논의, MOU 체결",
    "연간 사업 계획 수립, 예산 배정",
    "시장 조사 결과 발표, 경쟁사 분석",
    "브랜드 리뉴얼 논의, 마케팅 전략",
    "해외 전시회 참가, 부스 운영",
    "법률 검토, 계약서 수정 논의",
    "M&A 실사, 기업 가치 평가",
    "이사회 보고, 주요 안건 논의",
    "채용 면접 진행, 후보자 평가",
    "고객사 방문, 제품 데모",
    "비즈니스 이메일 작성, 격식 있는 표현",
    "해외 법인 설립, 현지 규정 확인",
    "지식재산권 보호, 특허 출원 논의",
    "사업 파트너십 제안, 윈윈 전략",
    "공장/생산시설 견학, 품질 관리",
    "유통 채널 확대, 판매 전략",
  ],
};

const PROMPT_CONFIG: Record<string, { role: string; nativeLang: string; translationRules: string; themeFormat: string }> = {
  ko: {
    role: "당신은 한국인을 위한 영어 교육 전문가입니다.",
    nativeLang: "한국어",
    translationRules: `6. sentence_ko 번역 규칙:
   - 직역이 아닌 의역으로 자연스러운 한국어 문장을 작성하세요
   - 한국어 어순과 조사를 자연스럽게 사용하세요
   - 존댓말(해요체)로 통일하세요
   - 관용적 한국어 표현을 적극 사용하세요
   - 번역투 표현을 피하세요`,
    themeFormat: `"오늘의 ○○ 영어"`,
  },
  ja: {
    role: "あなたは日本人のための英語教育の専門家です。",
    nativeLang: "日本語",
    translationRules: `6. sentence_ko（日本語訳）の翻訳ルール:
   - 直訳ではなく意訳で自然な日本語の文を作成してください
   - 日本語の語順と助詞を自然に使ってください
   - 丁寧語（です・ます調）で統一してください
   - 慣用的な日本語表現を積極的に使ってください
   - 翻訳調の表現を避けてください`,
    themeFormat: `"今日の○○英語"`,
  },
};

function pickDailyTopic(environment: string, date: string): string {
  const topics = ENV_TOPICS[environment];
  const dateNum = parseInt(date.replace(/-/g, ""), 10);
  const index = (dateNum + environment.length) % topics.length;
  return topics[index];
}

function buildPrompt(level: string, environment: string, date: string, language: string): string {
  const todayTopic = pickDailyTopic(environment, date);
  const cfg = PROMPT_CONFIG[language] || PROMPT_CONFIG["ko"];
  const levelGuide = LEVEL_GUIDE[language]?.[level] || LEVEL_GUIDE["ko"][level];

  return `${cfg.role}
아래 조건에 맞는 영어 학습 콘텐츠를 JSON으로 생성하세요.

조건:
- 레벨: ${level} (${levelGuide})
- 오늘의 주제: ${todayTopic}
- 날짜: ${date}
- 시나리오 수: 정확히 3개

요구사항:
1. 테마는 해당 환경에서 실제로 마주치는 상황이어야 합니다
2. 3개의 시나리오는 서로 다른 상황이되 하나의 테마로 자연스럽게 연결되어야 합니다
3. 영어 문장은 ${level} 수준의 문법을 자연스럽게 포함해야 합니다
4. 문법 포인트는 시나리오당 2~3개:
   - pattern: 영어 문법 패턴이나 구동사를 영어로 표기 (예: "Work on + noun", "Look forward to + -ing")
   - explanation: ${cfg.nativeLang}로 쉽고 친절하게 해당 패턴의 의미와 사용법 설명
   - example: 해당 패턴을 사용한 짧은 영어 예문 1개
5. 구동사(phrasal verb)가 문장에 사용되었다면 반드시 문법 포인트에 포함하세요
${cfg.translationRules}
7. context는 ${cfg.nativeLang}로 이 상황이 어떤 상황인지 한 줄로 설명

반드시 아래 JSON 형식만 출력하세요. 다른 텍스트 없이 JSON만 출력:
{
  "theme_ko": ${cfg.themeFormat},
  "theme_en": "Daily ○○ English",
  "scenarios": [
    {
      "order": 1,
      "title_ko": "시나리오 제목 (${cfg.nativeLang})",
      "title_en": "Scenario Title (English)",
      "context": "${cfg.nativeLang} 상황 설명",
      "sentence_en": "English sentences here.",
      "sentence_ko": "${cfg.nativeLang} 번역",
      "grammar": [
        { "pattern": "Work on + noun", "explanation": "${cfg.nativeLang} 설명", "example": "She is working on her homework." }
      ]
    },
    { "order": 2, "title_ko": "...", "title_en": "...", "context": "...", "sentence_en": "...", "sentence_ko": "...", "grammar": [{"pattern":"...","explanation":"...","example":"..."}] },
    { "order": 3, "title_ko": "...", "title_en": "...", "context": "...", "sentence_en": "...", "sentence_ko": "...", "grammar": [{"pattern":"...","explanation":"...","example":"..."}] }
  ]
}`;
}

async function generateLesson(
  apiKey: string,
  level: string,
  environment: string,
  date: string,
  language: string,
): Promise<Record<string, unknown> | null> {
  const prompt = buildPrompt(level, environment, date, language);
  const cfg = PROMPT_CONFIG[language] || PROMPT_CONFIG["ko"];

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: "gpt-5.4-nano",
      max_completion_tokens: 2048,
      temperature: 0.7,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: `You are a JSON-only response bot. Always respond with valid JSON. All non-English text (explanations, translations, titles, context) MUST be written in ${cfg.nativeLang}. Never mix other languages.` },
        { role: "user", content: prompt },
      ],
    }),
  });

  if (!response.ok) {
    const err = await response.text();
    console.error(`OpenAI API error for ${level}/${environment}/${language}: ${err}`);
    return null;
  }

  const result = await response.json();
  const text = result.choices?.[0]?.message?.content;
  if (!text) {
    console.error(`No content in response for ${level}/${environment}/${language}`);
    return null;
  }

  try {
    return JSON.parse(text);
  } catch {
    console.error(`Failed to parse JSON for ${level}/${environment}/${language}: ${text.slice(0, 200)}`);
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

    let targetLevel: string | null = null;
    let targetDate: string | null = null;
    let targetLanguage: string = "ko";
    let forceRegenerate = false;
    try {
      const body = await req.json();
      targetLevel = body.level || null;
      targetDate = body.date || null;
      targetLanguage = body.language || "ko";
      forceRegenerate = body.forceRegenerate === true;
    } catch {
      // body 없으면 기본값
    }

    const dateToUse = targetDate || today;
    const levelsToGenerate = targetLevel ? [targetLevel] : LEVELS;

    // 강제 재생성: 기존 데이터 삭제
    if (forceRegenerate) {
      let deleteQuery = supabase
        .from("daily_lessons")
        .delete()
        .eq("date", dateToUse)
        .eq("language", targetLanguage);
      if (targetLevel) {
        deleteQuery = deleteQuery.eq("level", targetLevel);
      }
      const { error: delErr } = await deleteQuery;
      if (delErr) {
        console.error(`Delete error: ${delErr.message}`);
      } else {
        console.log(`Deleted existing lessons for ${dateToUse}/${targetLanguage}${targetLevel ? `/${targetLevel}` : ""}`);
      }
    }

    // 이미 생성된 레슨 확인 (언어 포함)
    const { data: existing } = await supabase
      .from("daily_lessons")
      .select("level, environment, language")
      .eq("date", dateToUse)
      .eq("language", targetLanguage);

    const existingSet = new Set(
      (existing || []).map((e: { level: string; environment: string }) => `${e.level}_${e.environment}`),
    );

    let generated = 0;
    let skipped = 0;
    let failed = 0;

    for (const level of levelsToGenerate) {
      const promises = ENVIRONMENTS.map(async (env) => {
        const key = `${level}_${env}`;
        if (existingSet.has(key)) {
          skipped++;
          return;
        }

        const lesson = await generateLesson(openaiKey, level, env, dateToUse, targetLanguage);
        if (!lesson) {
          failed++;
          return;
        }

        const { error } = await supabase.from("daily_lessons").insert({
          date: dateToUse,
          level: level,
          environment: env,
          language: targetLanguage,
          theme_ko: lesson.theme_ko,
          theme_en: lesson.theme_en,
          scenarios: lesson.scenarios,
        });

        if (error) {
          console.error(`Insert error for ${key}/${targetLanguage}: ${error.message}`);
          failed++;
        } else {
          generated++;
          console.log(`Generated: ${key}/${targetLanguage}`);
        }
      });

      await Promise.all(promises);
    }

    return new Response(
      JSON.stringify({
        date: dateToUse,
        language: targetLanguage,
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
