import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// 영어 콘텐츠만 생성하는 Edge Function.
// 번역은 translate-lessons 함수에서 별도 처리.

const LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"];
const ENVIRONMENTS = ["school", "work", "travel", "daily", "business"];

const LEVEL_GUIDE: Record<string, string> = {
  A1: "Beginner. Exactly 2 short sentences per scenario. Use only basic 1000 words, present tense, be-verbs, and simple questions.",
  A2: "Elementary. 2~3 sentences per scenario. Everyday vocabulary. Past tense, can/will, simple conjunctions (and, but).",
  B1: "Intermediate. 3 sentences per scenario. Present perfect, if-clauses, relative pronouns (who, which, that). Natural everyday English.",
  B2: "Upper-intermediate. 3~4 sentences per scenario. Subjunctive, participial phrases, complex sentences. Varied expressions.",
  C1: "Advanced. 4 sentences per scenario. Inversion, emphatic structures, idiomatic expressions. Business/academic nuance.",
  C2: "Proficient. 4~5 sentences per scenario. Native-level idioms, cultural context, subtle nuance differences.",
};

// 주제 목록은 한국어로 유지 (의미 전달만 하면 되고, 프롬프트에서는 "Topic hint" 로 전달)
const ENV_TOPICS: Record<string, string[]> = {
  school: [
    "Asking questions in class, emailing a professor",
    "Requesting an assignment deadline extension, dividing team project roles",
    "Recruiting a study group, confirming exam scope",
    "Finding materials at the library, asking about references",
    "Course registration, consulting on schedule changes",
    "Joining a campus club, participating in events",
    "Dorm life, setting rules with a roommate",
    "Checking graduation requirements, career counseling",
    "Conversations in the lab, practicum reports",
    "Applying for exchange student programs, study abroad prep",
    "Ordering at the school cafeteria, lunch with friends",
    "Preparing a presentation, receiving feedback",
    "Making plans with friends after finals",
    "On-campus part-time jobs, TA duties",
    "Getting documents from the administrative office",
    "Online class connection issues, Zoom etiquette",
    "Grade appeals, checking transcripts",
    "Choosing a thesis topic, advisor consultation",
    "Using the campus gym, joining a sports club",
    "Campus tours, introducing the school to freshmen",
    "Planning a department MT, deciding location and activities",
    "Double major / minor application counseling",
    "Visiting the school health center, consulting about symptoms",
    "Student council elections, debating pledges",
    "Studying at the campus cafe, saving a seat",
    "Checking shuttle bus times, commuting talk",
    "Applying for scholarships, asking for recommendation letters",
    "Preparing for the school festival, running a booth",
    "Applying to overseas universities, writing a personal statement",
    "In-class debate, sharing pros and cons",
  ],
  work: [
    "Reporting progress, weekly meetings",
    "Brainstorming a new project, suggesting ideas",
    "Asking a colleague for help, coordinating collaboration",
    "Requesting time off from a manager, adjusting schedules",
    "Onboarding new employees, handing over work",
    "Reporting a work mistake, discussing solutions",
    "Deciding lunch menu, planning a team dinner",
    "Remote work communication, video call etiquette",
    "Salary negotiation, performance review",
    "Casual chat with coworkers after work",
    "Ordering office supplies, facility inquiries",
    "Handling customer complaints, discussing service improvements",
    "Department transfers, adapting to a new team",
    "Adjusting deadlines, setting priorities",
    "Booking a meeting room, resolving schedule conflicts",
    "Writing a business trip report, settling expenses",
    "Team building activities, planning workshops",
    "Work requests via company messenger, matching tone",
    "Communicating with freelancers / outsourcing vendors",
    "Office coffee machine broken, contacting facilities",
    "Introducing new software, user training",
    "Sharing overtime status, requesting task redistribution",
    "Congratulating a colleague on promotion, choosing a gift",
    "Monday morning meeting, setting weekly goals",
    "Friday afternoon, wrapping up the week",
    "Inquiring about company benefits, HR consultation",
    "In-house club activities, joining guide",
    "Proposing workflow automation, efficiency improvements",
    "Preparing for a client meeting, reviewing materials",
    "Planning company events, assigning roles",
  ],
  travel: [
    "Airport check-in, passing security",
    "Hotel check-in / check-out, resolving room issues",
    "Ordering at a local restaurant, getting food recommendations",
    "Asking for help when lost, reading a map",
    "Buying attraction tickets, guided tours",
    "Renting a car, conversation at a gas station",
    "Buying train/bus tickets, asking for transfer info",
    "Asking about discounts at a mall, refund/exchange",
    "Chatting with locals about culture, asking for recommendations",
    "Changing accommodation reservations, cancellation requests",
    "Visiting pharmacy/hospital when sick while traveling",
    "Duty-free shopping at the airport, checking limits",
    "Using a bank/exchange office abroad",
    "Communicating with an Airbnb host, check-in method",
    "Asking someone to take a travel photo, joining a local festival",
    "Reporting lost luggage, filing airline claims",
    "Boarding a cruise/ferry, onboard activities",
    "Conversation with a trekking/hiking guide",
    "Renting beach equipment, booking activities",
    "Souvenir shopping before going home, packaging requests",
    "Chatting with flight attendants, choosing in-flight meals",
    "Using the airport lounge, connecting to Wi-Fi",
    "Calling a taxi/Uber, explaining the destination",
    "Hostel check-in, greeting fellow travelers",
    "Travel insurance inquiries, accident reports",
    "Exploring local markets, haggling",
    "Visiting museums/galleries, renting an audio guide",
    "Scuba diving / snorkeling safety briefing",
    "Campsite reservations, renting equipment",
    "Winery/brewery tours, tasting",
  ],
  daily: [
    "Ordering a drink at a cafe, custom requests",
    "Receiving packages, delivery issue inquiries",
    "Greeting neighbors, discussing noise issues",
    "Making a reservation by phone, rescheduling",
    "Hospital check-in, describing symptoms",
    "Opening a bank account, transfer inquiries",
    "Grocery shopping at the mart, checkout chat",
    "Booking a hair salon, describing a style",
    "Gym registration, talking with a trainer",
    "Visiting a pet hospital, describing symptoms",
    "Requesting home repairs, contacting management",
    "Second-hand item trades, price haggling",
    "Using a dry cleaner, requesting alterations",
    "Sending parcels at the post office",
    "Auto repair shop, explaining problems",
    "Buying medicine at a pharmacy, checking dosage",
    "Ordering food delivery, leaving reviews",
    "Using the library, borrowing/returning books",
    "Planning movies/shows with friends",
    "Moving into a new home, installing internet",
    "Weekend brunch with a friend",
    "Registering for a yoga/Pilates class",
    "Picking bread at a local bakery, asking for recommendations",
    "Visiting community center, getting documents",
    "Bicycle tire repair at a bike shop",
    "Nail salon reservation, choosing a design",
    "Cooking at home, sharing recipes",
    "Weekend hiking, recommending a trail",
    "Parent-teacher meeting at child's school",
    "Neighborhood walk, meeting neighbors while walking a dog",
  ],
  business: [
    "Presentations, handling Q&A",
    "Video conferences with overseas partners, coordinating time zones",
    "Negotiating contract terms, requesting revisions",
    "Quarterly performance report, sales analysis",
    "New business proposal, investor pitching",
    "Business networking, exchanging business cards",
    "Scheduling a business trip, settling expenses",
    "Attending conferences, introducing speakers",
    "Business dinner with overseas partners, etiquette",
    "Project kickoff meeting, setting goals",
    "Crisis management, handling client complaints",
    "Performance review, delivering team feedback",
    "Running in-house training / workshops",
    "Selecting vendors, comparing quotes",
    "Joint venture discussions, signing an MOU",
    "Annual business plan, budget allocation",
    "Announcing market research results, competitor analysis",
    "Brand renewal discussions, marketing strategy",
    "Participating in overseas expos, running a booth",
    "Legal review, contract revision discussions",
    "M&A due diligence, company valuation",
    "Board reporting, discussing major agendas",
    "Conducting job interviews, evaluating candidates",
    "Client visits, product demos",
    "Writing business emails, formal expressions",
    "Setting up an overseas subsidiary, checking local regulations",
    "IP protection, patent filing discussions",
    "Proposing a business partnership, win-win strategy",
    "Factory / production facility tours, quality control",
    "Expanding distribution channels, sales strategy",
  ],
};

