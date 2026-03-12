import Foundation

enum EnglishLevel: String, CaseIterable, Codable, Identifiable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"
    case c1 = "C1"
    case c2 = "C2"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .a1: return "A1 입문"
        case .a2: return "A2 초급"
        case .b1: return "B1 중급"
        case .b2: return "B2 중고급"
        case .c1: return "C1 고급"
        case .c2: return "C2 최상급"
        }
    }

    var description: String {
        switch self {
        case .a1: return "기본 인사와 간단한 표현을 배워요"
        case .a2: return "일상적인 대화를 이해할 수 있어요"
        case .b1: return "여행이나 업무에서 의사소통이 가능해요"
        case .b2: return "복잡한 주제도 자연스럽게 표현해요"
        case .c1: return "전문적인 영어를 유창하게 구사해요"
        case .c2: return "원어민 수준의 영어를 구사해요"
        }
    }

    var emoji: String {
        switch self {
        case .a1: return "🌱"
        case .a2: return "🌿"
        case .b1: return "🌳"
        case .b2: return "🏔️"
        case .c1: return "⭐"
        case .c2: return "👑"
        }
    }
}
