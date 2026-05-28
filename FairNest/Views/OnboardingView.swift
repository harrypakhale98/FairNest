import SwiftUI

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

                    Button(step == 2 ? "Start FairNest" : "Continue") {
                        if step < 2 {
                            step += 1
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
                    Task { await parse() }
                } label: {
                    Label(isParsing ? "Parsing" : "Suggest Cards", systemImage: "sparkles")
                }
                .disabled(brainDump.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)

                if let notice {
                    safetyNoticeView(notice)
                }

                ForEach($suggestions) { $suggestion in
                    Toggle(isOn: selectionBinding(for: suggestion.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Title", text: $suggestion.title)
                            Text(suggestion.type.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
        isParsing = true
        defer { isParsing = false }
        do {
            let result = try await services.parser.parse(brainDump, context: BrainDumpContext())
            notice = result.safetyNotice
            suggestions = result.suggestions
            selectedSuggestionIDs = Set(result.suggestions.map(\.id))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveAndFinish() {
        for suggestion in suggestions where selectedSuggestionIDs.contains(suggestion.id) &&
            !suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = cardStore.add(suggestion)
        }
        services.completeOnboarding()
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
}
