import SwiftUI

struct BrainDumpView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var cardStore: LocalCardStore
    @State private var text = ""
    @State private var suggestions: [BrainDumpSuggestion] = []
    @State private var selectedIDs = Set<UUID>()
    @State private var safetyNotice: SafetyNotice?
    @State private var errorMessage: String?
    @State private var isParsing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .accessibilityLabel("Household thoughts")
                        .accessibilityHint("Enter household tasks, reminders, decisions, or appreciation to turn into reviewable cards.")
                        .accessibilityIdentifier("brainDumpText")
                } header: {
                    Text("Household thoughts")
                } footer: {
                    Text("Messy is fine. Raw text stays private until you save reviewed cards.")
                }

                Section {
                    Button {
                        Task { await parse() }
                    } label: {
                        Label(isParsing ? "Reading" : "Suggest Cards", systemImage: "sparkles")
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)

                    if let safetyNotice {
                        SafetyNoticeRow(notice: safetyNotice)
                    }

                    if suggestions.isEmpty, safetyNotice == nil {
                        ContentUnavailableView(
                            "No suggestions yet",
                            systemImage: "text.badge.plus",
                            description: Text("Add a few thoughts above and review the suggested cards before saving.")
                        )
                    } else {
                        ForEach($suggestions) { $suggestion in
                            SuggestionReviewRow(
                                suggestion: $suggestion,
                                isSelected: selectionBinding(for: suggestion.id)
                            )
                        }
                    }
                } header: {
                    Text("Review before saving")
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
        suggestions.contains { suggestion in
            selectedIDs.contains(suggestion.id) &&
                !suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func parse() async {
        isParsing = true
        defer { isParsing = false }
        do {
            let result = try await services.parser.parse(text, context: BrainDumpContext())
            suggestions = result.suggestions
            selectedIDs = Set(result.suggestions.map(\.id))
            safetyNotice = result.safetyNotice
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveSelected() {
        for suggestion in suggestions where selectedIDs.contains(suggestion.id) &&
            !suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = cardStore.add(suggestion)
        }
        text = ""
        suggestions = []
        selectedIDs = []
        safetyNotice = nil
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
}

private struct SuggestionReviewRow: View {
    @Binding var suggestion: BrainDumpSuggestion
    @Binding var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $isSelected) {
                Label(suggestion.type.label, systemImage: suggestion.type.symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Title", text: $suggestion.title, axis: .vertical)
                .font(.headline)

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
        }
        .padding(.vertical, 4)
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
