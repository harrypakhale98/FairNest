import Foundation

protocol BrainDumpParser: Sendable {
    func parse(_ text: String, context: BrainDumpContext) async throws -> BrainDumpParseResult
}

enum BrainDumpParserError: LocalizedError {
    case emptyInput

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Add a few household thoughts before parsing."
        }
    }
}

enum SafetyClassifier {
    static func noticeIfNeeded(for text: String) -> SafetyNotice? {
        let normalized = normalize(text)
        let selfHarm = [
            "kill myself",
            "suicide",
            "hurt myself",
            "harm myself",
            "end my life",
            "self harm",
            "self-harm",
            "want to die",
            "wanted to die",
            "die by suicide",
            "cut myself"
        ]
        let immediateDanger = [
            "call 911",
            "emergency",
            "in danger right now",
            "weapon",
            "threatened me",
            "threatened to hurt",
            "scared to go home",
            "afraid to go home"
        ]
        let abuse = [
            "hit me",
            "hits me",
            "partner hit",
            "partner hurts",
            "afraid of my partner",
            "scared of my partner",
            "domestic violence",
            "choked me",
            "strangled me",
            "coerced",
            "forced me",
            "controls my money",
            "won't let me leave",
            "wont let me leave"
        ]

        if containsAny(selfHarm + immediateDanger + abuse, in: normalized) {
            return SafetyNotice(
                title: "This may need support outside FairNest",
                message: "FairNest will not turn this into household tasks. If you may be in immediate danger, consider contacting local emergency services or a trusted person. You can still use FairNest later for ordinary household organization."
            )
        }
        return nil
    }

    private static func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
    }
}
