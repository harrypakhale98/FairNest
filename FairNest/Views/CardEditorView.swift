import SwiftUI

struct CardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var card: LoadCard
    @State private var hasDueDate: Bool
    @State private var showingDiscardConfirmation = false
    private let originalCard: LoadCard
    var onSave: (LoadCard) -> Void

    init(card: LoadCard, onSave: @escaping (LoadCard) -> Void) {
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
                        Text("None").tag(Recurrence.none)
                        Text("Daily").tag(Recurrence.daily)
                        Text("Weekly").tag(Recurrence.weekly(weekday: Calendar.current.component(.weekday, from: Date())))
                        Text("Monthly").tag(Recurrence.monthly(day: Calendar.current.component(.day, from: Date())))
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
            }
            .navigationTitle(card.title.isEmpty ? "New Card" : "Edit Card")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        card.updatedAt = Date()
                        onSave(card)
                    }
                    .disabled(card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveCard")
                }
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
}
