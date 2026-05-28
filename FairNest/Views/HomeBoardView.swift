import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var cardStore: LocalCardStore
    @State private var filter: BoardFilter = .today
    @State private var editingCard: LoadCard?
    @State private var showingAdd = false
    @State private var recentlyDeleted: LoadCard?
    @State private var boardError: BoardOperationError?

    var body: some View {
        NavigationStack {
            List {
                if let boardStatus {
                    BoardStatusRow(status: boardStatus)
                }

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
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: emptySymbol)
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        Button {
                            showingAdd = true
                        } label: {
                            Label("Add Card", systemImage: "plus")
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(filteredCards) { card in
                            CardRow(card: card)
                                .contentShape(Rectangle())
                                .onTapGesture { editingCard = card }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        remove(card)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }

                                    Button {
                                        performBoardOperation("mark this card done") {
                                            try cardStore.transition(id: card.id, to: .done)
                                        }
                                    } label: {
                                        Label("Done", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        performBoardOperation("snooze this card") {
                                            try cardStore.snoozeThrowing(id: card.id, days: 1)
                                        }
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
            .refreshable {
                await services.syncCardsIfAvailable()
            }
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
                    try cardStore.upsertThrowing(updated)
                    editingCard = nil
                }
            }
            .sheet(isPresented: $showingAdd) {
                CardEditorView(card: LoadCard(title: "")) { card in
                    try cardStore.upsertThrowing(card)
                    showingAdd = false
                }
            }
            .alert(item: $boardError) { error in
                Alert(
                    title: Text("Board update failed"),
                    message: Text(error.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .safeAreaInset(edge: .bottom) {
                if let recentlyDeleted {
                    HStack {
                        Text("Removed \(recentlyDeleted.title)")
                            .lineLimit(2)
                        Spacer()
                        Button("Undo") {
                            restore(recentlyDeleted)
                        }
                        .accessibilityLabel("Undo remove \(recentlyDeleted.title)")
                    }
                    .font(.footnote)
                    .padding()
                    .background(.bar)
                }
            }
        }
    }

    private var boardStatus: BoardStatus? {
        if let message = cardStore.lastLoadErrorMessage {
            return BoardStatus(message: message, symbol: "exclamationmark.triangle", tint: .red)
        }
        if let message = cardStore.lastPersistenceErrorMessage {
            return BoardStatus(message: message, symbol: "externaldrive.badge.exclamationmark", tint: .red)
        }
        if services.iCloudSyncEnabled, let message = services.lastSyncMessage {
            return BoardStatus(message: "iCloud sync needs attention: \(message)", symbol: "icloud.slash", tint: .orange)
        }
        if services.iCloudSyncEnabled, services.syncInProgress {
            return BoardStatus(message: "Syncing household cards with iCloud.", symbol: "arrow.triangle.2.circlepath.icloud", tint: Color.secondary)
        }
        return nil
    }

    private func remove(_ card: LoadCard) {
        performBoardOperation("remove this card") {
            try cardStore.deleteThrowing(id: card.id)
            recentlyDeleted = card
            announce("Removed \(card.title). Undo is available.")
        }
    }

    private func restore(_ card: LoadCard) {
        performBoardOperation("restore this card") {
            try cardStore.restoreThrowing(id: card.id)
            recentlyDeleted = nil
            announce("Restored \(card.title).")
        }
    }

    private func performBoardOperation(_ actionDescription: String, _ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            boardError = BoardOperationError(message: "FairNest could not \(actionDescription). \(error.localizedDescription)")
            announce("Board update failed.")
        }
    }

    private func announce(_ message: String) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var card: LoadCard

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: card.type.symbolName)
                .font(.title2)
                .foregroundStyle(card.status == .done ? Color.green : Color.accentColor)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(card.title.isEmpty ? "Untitled card" : card.title)
                    .font(.headline)
                    .strikethrough(card.status == .done)
                    .lineLimit(3)

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        OwnerBadge(owner: card.owner)
                        StatusBadge(status: card.status)
                        EffortDots(effort: card.effort)
                    }
                } else {
                    HStack(spacing: 10) {
                        OwnerBadge(owner: card.owner)
                        StatusBadge(status: card.status)
                        EffortDots(effort: card.effort)
                    }
                }

                if let dueDate = card.dueDate {
                    Label(dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
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

private struct BoardOperationError: Identifiable {
    let id = UUID()
    let message: String
}

private struct BoardStatus {
    var message: String
    var symbol: String
    var tint: Color
}

private struct BoardStatusRow: View {
    var status: BoardStatus

    var body: some View {
        Section {
            Label(status.message, systemImage: status.symbol)
                .font(.footnote)
                .foregroundStyle(status.tint)
                .accessibilityIdentifier("boardStatusMessage")
        }
    }
}
