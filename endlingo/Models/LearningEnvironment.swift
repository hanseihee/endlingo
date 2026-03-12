import Foundation

enum LearningEnvironment: String, CaseIterable, Codable, Identifiable {
    case school
    case work
    case travel
    case daily
    case business

    var id: String { rawValue }

    var title: String {
        switch self {
        case .school:   return "학교"
        case .work:     return "직장"
        case .travel:   return "여행"
        case .daily:    return "일상"
        case .business: return "비즈니스"
        }
    }

    var description: String {
        switch self {
        case .school:   return "수업, 과제, 캠퍼스 생활"
        case .work:     return "회의, 이메일, 동료와 대화"
        case .travel:   return "공항, 호텔, 관광지"
        case .daily:    return "카페, 쇼핑, 일상 대화"
        case .business: return "프레젠테이션, 협상, 보고서"
        }
    }

    var emoji: String {
        switch self {
        case .school:   return "🎓"
        case .work:     return "💼"
        case .travel:   return "✈️"
        case .daily:    return "☕"
        case .business: return "📊"
        }
    }
}
