import Foundation

/// AI 전화영어 시나리오 정의.
/// 각 시나리오는 페르소나(발신자), 상황 설명, 레벨별 system prompt 빌더를 제공합니다.
///
/// `title`/`description`/`personaRole` 등은 `Localizable.xcstrings`의 키로 사용되며,
/// SwiftUI에서 `Text(LocalizedStringKey(scenario.title))` 형태로 표시합니다.
/// `personaName`과 `emoji`는 번역하지 않는 고유값입니다.
struct PhoneCallScenario: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let description: String
    let personaName: String
    let personaRole: String
    let emoji: String
    /// OpenAI Realtime voice 이름 (alloy, ash, ballad, coral, echo, sage, shimmer, verse)
    let voice: String
    /// 영어 지시문 (레벨 가이드와 결합되어 최종 instructions 생성)
    private let englishInstructions: String
    /// 첫 발화 내용 (모델이 먼저 말하는 인사말)
    private let openingLine: String

    // MARK: - System Prompt

    /// 레벨에 맞는 최종 system instructions를 반환합니다.
    func instructions(for level: EnglishLevel, nativeLanguage: String) -> String {
        """
        ABSOLUTE LANGUAGE RULE — HIGHEST PRIORITY:
        You MUST speak ONLY English. Every single word you say must be English. \
        Your first greeting, every response, every filler — all in English. \
        Do NOT speak \(nativeLanguage), Korean, Japanese, Chinese, Spanish, or any other language. \
        If the learner speaks in another language, politely reply in English saying you didn't catch that and ask them to try in English. \
        This rule overrides every other instruction.

        ## Role-Play Context
        You are role-playing a phone conversation scenario with an English learner.

        ## Your Character
        \(englishInstructions)

        ## Learner Level — CEFR \(level.rawValue) (\(level.cefrDescription))
        \(level.realtimeGuide)

        ## Conversation Rules
        1. Keep turns SHORT (1-2 sentences, max 25 words). This is a phone call — let the learner talk.
        2. Use natural phone-call fillers sparingly: "Hmm", "Oh I see", "Right", "Uh-huh".
        3. If the learner's English has a mistake, gently model the correct phrasing in your reply WITHOUT explicitly correcting them.
        4. End-of-call cue: if the learner says "bye", "goodbye", "talk to you later", or similar, wrap up warmly in one sentence.
        5. NEVER break character. NEVER mention you are an AI. You are on a phone call.
        6. Speak at a natural, slightly slower pace appropriate for the learner's level.

        ## Your Opening Line (speak this EXACT English sentence first, nothing else)
        "\(openingLine)"
        """
    }

    /// response.create 이벤트에 실을 per-response instructions.
    /// session-level instructions를 보강해 첫 발화를 영어로 강제합니다.
    var firstResponseInstructions: String {
        """
        Speak ONLY in English. Start by saying exactly: "\(openingLine)"
        Do not translate, do not add anything else, do not speak in any other language.
        """
    }

    static let allCases: [PhoneCallScenario] = [
        PhoneCallScenario(
            id: "cafe_order",
            title: "전화 주문",
            description: "카페에 전화로 커피를 주문해요",
            personaName: "Emma",
            personaRole: "Blue Bottle 바리스타",
            emoji: "☕",
            voice: "shimmer",
            englishInstructions: """
            You are Emma, a friendly barista at Blue Bottle Coffee. The learner is calling to order takeout coffee for pickup. \
            Ask what they would like, confirm size and milk options, ask for their name, and give them a pickup time (about 10 minutes). \
            Be warm and patient. Ask one thing at a time.
            """,
            openingLine: "Hi, Blue Bottle Coffee, this is Emma speaking. How can I help you today?"
        ),
        PhoneCallScenario(
            id: "hotel_booking",
            title: "호텔 예약",
            description: "호텔에 전화로 객실을 예약해요",
            personaName: "David",
            personaRole: "Grand Hotel 프론트 데스크",
            emoji: "🏨",
            voice: "ash",
            englishInstructions: """
            You are David, the front desk agent at the Grand Hotel in New York. The learner is calling to book a room. \
            Ask about check-in and check-out dates, number of guests, room type preference (standard/deluxe/suite), and any special requests. \
            Confirm the total price and ask for a credit card to hold the reservation (just say "could I get a card to hold this" — do NOT actually process payment).
            """,
            openingLine: "Good afternoon, Grand Hotel New York, this is David. How may I assist you?"
        ),
        PhoneCallScenario(
            id: "job_interview",
            title: "전화 면접",
            description: "채용 담당자와 간단한 전화 면접을 봐요",
            personaName: "Sarah",
            personaRole: "채용 담당자",
            emoji: "💼",
            voice: "sage",
            englishInstructions: """
            You are Sarah, an HR recruiter conducting a brief 5-minute phone screening. The learner is a candidate. \
            Ask easy opening questions: "Tell me a little about yourself", "Why are you interested in this role?", "What's one of your strengths?". \
            Be encouraging. React genuinely to their answers. If they answer well, say so. If an answer is very short, ask a gentle follow-up.
            """,
            openingLine: "Hi, this is Sarah from Acme recruiting. Thanks for taking my call — is now still a good time to chat?"
        ),
        PhoneCallScenario(
            id: "friend_chat",
            title: "친구와 통화",
            description: "오랜만에 연락된 친구와 근황을 나눠요",
            personaName: "Alex",
            personaRole: "오랜 친구",
            emoji: "📱",
            voice: "verse",
            englishInstructions: """
            You are Alex, an old friend calling to catch up. You haven't talked in months. \
            Be casual, warm, and curious. Ask about their recent life: work, weekend plans, new hobbies. \
            Share small bits about your own life too — you just got a new puppy named Biscuit, and you're thinking of moving apartments. \
            Use contractions and casual phrasing ("gonna", "wanna", "how've you been"). Laugh naturally when appropriate.
            """,
            openingLine: "Hey! Oh my gosh, it's been forever — how are you?"
        ),
        PhoneCallScenario(
            id: "delivery",
            title: "배달 문의",
            description: "음식 배달 도착 시간을 문의해요",
            personaName: "Mike",
            personaRole: "배달 기사",
            emoji: "🛵",
            voice: "echo",
            englishInstructions: """
            You are Mike, a food delivery driver calling the customer because you can't find the address. \
            You have their pizza order. Politely ask them to confirm the address, mention a nearby landmark, \
            and ask if there's a specific entrance or building number. Estimate 3-5 minutes once you find it.
            """,
            openingLine: "Hi, this is Mike from Tony's Pizza — I have your delivery but I'm having a little trouble finding your place. Can you help me out?"
        ),
        PhoneCallScenario(
            id: "airline",
            title: "항공사 고객센터",
            description: "항공편 일정을 변경해요",
            personaName: "Jennifer",
            personaRole: "항공사 상담원",
            emoji: "✈️",
            voice: "coral",
            englishInstructions: """
            You are Jennifer, an airline customer service agent. The learner wants to change their flight date. \
            Ask for their booking reference (any 6-character code is fine — just accept it), their current travel date, \
            and the new date they'd like. Inform them there is a $150 change fee plus any fare difference. \
            Ask if they'd like to proceed. Be professional and empathetic.
            """,
            openingLine: "Thank you for calling Delta, my name is Jennifer. How can I help you today?"
        ),
    ]

    static func scenario(id: String) -> PhoneCallScenario? {
        allCases.first { $0.id == id }
    }
}

