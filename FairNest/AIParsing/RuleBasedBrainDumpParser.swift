import Foundation

struct RuleBasedBrainDumpParser: BrainDumpParser {
    func parse(_ text: String, context: BrainDumpContext = BrainDumpContext()) async throws -> BrainDumpParseResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BrainDumpParserError.emptyInput }

        if let safetyNotice = SafetyClassifier.noticeIfNeeded(for: trimmed) {
            return BrainDumpParseResult(suggestions: [], safetyNotice: safetyNotice, source: .ruleBased)
        }

        let suggestions = split(trimmed)
            .prefix(12)
            .compactMap { makeSuggestion(from: $0, context: context) }

        return BrainDumpParseResult(suggestions: Array(suggestions), safetyNotice: nil, source: .ruleBased)
    }

    private func split(_ text: String) -> [String] {
        let hardBreaks = CharacterSet(charactersIn: "\n.;•")
        return text
            .components(separatedBy: hardBreaks)
            .flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 2 }
    }

    private func makeSuggestion(from phrase: String, context: BrainDumpContext) -> BrainDumpSuggestion? {
        let cleaned = phrase
            .replacingOccurrences(of: #"^\s*(we need to|need to|remember to|please|can you|i need to)\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > 2 else { return nil }

        let lower = cleaned.lowercased()
        let type = classify(lower)
        let owner = inferOwner(lower, defaultOwner: context.defaultOwner)
        let recurrence = inferRecurrence(lower, today: context.today)
        let dueDate = inferDueDate(lower, today: context.today)
        let effort = inferEffort(lower)

        return BrainDumpSuggestion(
            title: titleCase(cleaned),
            type: type,
            owner: owner,
            effort: effort,
            dueDate: dueDate,
            recurrence: recurrence,
            notes: "",
            doneCriteria: doneCriteria(for: type),
            sourceSnippet: phrase
        )
    }

    private func classify(_ lower: String) -> CardType {
        if lower.contains("thank") || lower.contains("appreciate") || lower.contains("grateful") {
            return .appreciation
        }
        if lower.contains("decide") || lower.contains("choose") || lower.contains("figure out") {
            return .decision
        }
        if lower.contains("talk about") || lower.contains("discuss") || lower.contains("conversation") || lower.contains("check in") {
            return .conversation
        }
        if lower.contains("remind") || lower.contains("appointment") || lower.contains("deadline") {
            return .reminder
        }
        if lower.contains("every ") || lower.contains("weekly") || lower.contains("daily") || lower.contains("monthly") || lower.contains("each ") {
            return .recurringResponsibility
        }
        return .task
    }

    private func inferOwner(_ lower: String, defaultOwner: CardOwner) -> CardOwner {
        if lower.contains(" we ") || lower.hasPrefix("we ") || lower.contains("together") {
            return .shared
        }
        if lower.contains("partner") || lower.contains("spouse") || lower.contains("they need") {
            return .partner
        }
        if lower.contains(" i ") || lower.hasPrefix("i ") || lower.contains(" my ") {
            return .me
        }
        return defaultOwner
    }

    private func inferEffort(_ lower: String) -> Effort {
        if lower.contains("deep clean") || lower.contains("tax") || lower.contains("repair") || lower.contains("plan trip") {
            return .heavy
        }
        if lower.contains("quick") || lower.contains("text ") || lower.contains("email ") {
            return .tiny
        }
        if lower.contains("call ") || lower.contains("pick up") || lower.contains("laundry") {
            return .light
        }
        return .medium
    }

    private func inferRecurrence(_ lower: String, today: Date) -> Recurrence {
        if lower.contains("daily") || lower.contains("every day") {
            return .daily
        }
        let calendar = Calendar.current
        let weekdayPairs = calendar.weekdaySymbols.enumerated().map { ($0.element.lowercased(), $0.offset + 1) }
        if let match = weekdayPairs.first(where: { weekday, _ in
            lower.contains("every \(weekday)") ||
                lower.contains("each \(weekday)") ||
                lower.contains("every \(weekday)s") ||
                lower.contains("each \(weekday)s")
        }) {
            return .weekly(weekday: match.1)
        }
        if lower.contains("weekly") || lower.contains("every week") {
            return .weekly(weekday: calendar.component(.weekday, from: today))
        }
        if lower.contains("monthly") || lower.contains("every month") {
            return .monthly(day: calendar.component(.day, from: today))
        }
        return .none
    }

    private func inferDueDate(_ lower: String, today: Date) -> Date? {
        let calendar = Calendar.current
        if lower.contains("today") { return calendar.startOfDay(for: today) }
        if lower.contains("tomorrow") { return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today)) }
        if lower.contains("this week") { return calendar.date(byAdding: .day, value: 6, to: calendar.startOfDay(for: today)) }

        let weekdayPairs = calendar.weekdaySymbols.enumerated().map { ($0.element.lowercased(), $0.offset + 1) }
        if let match = weekdayPairs.first(where: { lower.contains($0.0.lowercased()) }) {
            var components = DateComponents()
            components.weekday = match.1
            return calendar.nextDate(after: today, matching: components, matchingPolicy: .nextTimePreservingSmallerComponents)
        }
        return nil
    }

    private func doneCriteria(for type: CardType) -> String {
        switch type {
        case .decision: return "Decision is recorded."
        case .conversation: return "Conversation happened and any next step is captured."
        case .appreciation: return "Appreciation is saved."
        case .recurringResponsibility: return "Responsibility is handled for this occurrence."
        case .reminder: return "Reminder has been addressed."
        case .task: return "Task is complete."
        }
    }

    private func titleCase(_ value: String) -> String {
        let lowerWords = ["a", "an", "and", "at", "for", "in", "of", "on", "or", "the", "to"]
        return value
            .split(separator: " ")
            .enumerated()
            .map { index, word in
                let lower = word.lowercased()
                if index > 0, lowerWords.contains(lower) { return lower }
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }
}
