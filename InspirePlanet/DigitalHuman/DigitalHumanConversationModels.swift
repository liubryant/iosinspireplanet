import Foundation

struct DigitalHumanTurn: Identifiable, Codable, Equatable {
    let id: UUID
    let role: InspireChatRole
    let content: String

    init(id: UUID = UUID(), role: InspireChatRole, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

enum DigitalHumanActivity {
    case idle, listening, thinking, speaking
}

enum DigitalHumanVoice {
    case female, male
}

enum DigitalHumanPersona: String, CaseIterable, Identifiable {
    case lily
    case leo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lily: return "Lily"
        case .leo: return "Leo"
        }
    }

    var chineseName: String {
        switch self {
        case .lily: return "灵感伙伴"
        case .leo: return "创意伙伴"
        }
    }

    var resourceFolder: String {
        switch self {
        case .lily: return "Lily"
        case .leo: return "Leo"
        }
    }

    var voice: DigitalHumanVoice {
        switch self {
        case .lily: return .female
        case .leo: return .male
        }
    }
}
