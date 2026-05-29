import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum WeeklyCheckInFocus: Hashable {
    case feltHeavy
    case gotDone
    case needsOwnership
    case appreciation
    case ownershipTitle(UUID)
}

struct WeeklyCheckInView: View {
    @EnvironmentObject private var cardStore: LocalCardStore
    @EnvironmentObject private var checkInStore: LocalCheckInStore
    @State private var step = 0
    @State private var draft = WeeklyCheckInDraft()
    @State private var changes: [OwnershipChange] = []
    @State private var saved = false
    @State private var saveErrorMessage: String?
    @State private var saveErrorDetails: String?
    @State private var showsEmptyCheckInConfirmation = false
    @FocusState private var focusedPrompt: WeeklyCheckInFocus?

    private let steps = [
        "What felt heavy",
        "What got done",
        "Needs ownership",
        "One appreciation",
        "Confirm changes"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProgressView(value: Double(step + 1), total: Double(steps.count))
                        .accessibilityLabel("Check-in progress")
                        .accessibilityValue("Step \(step + 1) of \(steps.count)")
                    Text(steps[step])
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                }

                if let checkInStoreStatus {
                    CheckInStoreStatusRow(status: checkInStoreStatus)
                }

                currentStep
            }
            .navigationTitle("Weekly Check-In")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !saved {
                        Button("Back") {
                            goBack()
                        }
                        .disabled(step == 0)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(primaryActionTitle) {
                        advance()
                    }
                    .accessibilityIdentifier("checkInNext")
                }

            }
            .alert("Save Empty Check-In?", isPresented: $showsEmptyCheckInConfirmation) {
                Button("Save Empty Check-In") {
                    save()
                }

                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("This will save a blank local reflection with no board changes.")
            }
        }
    }

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case 0:
            promptSection(
                text: $draft.feltHeavy,
                prompt: "Name the household work that felt heavy this week.",
                placeholder: "Example: meal planning, laundry backlog, remembering appointments",
                identifier: "checkInFeltHeavy",
                focus: .feltHeavy
            )
        case 1:
            promptSection(
                text: $draft.gotDone,
                prompt: "Capture what got done.",
                placeholder: "Example: bills paid, fridge cleaned, birthday gift ordered",
                identifier: "checkInGotDone",
                focus: .gotDone
            )
        case 2:
            promptSection(
                text: $draft.needsOwnership,
                prompt: "Name one to three things that need clearer ownership.",
                placeholder: "Example: partner owns trash night; I own school forms",
                identifier: "checkInNeedsOwnership",
                focus: .needsOwnership
            )
        case 3:
            promptSection(
                text: $draft.appreciation,
                prompt: "Save one appreciation.",
                placeholder: "Example: Thanks for handling dinner on Tuesday",
                identifier: "checkInAppreciation",
                focus: .appreciation
            )
        default:
            confirmSection
        }
    }

    private func promptSection(
        text: Binding<String>,
        prompt: String,
        placeholder: String,
        identifier: String,
        focus: WeeklyCheckInFocus
    ) -> some View {
        Section {
            Text(prompt)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextEditor(text: text)
                .focused($focusedPrompt, equals: focus)
                .frame(minHeight: 140)
                .accessibilityLabel(prompt)
                .accessibilityHint(placeholder)
                .accessibilityIdentifier(identifier)
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
    }

    @ViewBuilder
    private var confirmSection: some View {
        if saved {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Check-in saved")
                            .font(.headline)
                        Text("Your reflection is saved locally and reviewed ownership changes are on the board.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Button {
                    reset()
                } label: {
                    Label("Start New Check-In", systemImage: "plus.circle")
                }
            }
        } else {
            Section {
                if changes.isEmpty {
                    ReviewEmptyStateRow(
                        title: isEmptyCheckIn ? "Empty check-in" : "No ownership changes",
                        systemImage: "checkmark.circle",
                        message: isEmptyCheckIn ? "You can save an empty reflection, or go back and add notes first." : "The check-in can still be saved with no board changes."
                    )
                } else {
                    ForEach($changes) { changeBinding in
                        OwnershipChangeReviewRow(change: changeBinding, focusedPrompt: $focusedPrompt) {
                            let id = changeBinding.wrappedValue.id
                            changes.removeAll { $0.id == id }
                            saveErrorMessage = nil
                        }
                    }
                }

                Button {
                    let change = OwnershipChange(title: "", owner: .shared, reason: "Reviewed in the weekly check-in.")
                    changes.append(change)
                    saveErrorMessage = nil
                    focusedPrompt = .ownershipTitle(change.id)
                } label: {
                    Label("Add Ownership Change", systemImage: "plus")
                }

                if hasBlankOwnershipChange {
                    Label("Add a responsibility for each ownership change or remove blank changes.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("checkInValidationMessage")
                }

                if !draft.appreciation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(draft.appreciation, systemImage: "heart")
                }

                if let saveErrorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(saveErrorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        if let saveErrorDetails {
                            TechnicalDetailsDisclosure(details: saveErrorDetails)
                        }
                    }
                }
            } header: {
                Text("Review changes")
            } footer: {
                Text("Only the changes listed here will update the board. Remove anything that does not look right.")
            }
        }
    }

    private func goBack() {
        dismissKeyboard()
        step = max(0, step - 1)
        saveErrorMessage = nil
    }

    private func advance() {
        dismissKeyboard()
        if saved {
            reset()
            return
        }

        if step == 3 {
            changes = WeeklyCheckInEngine.generateChanges(from: draft, cards: cardStore.activeCards)
            saveErrorMessage = nil
            step += 1
            announce("Review changes.")
            return
        }

        if step == steps.count - 1 {
            if let blankChange = firstBlankOwnershipChange {
                saveErrorMessage = "Add a responsibility for each ownership change, or remove blank changes before saving."
                saveErrorDetails = nil
                focusedPrompt = .ownershipTitle(blankChange.id)
                announce("Add a responsibility before saving.")
                return
            }
            if requiresEmptyCheckInConfirmation {
                showsEmptyCheckInConfirmation = true
                return
            }
            save()
            return
        }

        step += 1
        announce(steps[step])
    }

    private func save() {
        guard !saved else { return }
        guard !checkInStore.isUnavailableDueToLoadFailure else {
            saveErrorMessage = FairNestIssueCopy.localCheckInReadUnavailable
            saveErrorDetails = checkInStore.lastLoadErrorMessage
            return
        }
        let finalChanges = reviewedChanges
        let record = CheckInRecord(
            feltHeavy: draft.feltHeavy.trimmingCharacters(in: .whitespacesAndNewlines),
            gotDone: draft.gotDone.trimmingCharacters(in: .whitespacesAndNewlines),
            needsOwnership: draft.needsOwnership.trimmingCharacters(in: .whitespacesAndNewlines),
            appreciation: draft.appreciation.trimmingCharacters(in: .whitespacesAndNewlines),
            changes: finalChanges
        )

        let previousCards = cardStore.cards
        let updatedCards = WeeklyCheckInEngine.cardsAfterApplying(finalChanges, to: previousCards)

        do {
            if updatedCards != previousCards {
                try cardStore.replaceAllThrowing(with: updatedCards)
            }

            do {
                try checkInStore.save(record)
            } catch {
                try WeeklyCheckInSaveCoordinator.handleCheckInSaveFailure(
                    previousCards: previousCards,
                    updatedCards: updatedCards,
                    originalError: error
                ) {
                    try cardStore.replaceAllThrowing(with: previousCards)
                }
            }

            changes = finalChanges
            saved = true
            saveErrorMessage = nil
            saveErrorDetails = nil
            announce("Check-in saved.")
        } catch {
            saveErrorMessage = FairNestIssueCopy.localCheckInSaveFailure
            saveErrorDetails = error.localizedDescription
            announce("Check-in could not be saved.")
        }
    }

    private var primaryActionTitle: String {
        if saved && step == steps.count - 1 {
            return "New"
        }
        return step == steps.count - 1 ? "Save" : "Next"
    }

    private var reviewedChanges: [OwnershipChange] {
        changes.compactMap { change in
            let title = change.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let reason = change.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return OwnershipChange(
                id: change.id,
                title: title,
                owner: change.owner,
                reason: reason.isEmpty ? "Reviewed in the weekly check-in." : reason
            )
        }
    }

    private var isEmptyCheckIn: Bool {
        [
            draft.feltHeavy,
            draft.gotDone,
            draft.needsOwnership,
            draft.appreciation
        ].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var firstBlankOwnershipChange: OwnershipChange? {
        changes.first { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var hasBlankOwnershipChange: Bool {
        firstBlankOwnershipChange != nil
    }

    private var requiresEmptyCheckInConfirmation: Bool {
        isEmptyCheckIn && reviewedChanges.isEmpty
    }

    private var checkInStoreStatus: CheckInStoreStatus? {
        if let message = checkInStore.lastLoadErrorMessage {
            return CheckInStoreStatus(
                title: checkInStore.isUnavailableDueToLoadFailure ? "Check-ins need attention" : "Previous check-ins were repaired",
                message: checkInStore.isUnavailableDueToLoadFailure ? FairNestIssueCopy.localCheckInReadUnavailable : FairNestIssueCopy.localCheckInLoadFailure,
                symbol: checkInStore.isUnavailableDueToLoadFailure ? "exclamationmark.triangle" : "checkmark.circle",
                tint: checkInStore.isUnavailableDueToLoadFailure ? .red : .orange,
                technicalDetails: message
            )
        }
        if let message = checkInStore.lastPersistenceErrorMessage {
            return CheckInStoreStatus(
                title: "Check-in is not saved yet",
                message: FairNestIssueCopy.localCheckInSaveFailure,
                symbol: "externaldrive.badge.exclamationmark",
                tint: .red,
                technicalDetails: message
            )
        }
        return nil
    }

    private func dismissKeyboard() {
        focusedPrompt = nil
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private func announce(_ message: String) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }

    private func reset() {
        step = 0
        draft = WeeklyCheckInDraft()
        changes = []
        saved = false
        saveErrorMessage = nil
        saveErrorDetails = nil
        showsEmptyCheckInConfirmation = false
        focusedPrompt = nil
    }
}

private struct CheckInStoreStatus {
    var title: String
    var message: String
    var symbol: String
    var tint: Color
    var technicalDetails: String
}

private struct CheckInStoreStatusRow: View {
    var status: CheckInStoreStatus

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(status.title, systemImage: status.symbol)
                    .font(.headline)
                    .foregroundStyle(status.tint)
                Text(status.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TechnicalDetailsDisclosure(details: status.technicalDetails)
            }
            .accessibilityIdentifier("checkInStoreStatusMessage")
        }
    }
}

private struct OwnershipChangeReviewRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var change: OwnershipChange
    var focusedPrompt: FocusState<WeeklyCheckInFocus?>.Binding
    var onDelete: () -> Void

    private let owners: [CardOwner] = [.me, .partner, .shared]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Responsibility", text: $change.title, axis: .vertical)
                .focused(focusedPrompt, equals: .ownershipTitle(change.id))
                .font(.headline)
                .accessibilityLabel("Responsibility for ownership change")
                .accessibilityIdentifier("checkInOwnershipTitle")

            ownerPicker
                .accessibilityIdentifier("checkInOwnershipOwner")

            Text(change.reason)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove Change", systemImage: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var ownerPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Owner", selection: $change.owner) {
                ForEach(owners) { owner in
                    Label(owner.label, systemImage: owner.symbolName).tag(owner)
                }
            }
            .pickerStyle(.menu)
        } else {
            Picker("Owner", selection: $change.owner) {
                ForEach(owners) { owner in
                    Text(owner.label).tag(owner)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
