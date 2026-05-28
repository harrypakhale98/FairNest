import SwiftUI

enum BrainDumpInputFocus: Hashable {
    case thoughts
    case firstBrainDump
    case suggestionTitle(UUID)
    case suggestionDoneCriteria(UUID)
    case suggestionNotes(UUID)
}

struct BrainDumpView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var cardStore: LocalCardStore
    @State private var text = ""
    @State private var suggestions: [BrainDumpSuggestion] = []
    @State private var selectedIDs = Set<UUID>()
    @State private var safetyNotice: SafetyNotice?
    @State private var errorMessage: String?
    @State private var saveConfirmation: String?
    @State private var isParsing = false
    @State private var lastParsedText: String?
    @FocusState private var focusedField: BrainDumpInputFocus?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Household thoughts", text: $text, axis: .vertical)
                        .focused($focusedField, equals: .thoughts)
                        .lineLimit(6...12)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityLabel("Household thoughts")
                        .accessibilityHint("Enter household tasks, reminders, decisions, or appreciation to turn into reviewable cards.")
                        .accessibilityIdentifier("brainDumpText")

                    Button {
                        dismissKeyboard()
                    } label: {
                        Label("Done", systemImage: "keyboard.chevron.compact.down")
                    }
                    .accessibilityIdentifier("dismissBrainDumpKeyboard")
                } header: {
                    Text("Household thoughts")
                } footer: {
                    Text("Messy is fine. Only reviewed cards are saved; raw text is discarded.")
                }

                Section {
                    Button {
                        dismissKeyboard()
                        Task { await parse() }
                    } label: {
                        Label(isParsing ? "Reading" : "Suggest Cards", systemImage: "sparkles")
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)
                    .accessibilityLabel(isParsing ? "Reading brain dump" : "Suggest Cards")

                    if isParsing {
                        HStack {
                            ProgressView()
                            Text("Reading your thoughts on device")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    if hasStaleReview {
                        Label("Text changed. Suggest cards again before saving.", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                    }

                    if let safetyNotice {
                        SafetyNoticeRow(notice: safetyNotice)
                    }

                    if suggestions.isEmpty, safetyNotice == nil {
                        ReviewEmptyStateRow(
                            title: "No suggestions yet",
                            systemImage: "text.badge.plus",
                            message: "Add a few thoughts above and review the suggested cards before saving."
                        )
                    } else {
                        ForEach($suggestions) { $suggestion in
                            BrainDumpSuggestionReviewRow(
                                suggestion: $suggestion,
                                isSelected: selectionBinding(for: suggestion.id),
                                focusedField: $focusedField
                            )
                        }
                    }
                } header: {
                    Text("Review before saving")
                }

                if let saveConfirmation {
                    Section {
                        Label(saveConfirmation, systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                            .accessibilityIdentifier("brainDumpSaveConfirmation")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityLabel("Brain dump error: \(errorMessage)")
                    }
                }
            }
            .navigationTitle("Brain Dump")
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: text) { _, newValue in
                if !normalized(newValue).isEmpty {
                    saveConfirmation = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveSelected()
                    }
                    .disabled(!hasSavableSelection)
                    .accessibilityIdentifier("saveBrainDumpSuggestions")
                }
            }
        }
    }

    private var hasSavableSelection: Bool {
        isReviewCurrent && suggestions.contains { suggestion in
            selectedIDs.contains(suggestion.id) &&
                !suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var hasStaleReview: Bool {
        !suggestions.isEmpty && !isReviewCurrent
    }

    private var isReviewCurrent: Bool {
        lastParsedText == normalized(text)
    }

    private func parse() async {
        dismissKeyboard()
        let input = normalized(text)
        isParsing = true
        suggestions = []
        selectedIDs = []
        safetyNotice = nil
        errorMessage = nil
        saveConfirmation = nil
        defer { isParsing = false }
        do {
            let result = try await services.parser.parse(input, context: BrainDumpContext())
            suggestions = result.suggestions
            selectedIDs = Set(result.suggestions.map(\.id))
            safetyNotice = result.safetyNotice
            lastParsedText = input
            errorMessage = nil
        } catch {
            lastParsedText = nil
            errorMessage = error.localizedDescription
        }
    }

    private func saveSelected() {
        dismissKeyboard()
        let selectedSuggestions = suggestions.filter { suggestion in
            selectedIDs.contains(suggestion.id) &&
                !suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        do {
            let savedCards = try cardStore.addReviewed(selectedSuggestions)
            let cardWord = savedCards.count == 1 ? "card" : "cards"
            saveConfirmation = "Saved \(savedCards.count) \(cardWord)."
            errorMessage = nil
            text = ""
            suggestions = []
            selectedIDs = []
            safetyNotice = nil
            lastParsedText = nil
        } catch {
            saveConfirmation = nil
            errorMessage = error.localizedDescription
        }
    }

    private func selectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { isSelected in
                if isSelected {
                    selectedIDs.insert(id)
                } else {
                    selectedIDs.remove(id)
                }
            }
        )
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dismissKeyboard() {
        focusedField = nil
    }
}

struct ReviewEmptyStateRow: View {
    var title: String
    var systemImage: String
    var message: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct BrainDumpSuggestionReviewRow: View {
    @Binding var suggestion: BrainDumpSuggestion
    @Binding var isSelected: Bool
    @State private var hasDueDate: Bool
    var focusedField: FocusState<BrainDumpInputFocus?>.Binding

    init(
        suggestion: Binding<BrainDumpSuggestion>,
        isSelected: Binding<Bool>,
        focusedField: FocusState<BrainDumpInputFocus?>.Binding
    ) {
        _suggestion = suggestion
        _isSelected = isSelected
        _hasDueDate = State(initialValue: suggestion.wrappedValue.dueDate != nil)
        self.focusedField = focusedField
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $isSelected) {
                Label("Include this card", systemImage: suggestion.type.symbolName)
            }

            TextField("Title", text: $suggestion.title, axis: .vertical)
                .focused(focusedField, equals: .suggestionTitle(suggestion.id))
                .font(.headline)
                .accessibilityIdentifier("brainDumpSuggestionTitle")

            Picker("Type", selection: $suggestion.type) {
                ForEach(CardType.allCases) { type in
                    Label(type.label, systemImage: type.symbolName).tag(type)
                }
            }

            Picker("Owner", selection: $suggestion.owner) {
                ForEach(CardOwner.allCases) { owner in
                    Text(owner.label).tag(owner)
                }
            }

            Picker("Effort", selection: $suggestion.effort) {
                ForEach(Effort.allCases) { effort in
                    Text(effort.label).tag(effort)
                }
            }

            Toggle("Due date", isOn: dueDateEnabled)

            if hasDueDate {
                DatePicker(
                    "When",
                    selection: Binding(
                        get: { suggestion.dueDate ?? Date() },
                        set: { suggestion.dueDate = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
            }

            Picker("Recurrence", selection: $suggestion.recurrence) {
                ForEach(recurrenceOptions, id: \.self) { recurrence in
                    Text(recurrence.label).tag(recurrence)
                }
            }

            TextField("Done criteria", text: $suggestion.doneCriteria, axis: .vertical)
                .focused(focusedField, equals: .suggestionDoneCriteria(suggestion.id))
                .accessibilityIdentifier("brainDumpSuggestionDoneCriteria")

            TextField("Notes", text: $suggestion.notes, axis: .vertical)
                .focused(focusedField, equals: .suggestionNotes(suggestion.id))
                .accessibilityIdentifier("brainDumpSuggestionNotes")
        }
        .padding(.vertical, 4)
    }

    private var dueDateEnabled: Binding<Bool> {
        Binding(
            get: { hasDueDate },
            set: { enabled in
                hasDueDate = enabled
                suggestion.dueDate = enabled ? (suggestion.dueDate ?? Date()) : nil
            }
        )
    }

    private var recurrenceOptions: [Recurrence] {
        var options: [Recurrence] = [.none, .daily]
        let calendar = Calendar.current
        let weeklyDay: Int
        if case .weekly(let weekday) = suggestion.recurrence {
            weeklyDay = weekday
        } else if let dueDate = suggestion.dueDate {
            weeklyDay = calendar.component(.weekday, from: dueDate)
        } else {
            weeklyDay = calendar.component(.weekday, from: Date())
        }
        options.append(.weekly(weekday: weeklyDay))

        let monthlyDay: Int
        if case .monthly(let day) = suggestion.recurrence {
            monthlyDay = day
        } else if let dueDate = suggestion.dueDate {
            monthlyDay = calendar.component(.day, from: dueDate)
        } else {
            monthlyDay = calendar.component(.day, from: Date())
        }
        options.append(.monthly(day: monthlyDay))

        if !options.contains(suggestion.recurrence) {
            options.append(suggestion.recurrence)
        }
        return options
    }
}

private struct SafetyNoticeRow: View {
    var notice: SafetyNotice

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.headline)
                Text(notice.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}
