import Foundation

struct WeeklyCheckInDraft: Equatable {
    var feltHeavy: String = ""
    var gotDone: String = ""
    var needsOwnership: String = ""
    var appreciation: String = ""
}

enum WeeklyCheckInEngine {
    static func generateChanges(from draft: WeeklyCheckInDraft, cards: [LoadCard]) -> [OwnershipChange] {
        var changes: [OwnershipChange] = []
        let ownershipText = draft.needsOwnership.trimmingCharacters(in: .whitespacesAndNewlines)

        if !ownershipText.isEmpty {
            let parser = RuleBasedOwnershipParser()
            changes.append(contentsOf: parser.parse(ownershipText))
        }

        if changes.isEmpty {
            let candidates = cards
                .filter { !$0.isDeleted && $0.status != .done && ($0.owner == .unassigned || $0.owner == .shared) }
                .sorted { $0.effort > $1.effort }
                .prefix(3)

            changes.append(contentsOf: candidates.map {
                OwnershipChange(title: $0.title, owner: .me, reason: "Needs a clear owner for this week.")
            })
        }

        return Array(changes.prefix(3))
    }
}

private struct RuleBasedOwnershipParser {
    func parse(_ text: String) -> [OwnershipChange] {
        let changes = text
            .components(separatedBy: CharacterSet(charactersIn: "\n.;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { phrase -> OwnershipChange? in
                let title = cleanedTitle(phrase)
                guard title.count > 2 else { return nil }
                return OwnershipChange(
                    title: title,
                    owner: inferredOwner(phrase.lowercased()),
                    reason: "Captured from the weekly check-in."
                )
            }
        return Array(changes.prefix(3))
    }

    private func inferredOwner(_ lower: String) -> CardOwner {
        if lower.contains("partner") || lower.contains("they") {
            return .partner
        }
        if lower.contains("together") || lower.contains("both") || lower.contains("we ") {
            return .shared
        }
        return .me
    }

    private func cleanedTitle(_ phrase: String) -> String {
        phrase
            .replacingOccurrences(of: #"(?i)^\s*(i|we|partner|they)\s+(will|can|should)\b\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*(i|we|partner|they)\s+(owns?|takes?|handles?)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*(owns?|takes?|handles?)\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
    }
}
