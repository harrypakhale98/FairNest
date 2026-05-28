import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
@Generable
struct FoundationBrainDumpOutput {
    var suggestions: [FoundationBrainDumpSuggestion]
}

@available(iOS 26.0, *)
@Generable
struct FoundationBrainDumpSuggestion {
    var title: String
    var type: String
    var owner: String
    var effort: String
    var notes: String
    var doneCriteria: String
}
#endif

struct FoundationModelsBrainDumpParser: BrainDumpParser {
    private let fallback: RuleBasedBrainDumpParser

    init(fallback: RuleBasedBrainDumpParser = RuleBasedBrainDumpParser()) {
        self.fallback = fallback
    }

    func parse(_ text: String, context: BrainDumpContext = BrainDumpContext()) async throws -> BrainDumpParseResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BrainDumpParserError.emptyInput }

        if let safetyNotice = SafetyClassifier.noticeIfNeeded(for: trimmed) {
            return BrainDumpParseResult(suggestions: [], safetyNotice: safetyNotice, source: .ruleBased)
        }

        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return try await fallback.parse(trimmed, context: context)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable, model.supportsLocale(context.locale) else {
                return try await fallback.parse(trimmed, context: context)
            }

            do {
                let session = LanguageModelSession(
                    model: model,
                    instructions: """
                    You turn household brain dumps into calm, concrete FairNest cards.
                    Return only structured suggestions. Do not provide therapy, diagnosis, legal, medical, or emergency advice.
                    Do not include raw private text beyond short neutral card titles.
                    Card types must be one of task, recurringResponsibility, decision, reminder, conversation, appreciation.
                    Owners must be one of unassigned, me, partner, shared.
                    Effort must be one of tiny, light, medium, heavy.
                    """
                )
                let response = try await session.respond(
                    to: "Create at most 8 editable household organization cards from this text:\n\(trimmed)",
                    generating: FoundationBrainDumpOutput.self
                )
                var mapped: [BrainDumpSuggestion] = []
                for suggestion in response.content.suggestions.prefix(8) {
                    if let card = await map(suggestion, context: context) {
                        mapped.append(card)
                    }
                }
                if !mapped.isEmpty {
                    return BrainDumpParseResult(suggestions: mapped, safetyNotice: nil, source: .foundationModels)
                }
            } catch {
                return try await fallback.parse(trimmed, context: context)
            }
        }
        #endif

        return try await fallback.parse(trimmed, context: context)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func map(_ suggestion: FoundationBrainDumpSuggestion, context: BrainDumpContext) async -> BrainDumpSuggestion? {
        let title = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count > 2 else { return nil }
        let deterministicText = [title, suggestion.notes, suggestion.doneCriteria]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: ". ")
        let deterministicResult = try? await fallback.parse(deterministicText, context: context)
        let deterministicSuggestion = deterministicResult?.suggestions.first
        return BrainDumpSuggestion(
            title: title,
            type: CardType(rawValue: suggestion.type) ?? .task,
            owner: CardOwner(rawValue: suggestion.owner) ?? .unassigned,
            effort: effort(from: suggestion.effort),
            dueDate: deterministicSuggestion?.dueDate,
            recurrence: deterministicSuggestion?.recurrence ?? .none,
            notes: suggestion.notes,
            doneCriteria: suggestion.doneCriteria.isEmpty ? "Card is complete." : suggestion.doneCriteria,
            sourceSnippet: ""
        )
    }

    private func effort(from value: String) -> Effort {
        switch value {
        case "tiny": .tiny
        case "light": .light
        case "heavy": .heavy
        default: .medium
        }
    }
    #endif
}
