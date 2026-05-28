import SwiftUI

struct WeeklyCheckInView: View {
    @EnvironmentObject private var cardStore: LocalCardStore
    @EnvironmentObject private var checkInStore: LocalCheckInStore
    @State private var step = 0
    @State private var draft = WeeklyCheckInDraft()
    @State private var changes: [OwnershipChange] = []
    @State private var saved = false

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
                    Text(steps[step])
                        .font(.headline)
                }

                currentStep
            }
            .navigationTitle("Weekly Check-In")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") {
                        step = max(0, step - 1)
                    }
                    .disabled(step == 0)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(saved && step == steps.count - 1 ? "Saved" : step == steps.count - 1 ? "Finish" : "Next") {
                        advance()
                    }
                    .disabled(saved && step == steps.count - 1)
                    .accessibilityIdentifier("checkInNext")
                }
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
                placeholder: "Example: meal planning, laundry backlog, remembering appointments"
            )
        case 1:
            promptSection(
                text: $draft.gotDone,
                prompt: "Capture what got done.",
                placeholder: "Example: bills paid, fridge cleaned, birthday gift ordered"
            )
        case 2:
            promptSection(
                text: $draft.needsOwnership,
                prompt: "Name one to three things that need clearer ownership.",
                placeholder: "Example: partner owns trash night; I own school forms"
            )
        case 3:
            promptSection(
                text: $draft.appreciation,
                prompt: "Save one appreciation.",
                placeholder: "Example: Thanks for handling dinner on Tuesday"
            )
        default:
            confirmSection
        }
    }

    private func promptSection(text: Binding<String>, prompt: String, placeholder: String) -> some View {
        Section {
            Text(prompt)
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .frame(minHeight: 140)
                .accessibilityLabel(prompt)
                .accessibilityHint(placeholder)
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var confirmSection: some View {
        Section {
            if changes.isEmpty {
                ContentUnavailableView(
                    "No ownership changes",
                    systemImage: "checkmark.circle",
                    description: Text("The check-in can still be saved with no changes.")
                )
            } else {
                ForEach(changes) { change in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(change.title)
                            .font(.headline)
                        Text("\(change.owner.label) owns this")
                            .foregroundStyle(.secondary)
                        Text(change.reason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !draft.appreciation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(draft.appreciation, systemImage: "heart")
            }

            if saved {
                Label("Check-in saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } header: {
            Text("1-3 concrete changes")
        } footer: {
            Text("FairNest keeps this practical: ownership changes only, no diagnosis or advice.")
        }
    }

    private func advance() {
        if step == 3 {
            changes = WeeklyCheckInEngine.generateChanges(from: draft, cards: cardStore.activeCards)
            step += 1
            return
        }

        if step == steps.count - 1 {
            save()
            return
        }

        step += 1
    }

    private func save() {
        guard !saved else { return }
        let record = CheckInRecord(
            feltHeavy: draft.feltHeavy,
            gotDone: draft.gotDone,
            needsOwnership: draft.needsOwnership,
            appreciation: draft.appreciation,
            changes: changes
        )
        checkInStore.save(record)
        apply(changes)
        saved = true
    }

    private func apply(_ changes: [OwnershipChange]) {
        for change in changes {
            let changeTitle = change.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !changeTitle.isEmpty else { continue }
            if let match = cardStore.activeCards.first(where: { card in titlesMatch(card.title, changeTitle) }) {
                cardStore.reassign(id: match.id, to: change.owner)
            } else {
                let suggestion = BrainDumpSuggestion(
                    title: changeTitle,
                    type: .task,
                    owner: change.owner,
                    effort: .medium,
                    doneCriteria: "Ownership is clear for this week."
                )
                _ = cardStore.add(suggestion)
            }
        }
    }

    private func titlesMatch(_ cardTitle: String, _ changeTitle: String) -> Bool {
        let normalizedCardTitle = cardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCardTitle.isEmpty else { return false }
        return normalizedCardTitle.localizedCaseInsensitiveContains(changeTitle) ||
            changeTitle.localizedCaseInsensitiveContains(normalizedCardTitle)
    }
}
