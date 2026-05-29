import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OnboardingView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var cardStore: LocalCardStore
    @State private var step = 0
    @State private var brainDump = ""
    @State private var suggestions: [BrainDumpSuggestion] = []
    @State private var selectedSuggestionIDs = Set<UUID>()
    @State private var notice: SafetyNotice?
    @State private var isParsing = false
    @State private var errorMessage: String?
    @State private var validationMessage: String?
    @State private var lastParsedBrainDump: String?
    @FocusState private var focusedField: BrainDumpInputFocus?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if dynamicTypeSize.isAccessibilitySize {
                    if step == 2 {
                        firstBrainDumpStep
                    } else {
                        ScrollView {
                            currentStep
                                .padding(.bottom, 24)
                        }
                    }
                } else {
                    TabView(selection: $step) {
                        ScrollView {
                            stepIntro(
                                title: "Share the home load",
                                symbol: "house.and.flag",
                                text: "FairNest turns household work, decisions, reminders, and appreciation into clear shared cards."
                            )
                        }
                        .tag(0)

                        ScrollView {
                            stepIntro(
                                title: "Private by design",
                                symbol: "lock.shield",
                                text: "FairNest works offline, syncs with iCloud when available, and can suggest cards on this iPhone."
                            )
                        }
                        .tag(1)

                        firstBrainDumpStep
                            .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                }

                Divider()

                actionBar
            }
            .navigationTitle("FairNest")
            .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .automatic)
        }
    }

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case 0:
            stepIntro(
                title: "Share the home load",
                symbol: "house.and.flag",
                text: "FairNest turns household work, decisions, reminders, and appreciation into clear shared cards."
            )
        case 1:
            stepIntro(
                title: "Private by design",
                symbol: "lock.shield",
                text: "FairNest works offline, syncs with iCloud when available, and can suggest cards on this iPhone."
            )
        default:
            firstBrainDumpStep
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                Button(primaryActionTitle) {
                    primaryAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(step == 2 && isParsing)
                .accessibilityIdentifier("onboardingContinue")

                Button("Back") {
                    goBack()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(step == 0)
            }
            .padding()
        } else {
            HStack {
                Button("Back") {
                    goBack()
                }
                .disabled(step == 0)

                Spacer()

                Button(primaryActionTitle) {
                    primaryAction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(step == 2 && isParsing)
                .accessibilityIdentifier("onboardingContinue")
            }
            .padding()
        }
    }

    private func goBack() {
        dismissKeyboard()
        step = max(0, step - 1)
    }

    private func stepIntro(title: String, symbol: String, text: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 38 : 48, weight: .regular))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(title)
                .font(dynamicTypeSize.isAccessibilitySize ? .title.bold() : .largeTitle.bold())
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
                TextField("First brain dump", text: $brainDump, axis: .vertical)
                    .focused($focusedField, equals: .firstBrainDump)
                    .lineLimit(5...10)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel("First brain dump")
                    .accessibilityHint("Enter a few household thoughts to create reviewable starter cards.")
                    .accessibilityIdentifier("onboardingBrainDump")

                Button {
                    dismissKeyboard()
                } label: {
                    Label("Done", systemImage: "keyboard.chevron.compact.down")
                }
                .accessibilityIdentifier("dismissOnboardingBrainDumpKeyboard")
            } header: {
                Text("First brain dump")
            } footer: {
                Text("Try: laundry every Sunday, decide grocery budget, thank partner for dishes. You review every suggestion before saving.")
            }

            Section {
                Button {
                    dismissKeyboard()
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

                if hasStaleReview, !suggestions.isEmpty {
                    Label("Text changed. Suggest cards again before saving.", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                }

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("onboardingBrainDumpValidation")
                }

                if let notice, !hasStaleReview {
                    safetyNoticeView(notice)
                }

                if let reviewEmptyState {
                    ReviewEmptyStateRow(
                        title: reviewEmptyState.title,
                        systemImage: reviewEmptyState.systemImage,
                        message: reviewEmptyState.message
                    )
                } else {
                    ForEach(suggestions.indices, id: \.self) { index in
                        BrainDumpSuggestionReviewRow(
                            suggestion: $suggestions[index],
                            isSelected: selectionBinding(for: suggestions[index].id),
                            position: index + 1,
                            totalCount: suggestions.count,
                            focusedField: $focusedField
                        )
                    }
                }
            } header: {
                Text("Review")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Onboarding error: \(errorMessage)")
                        .accessibilityIdentifier("onboardingBrainDumpError")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onDisappear {
            dismissKeyboard()
        }
    }

    private var primaryActionTitle: String {
        if step < 2 {
            return "Continue"
        }
        return shouldParseBeforeFinish ? "Review Cards" : "Start FairNest"
    }

    private func primaryAction() {
        if step < 2 {
            step += 1
        } else if shouldParseBeforeFinish {
            Task { await parse() }
        } else {
            saveAndFinish()
        }
    }

    private var firstSelectedBlankTitleSuggestion: BrainDumpSuggestion? {
        suggestions.first { suggestion in
            selectedSuggestionIDs.contains(suggestion.id) &&
                normalized(suggestion.title).isEmpty
        }
    }

    private var shouldParseBeforeFinish: Bool {
        let input = normalized(brainDump)
        return !input.isEmpty && lastParsedBrainDump != input
    }

    private var hasStaleReview: Bool {
        lastParsedBrainDump != nil && !isReviewCurrent
    }

    private var isReviewCurrent: Bool {
        lastParsedBrainDump == normalized(brainDump)
    }

    private var reviewEmptyState: BrainDumpReviewEmptyState? {
        guard suggestions.isEmpty else { return nil }
        if hasStaleReview {
            return .needsRefresh
        }
        guard notice == nil else { return nil }
        return lastParsedBrainDump == nil ? .initial : .nothingFound
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
        dismissKeyboard()
        let input = normalized(brainDump)
        isParsing = true
        suggestions = []
        selectedSuggestionIDs = []
        notice = nil
        errorMessage = nil
        validationMessage = nil
        defer { isParsing = false }
        do {
            let result = try await services.parser.parse(input, context: BrainDumpContext())
            notice = result.safetyNotice
            suggestions = result.suggestions
            selectedSuggestionIDs = Set(result.suggestions.map(\.id))
            lastParsedBrainDump = input
            errorMessage = nil
            let count = result.suggestions.count
            if count == 0 {
                announce("No starter cards found.")
            } else {
                announce(count == 1 ? "1 starter card ready to review." : "\(count) starter cards ready to review.")
            }
        } catch {
            lastParsedBrainDump = nil
            errorMessage = (error as? BrainDumpParserError)?.localizedDescription ?? FairNestIssueCopy.brainDumpParseFailure
            announce("First brain dump could not be read.")
        }
    }

    private func saveAndFinish() {
        dismissKeyboard()
        if let blankSuggestion = firstSelectedBlankTitleSuggestion {
            validationMessage = "Add a title for each selected starter card or turn off cards you do not want to save."
            focusedField = .suggestionTitle(blankSuggestion.id)
            announce("Add a title before starting FairNest.")
            return
        }
        let selectedSuggestions = suggestions.filter { suggestion in
            selectedSuggestionIDs.contains(suggestion.id) &&
                !suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        do {
            _ = try cardStore.addReviewed(selectedSuggestions)
            services.completeOnboarding()
            announce("FairNest is ready.")
        } catch {
            errorMessage = FairNestIssueCopy.brainDumpSaveFailure
            announce("Starter cards could not be saved.")
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

    private func dismissKeyboard() {
        focusedField = nil
    }

    private func announce(_ message: String) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }
}