function pickDailyTopic(environment: string, date: string): string {
  const topics = ENV_TOPICS[environment];
  const dateNum = parseInt(date.replace(/-/g, ""), 10);
  const index = (dateNum + environment.length) % topics.length;
  return topics[index];
}

function buildPrompt(level: string, environment: string, date: string): string {
  const topicHint = pickDailyTopic(environment, date);
  const levelGuide = LEVEL_GUIDE[level];

  return `You are an English teaching content specialist.
Generate English learning content as JSON matching the schema below.

Constraints:
- Level: ${level} (${levelGuide})
- Topic hint: ${topicHint}
- Date: ${date}
- Exactly 3 scenarios

Requirements:
1. The theme must reflect a real situation in the "${environment}" environment.
2. The 3 scenarios must be distinct situations connected by a single theme.
3. English sentences must naturally incorporate grammar appropriate for ${level}.
4. For each scenario, include 2~3 grammar points:
   - "pattern": the English grammar pattern or phrasal verb (e.g., "Work on + noun", "Look forward to + -ing")
   - "example": one short English example sentence using the pattern
5. If a phrasal verb appears in the main sentence, it MUST be included in grammar.
6. All output MUST be in English only. Do NOT include Korean, Japanese, or any other language.

Output ONLY the JSON object below, no extra text:
{
  "theme_en": "Daily ○○ English",
  "scenarios": [
    {
      "order": 1,
      "title_en": "Scenario Title",
      "sentence_en": "English sentences here.",
      "grammar": [
        { "pattern": "Work on + noun", "example": "She is working on her homework." }
      ]
    },
    { "order": 2, "title_en": "...", "sentence_en": "...", "grammar": [{"pattern":"...","example":"..."}] },
    { "order": 3, "title_en": "...", "sentence_en": "...", "grammar": [{"pattern":"...","example":"..."}] }
  ]
}`;
}

