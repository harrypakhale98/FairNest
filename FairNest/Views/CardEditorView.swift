import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum CardEditorFocus: Hashable {
    case title
    case doneCriteria
    case notes
}

struct CardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var card: LoadCard
    @State private var hasDueDate: Bool
    @State private var showingDiscardConfirmation = false
    @State private var saveErrorMessage: String?
    @State private var saveErrorDetails: String?
    @FocusState private var focusedField: CardEditorFocus?
    @AccessibilityFocusState private var saveErrorFocused: Bool
    private let originalCard: LoadCard
    var onSave: (LoadCard) throws -> Void

    init(card: LoadCard, onSave: @escaping (LoadCard) throws -> Void) {
        _card = State(initialValue: card)
        _hasDueDate = State(initialValue: card.dueDate != nil)
        self.originalCard = card
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $card.title, axis: .vertical)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.done)
                        .accessibilityIdentifier("cardTitle")

                    Picker("Type", selection: $card.type) {
                        ForEach(CardType.allCases) { type in
                            Label(type.label, systemImage: type.symbolName).tag(type)
                        }
                    }

                    Picker("Owner", selection: $card.owner) {
                        ForEach(CardOwner.allCases) { owner in
                            Text(owner.label).tag(owner)
                        }
                    }

                    Picker("Status", selection: $card.status) {
                        ForEach(statusOptions) { status in
                            Text(status.label).tag(status)
                        }
                    }
                } header: {
                    Text("Card")
                } footer: {
                    if card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("A card needs a title before it can be saved.")
                            .accessibilityIdentifier("cardTitleValidation")
                    }
                }

                Section {
                    Picker("Effort", selection: $card.effort) {
                        ForEach(Effort.allCases) { effort in
                            Text(effort.label).tag(effort)
                        }
                    }

                    Toggle("Due date", isOn: dueDateEnabled)

                    if hasDueDate {
                        DatePicker(
                            "When",
                            selection: Binding(
                                get: { card.dueDate ?? Date() },
                                set: { card.dueDate = $0 }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    Picker("Recurrence", selection: recurrenceBinding) {
                        ForEach(recurrenceOptions, id: \.self) { recurrence in
                            Text(recurrence.label).tag(recurrence)
                        }
                    }
                } header: {
                    Text("Timing")
                }

                Section {
                    TextField("Done criteria", text: $card.doneCriteria, axis: .vertical)
                        .focused($focusedField, equals: .doneCriteria)
                        .submitLabel(.done)
                    TextField("Notes", text: $card.notes, axis: .vertical)
                        .focused($focusedField, equals: .notes)
                        .submitLabel(.done)
                } header: {
                    Text("Details")
                }

                if let saveErrorMessage {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(saveErrorMessage, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .accessibilityElement(children: .ignore)
                                .accessibilityIdentifier("cardSaveError")
                                .accessibilityLabel("Card save error: \(saveErrorMessage)")
                                .accessibilityFocused($saveErrorFocused)
                            if let saveErrorDetails {
                                TechnicalDetailsDisclosure(details: saveErrorDetails)
                            }
                        }
                    }
                }
            }
            .navigationTitle(card.title.isEmpty ? "New Card" : "Edit Card")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveCard")
                    .accessibilityHint(card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter a title before saving." : "Saves this card.")
                }
            }
            .onChange(of: card) { _, _ in
                saveErrorMessage = nil
                saveErrorDetails = nil
                saveErrorFocused = false
            }
            .task {
                guard originalCard.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                focusedField = .title
            }
            .interactiveDismissDisabled(isDirty)
            .confirmationDialog(
                "Discard unsaved changes?",
                isPresented: $showingDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
        }
    }

    private func save() {
        do {
            try onSave(card)
        } catch let error as CardTransitionError {
            saveErrorMessage = FairNestIssueCopy.invalidCardStatusTransition
            saveErrorDetails = error.localizedDescription
            announce(FairNestIssueCopy.invalidCardStatusTransition)
            Task { @MainActor in
                await Task.yield()
                saveErrorFocused = true
            }
        } catch {
            saveErrorMessage = FairNestIssueCopy.localCardSaveFailure
            saveErrorDetails = error.localizedDescription
            announce(FairNestIssueCopy.localCardSaveFailure)
            Task { @MainActor in
                await Task.yield()
                saveErrorFocused = true
            }
        }
    }

    private var statusOptions: [CardStatus] {
        originalCard.status.allowedEditorTransitions
    }

    private var isDirty: Bool {
        card != originalCard
    }

    private func cancel() {
        if isDirty {
            showingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private var recurrenceBinding: Binding<Recurrence> {
        Binding(
            get: { card.recurrence },
            set: { card.recurrence = $0 }
        )
    }

    private var dueDateEnabled: Binding<Bool> {
        Binding(
            get: { hasDueDate },
            set: { enabled in
                hasDueDate = enabled
                card.dueDate = enabled ? (card.dueDate ?? Date()) : nil
            }
        )
    }

    private var recurrenceOptions: [Recurrence] {
        var options: [Recurrence] = [.none, .daily]
        let calendar = Calendar.current
        let date = card.dueDate ?? Date()
        options.append(.weekly(weekday: calendar.component(.weekday, from: date)))
        options.append(.monthly(day: calendar.component(.day, from: date)))
        if !options.contains(card.recurrence) {
            options.append(card.recurrence)
        }
        return options
    }

    private func announce(_ message: String) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }
}
