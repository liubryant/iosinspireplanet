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
    case female, male, meijia, han
}

enum DigitalHumanPersona: String, CaseIterable, Identifiable {
    case leo
    case lily
    case kai
    case sofia
    case elenaFrost

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lily: return "Lily"
        case .leo: return "Leo"
        case .sofia: return "Sofia"
        case .kai: return "Kai"
        case .elenaFrost: return "Elena Frost"
        }
    }

    var chineseName: String {
        switch self {
        case .lily: return "灵感伙伴"
        case .leo: return "创意伙伴"
        case .sofia: return "知心伙伴"
        case .kai: return "活力伙伴"
        case .elenaFrost: return "温暖伙伴"
        }
    }

    var resourceFolder: String {
        switch self {
        case .lily: return "Lily"
        case .leo: return "Leo"
        case .sofia: return "Sofia"
        case .kai: return "Kai"
        case .elenaFrost: return "ElenaFrost"
        }
    }

    var thumbnailAssetName: String {
        switch self {
        case .leo: return "LeoThumbnail"
        case .lily: return "LilyThumbnail"
        case .sofia: return "SofiaThumbnail"
        case .kai: return "KaiThumbnail"
        case .elenaFrost: return "ElenaFrostThumbnail"
        }
    }

    var portraitAssetName: String? {
        switch self {
        case .leo: return nil
        case .lily: return "LilyPortrait"
        case .sofia: return "SofiaPortrait"
        case .kai: return "KaiPortrait"
        case .elenaFrost: return "ElenaFrostPortrait"
        }
    }

    /// Sofia and Elena Frost intentionally use bundled still portraits only.
    /// Their large DUIX model folders are excluded to reduce the App download size.
    var supportsLiveDigitalHuman: Bool {
        switch self {
        case .sofia, .elenaFrost:
            return false
        case .leo, .lily, .kai:
            return true
        }
    }

    var voice: DigitalHumanVoice {
        switch self {
        case .lily: return .female
        case .leo: return .male
        case .sofia: return .meijia
        case .kai: return .han
        case .elenaFrost: return .female
        }
    }
}
