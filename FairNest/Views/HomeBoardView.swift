import SwiftUI

enum BoardFilter: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "This Week"
    case recurring = "Recurring"
    case decisions = "Decisions"
    case appreciations = "Appreciations"
    case all = "All"

    var id: String { rawValue }
}

struct HomeBoardView: View {
    @EnvironmentObject private var cardStore: LocalCardStore
    @State private var filter: BoardFilter = .today
    @State private var editingCard: LoadCard?
    @State private var showingAdd = false
    @State private var recentlyDeleted: LoadCard?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("View", selection: $filter) {
                        ForEach(BoardFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("boardFilter")
                }

                if filteredCards.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: emptySymbol,
                        description: Text(emptyDescription)
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(filteredCards) { card in
                            CardRow(card: card)
                                .contentShape(Rectangle())
                                .onTapGesture { editingCard = card }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        recentlyDeleted = card
                                        cardStore.delete(id: card.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }

                                    Button {
                                        try? cardStore.transition(id: card.id, to: .done)
                                    } label: {
                                        Label("Done", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        cardStore.snooze(id: card.id, days: 1)
                                    } label: {
                                        Label("Tomorrow", systemImage: "moon")
                                    }
                                    .tint(.indigo)
                                }
                        }
                    }
                }
            }
            .navigationTitle("Home Board")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add card")
                    .accessibilityIdentifier("addCard")
                }
            }
            .sheet(item: $editingCard) { card in
                CardEditorView(card: card) { updated in
                    cardStore.upsert(updated)
                    editingCard = nil
                }
            }
            .sheet(isPresented: $showingAdd) {
                CardEditorView(card: LoadCard(title: "")) { card in
                    cardStore.upsert(card)
                    showingAdd = false
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let recentlyDeleted {
                    HStack {
                        Text("Deleted \(recentlyDeleted.title)")
                            .lineLimit(1)
                        Spacer()
                        Button("Undo") {
                            cardStore.restore(id: recentlyDeleted.id)
                            self.recentlyDeleted = nil
                        }
                    }
                    .font(.footnote)
                    .padding()
                    .background(.bar)
                }
            }
        }
    }

    private var filteredCards: [LoadCard] {
        let active = cardStore.activeCards
        let calendar = Calendar.current
        let now = Date()
        return active.filter { card in
            switch filter {
            case .today:
                return card.isActionableToday
            case .week:
                guard card.status != .done else { return false }
                guard let dueDate = card.dueDate else { return card.status == .inbox || card.status == .doing }
                guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: now) else { return false }
                return dueDate <= weekEnd
            case .recurring:
                return card.recurrence.isRecurring || card.type == .recurringResponsibility
            case .decisions:
                return card.type == .decision
            case .appreciations:
                return card.type == .appreciation
            case .all:
                return true
            }
        }
        .sorted { lhs, rhs in
            if lhs.status == .done, rhs.status != .done { return false }
            if rhs.status == .done, lhs.status != .done { return true }
            switch (lhs.dueDate, rhs.dueDate) {
            case let (left?, right?): return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.updatedAt > rhs.updatedAt
            }
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .today: return "Nothing due today"
        case .week: return "This week is clear"
        case .recurring: return "No recurring responsibilities"
        case .decisions: return "No open decisions"
        case .appreciations: return "No appreciations saved"
        case .all: return "No cards yet"
        }
    }

    private var emptySymbol: String {
        switch filter {
        case .appreciations: return "heart"
        case .decisions: return "questionmark.diamond"
        case .recurring: return "arrow.trianglehead.2.clockwise"
        default: return "checkmark.circle"
        }
    }

    private var emptyDescription: String {
        switch filter {
        case .all:
            "Use Brain Dump or the add button to create your first card."
        default:
            "FairNest will show cards here when they match this view."
        }
    }
}

struct CardRow: View {
    var card: LoadCard

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: card.type.symbolName)
                .font(.title3)
                .foregroundStyle(card.status == .done ? Color.green : Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(card.title.isEmpty ? "Untitled card" : card.title)
                    .font(.headline)
                    .strikethrough(card.status == .done)
                    .lineLimit(3)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        OwnerBadge(owner: card.owner)
                        StatusBadge(status: card.status)
                    }
                    EffortDots(effort: card.effort)
                }

                if let dueDate = card.dueDate {
                    Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Opens this card for editing.")
    }

    private var accessibilitySummary: String {
        var parts = [
            card.title.isEmpty ? "Untitled card" : card.title,
            card.type.label,
            "Owner \(card.owner.label)",
            "Status \(card.status.label)",
            "Effort \(card.effort.label)"
        ]
        if let dueDate = card.dueDate {
            parts.append("Due \(dueDate.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.joined(separator: ", ")
    }
}