interface EnglishLesson {
  theme_en: string;
  scenarios: Array<{
    order: number;
    title_en: string;
    sentence_en: string;
    grammar: Array<{ pattern: string; example: string }>;
  }>;
}

async function generateEnglishLesson(
  apiKey: string,
  level: string,
  environment: string,
  date: string,
): Promise<EnglishLesson | null> {
  const prompt = buildPrompt(level, environment, date);

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
        {
          role: "system",
          content:
            "You are a JSON-only response bot. Output valid JSON. All text (theme, titles, sentences, grammar) MUST be written in English only. Never include Korean, Japanese, Chinese, or any non-English text.",
        },
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
    return JSON.parse(text) as EnglishLesson;
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

    const today = new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Seoul" });

    let targetLevel: string | null = null;
    let targetDate: string | null = null;
    let forceRegenerate = false;
    try {
      const body = await req.json();
      targetLevel = body.level || null;
      targetDate = body.date || null;
      forceRegenerate = body.forceRegenerate === true;
    } catch {
      // 본문 없으면 기본값
    }

    const dateToUse = targetDate || today;
    const levelsToGenerate = targetLevel ? [targetLevel] : LEVELS;

    // 강제 재생성: 기존 영어 콘텐츠 삭제 (번역도 함께 날아감)
    if (forceRegenerate) {
      let deleteQuery = supabase
        .from("daily_lessons_v2")
        .delete()
        .eq("date", dateToUse);
      if (targetLevel) {
        deleteQuery = deleteQuery.eq("level", targetLevel);
      }
      const { error: delErr } = await deleteQuery;
      if (delErr) {
        console.error(`Delete error: ${delErr.message}`);
      } else {
        console.log(`Deleted existing lessons for ${dateToUse}${targetLevel ? `/${targetLevel}` : ""}`);
      }
    }

    // 이미 생성된 영어 레슨 확인 (skip 용)
    const { data: existing } = await supabase
      .from("daily_lessons_v2")
      .select("level, environment")
      .eq("date", dateToUse);

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

        const lesson = await generateEnglishLesson(openaiKey, level, env, dateToUse);
        if (!lesson) {
          failed++;
          return;
        }

        const { error } = await supabase.from("daily_lessons_v2").insert({
          date: dateToUse,
          level: level,
          environment: env,
          theme_en: lesson.theme_en,
          scenarios: lesson.scenarios,
          translations: {},
        });

        if (error) {
          console.error(`Insert error for ${key}: ${error.message}`);
          failed++;
        } else {
          generated++;
          console.log(`Generated EN: ${key}`);
        }
      });

      await Promise.all(promises);
    }

    return new Response(
      JSON.stringify({
        phase: "english",
        date: dateToUse,
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
