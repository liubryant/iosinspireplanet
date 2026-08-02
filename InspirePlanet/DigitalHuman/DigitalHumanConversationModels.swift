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
    case female, male, meijia
}

enum DigitalHumanPersona: String, CaseIterable, Identifiable {
    case leo
    case lily
    case sofia

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lily: return "Lily"
        case .leo: return "Leo"
        case .sofia: return "Sofia"
        }
    }

    var chineseName: String {
        switch self {
        case .lily: return "灵感伙伴"
        case .leo: return "创意伙伴"
        case .sofia: return "知心伙伴"
        }
    }

    var resourceFolder: String {
        switch self {
        case .lily: return "Lily"
        case .leo: return "Leo"
        case .sofia: return "Sofia"
        }
    }

    var thumbnailAssetName: String {
        switch self {
        case .leo: return "LeoThumbnail"
        case .lily: return "LilyThumbnail"
        case .sofia: return "SofiaThumbnail"
        }
    }

    var portraitAssetName: String? {
        switch self {
        case .leo: return nil
        case .lily: return "LilyPortrait"
        case .sofia: return "SofiaPortrait"
        }
    }

    var voice: DigitalHumanVoice {
        switch self {
        case .lily: return .female
        case .leo: return .male
        case .sofia: return .meijia
        }
    }
}
