import SwiftUI

private enum OnboardingFocusedField: Hashable {
    case firstBrainDump
}

struct OnboardingView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var cardStore: LocalCardStore
    @State private var step = 0
    @State private var brainDump = ""
    @State private var suggestions: [BrainDumpSuggestion] = []
    @State private var selectedSuggestionIDs = Set<UUID>()
    @State private var notice: SafetyNotice?
    @State private var isParsing = false
    @State private var errorMessage: String?
    @State private var lastParsedBrainDump: String?
    @FocusState private var focusedField: OnboardingFocusedField?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $step) {
                    ScrollView {
                        onboardingStep(
                            title: "Share the home load",
                            symbol: "house.and.flag",
                            text: "FairNest turns household work, decisions, reminders, and appreciation into clear shared cards."
                        )
                    }
                    .tag(0)

                    ScrollView {
                        onboardingStep(
                            title: "Private by design",
                            symbol: "lock.shield",
                            text: "FairNest works offline, syncs with iCloud when available, and uses on-device intelligence with a deterministic fallback."
                        )
                    }
                    .tag(1)

                    firstBrainDumpStep
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))

                Divider()

                HStack {
                    Button("Back") {
                        step = max(0, step - 1)
                    }
                    .disabled(step == 0)

                    Spacer()

                    Button(primaryActionTitle) {
                        if step < 2 {
                            step += 1
                        } else if shouldParseBeforeFinish {
                            Task { await parse() }
                        } else {
                            saveAndFinish()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(step == 2 && isParsing)
                    .accessibilityIdentifier("onboardingContinue")
                }
                .padding()
            }
            .navigationTitle("FairNest")
        }
    }

    private func onboardingStep(title: String, symbol: String, text: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }

    private var firstBrainDumpStep: some View {
        Form {
            Section {
                TextEditor(text: $brainDump)
                    .focused($focusedField, equals: .firstBrainDump)
                    .frame(minHeight: 120)
                    .accessibilityLabel("First brain dump")
                    .accessibilityHint("Enter a few household thoughts to create reviewable starter cards.")
                    .accessibilityIdentifier("onboardingBrainDump")
            } header: {
                Text("First brain dump")
            } footer: {
                Text("Try: laundry every Sunday, decide grocery budget, thank partner for dishes. You review every suggestion before saving.")
            }

            Section {
                Button {
                    focusedField = nil
                    Task { await parse() }
                } label: {
                    Label(isParsing ? "Parsing" : "Suggest Cards", systemImage: "sparkles")
                }
                .disabled(brainDump.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)
                .accessibilityLabel(isParsing ? "Reading first brain dump" : "Suggest Cards")

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

                if let notice {
                    safetyNoticeView(notice)
                }

                if suggestions.isEmpty, notice == nil {
                    ContentUnavailableView(
                        "No suggestions yet",
                        systemImage: "text.badge.plus",
                        description: Text("Add a few thoughts above and review the suggested cards before saving.")
                    )
                } else {
                    ForEach($suggestions) { $suggestion in
                        BrainDumpSuggestionReviewRow(
                            suggestion: $suggestion,
                            isSelected: selectionBinding(for: suggestion.id)
                        )
                    }
                }
            } header: {
                Text("Review")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
                .fontWeight(.semibold)
                .accessibilityIdentifier("dismissOnboardingBrainDumpKeyboard")
            }
        }
    }

    private var primaryActionTitle: String {
        if step < 2 {
            return "Continue"
        }
        return shouldParseBeforeFinish ? "Review Cards" : "Start FairNest"
    }

    private var shouldParseBeforeFinish: Bool {
        let input = normalized(brainDump)
        return !input.isEmpty && lastParsedBrainDump != input
    }

    private var hasStaleReview: Bool {
        !suggestions.isEmpty && lastParsedBrainDump != normalized(brainDump)
    }

    private func selectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedSuggestionIDs.contains(id) },
            set: { isSelected in
                if isSelected {
                    selectedSuggestionIDs.insert(id)
                } else {
                    selectedSuggestionIDs.remove(id)
                }
            }
        )
    }

    private func parse() async {
        focusedField = nil
        let input = normalized(brainDump)
        isParsing = true
        suggestions = []
        selectedSuggestionIDs = []
        notice = nil
        errorMessage = nil
        defer { isParsing = false }
        do {
            let result = try await services.parser.parse(input, context: BrainDumpContext())
            notice = result.safetyNotice
            suggestions = result.suggestions
            selectedSuggestionIDs = Set(result.suggestions.map(\.id))
            lastParsedBrainDump = input
            errorMessage = nil
        } catch {
            lastParsedBrainDump = nil
            errorMessage = error.localizedDescription
        }
    }

    private func saveAndFinish() {
        focusedField = nil
        let selectedSuggestions = suggestions.filter { suggestion in
            selectedSuggestionIDs.contains(suggestion.id) &&
                !suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        do {
            _ = try cardStore.addReviewed(selectedSuggestions)
            services.completeOnboarding()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func safetyNoticeView(_ notice: SafetyNotice) -> some View {
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
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