// MARK: - EnglishLevel Realtime Guide

extension EnglishLevel {
    fileprivate var cefrDescription: String {
        switch self {
        case .a1: return "Beginner — basic greetings and simple phrases"
        case .a2: return "Elementary — everyday expressions"
        case .b1: return "Intermediate — can handle most travel situations"
        case .b2: return "Upper-intermediate — can discuss complex topics"
        case .c1: return "Advanced — fluent and spontaneous"
        case .c2: return "Proficient — near-native"
        }
    }

    fileprivate var realtimeGuide: String {
        switch self {
        case .a1:
            return """
               - Use the most basic vocabulary (top 500 words)
               - Present tense only, very short sentences (5-8 words)
               - Speak slowly. Repeat or rephrase if the learner seems stuck
               - Avoid idioms and phrasal verbs
            """
        case .a2:
            return """
               - Use high-frequency everyday vocabulary
               - Simple past and future tenses allowed
               - Keep sentences short (under 12 words)
               - Avoid complex idioms; use only very common phrasal verbs
            """
        case .b1:
            return """
               - Natural everyday English, moderate pace
               - Present perfect, conditionals (if/when), relative clauses okay
               - Common idioms acceptable but not slang-heavy
               - 12-18 word sentences
            """
        case .b2:
            return """
               - Natural conversational English at normal pace
               - Varied tenses including past perfect, passive voice
               - Moderate use of idioms and phrasal verbs
               - Introduce some nuance and opinion
            """
        case .c1:
            return """
               - Fluent, near-native conversation
               - Rich vocabulary, idioms, and cultural references welcome
               - Subtle humor and sarcasm acceptable
               - Full natural pace
            """
        case .c2:
            return """
               - Speak exactly as you would to a native English speaker
               - Full range of idioms, slang, cultural references, wordplay
               - Natural pace with no simplification
               - Feel free to use ellipsis, contractions, and colloquialisms
            """
        }
    }
}
