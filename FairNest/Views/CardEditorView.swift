import SwiftUI

struct CardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var card: LoadCard
    @State private var hasDueDate: Bool
    @State private var showingDiscardConfirmation = false
    @State private var saveErrorMessage: String?
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
                        ForEach(CardStatus.allCases) { status in
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
                    TextField("Notes", text: $card.notes, axis: .vertical)
                } header: {
                    Text("Details")
                }

                if let saveErrorMessage {
                    Section {
                        Label(saveErrorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("cardSaveError")
                    }
                }
            }
            .navigationTitle(card.title.isEmpty ? "New Card" : "Edit Card")
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
        } catch {
            saveErrorMessage = error.localizedDescription
        }
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
}
