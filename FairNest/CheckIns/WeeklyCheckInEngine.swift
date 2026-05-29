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

        return Array(changes.prefix(3))
    }

    static func cardsAfterApplying(_ changes: [OwnershipChange], to cards: [LoadCard], at date: Date = Date()) -> [LoadCard] {
        var updatedCards = cards

        for change in changes {
            let trimmedTitle = change.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { continue }
            let normalizedChangeTitle = normalizedTitle(trimmedTitle)

            if let index = updatedCards.firstIndex(where: { card in
                !card.isDeleted && normalizedTitle(card.title) == normalizedChangeTitle
            }) {
                updatedCards[index].reassign(to: change.owner, at: date)
            } else {
                let suggestion = BrainDumpSuggestion(
                    title: trimmedTitle,
                    type: .task,
                    owner: change.owner,
                    effort: .medium,
                    doneCriteria: "Ownership is clear for this week."
                )
                updatedCards.insert(suggestion.makeCard(at: date), at: 0)
            }
        }

        return updatedCards.sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func normalizedTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

enum WeeklyCheckInSaveCoordinator {
    static func handleCheckInSaveFailure(
        previousCards: [LoadCard],
        updatedCards: [LoadCard],
        originalError: Error,
        restorePreviousCards: () throws -> Void
    ) throws {
        guard updatedCards != previousCards else {
            throw originalError
        }

        do {
            try restorePreviousCards()
        } catch let rollbackError {
            throw WeeklyCheckInSaveError.cardRollbackFailed(original: originalError, rollback: rollbackError)
        }

        throw originalError
    }
}

enum WeeklyCheckInSaveError: LocalizedError {
    case cardRollbackFailed(original: Error, rollback: Error)

    var errorDescription: String? {
        switch self {
        case let .cardRollbackFailed(original, rollback):
            return "FairNest could not save this check-in (\(original.localizedDescription)) or restore the previous board state (\(rollback.localizedDescription))."
        }
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
