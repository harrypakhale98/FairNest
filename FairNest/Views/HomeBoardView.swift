import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum BoardFilter: String, CaseIterable, Identifiable {
    case today = "Today + Overdue"
    case week = "This Week"
    case recurring = "Recurring"
    case decisions = "Decisions"
    case appreciations = "Appreciations"
    case all = "All"

    var id: String { rawValue }
}

enum BoardEmptyAction: Equatable {
    case addCard
    case brainDump
    case showAll

    var accessibilityIdentifier: String {
        switch self {
        case .addCard: return "emptyAddCard"
        case .brainDump: return "emptyBrainDump"
        case .showAll: return "showAllCards"
        }
    }
}

struct BoardEmptyState: Equatable {
    var title: String
    var symbol: String
    var description: String
    var actionTitle: String
    var actionSymbol: String
    var action: BoardEmptyAction
    var secondaryActionTitle: String?
    var secondaryActionSymbol: String?
    var secondaryAction: BoardEmptyAction?

    static func make(filter: BoardFilter, activeCardCount: Int) -> BoardEmptyState {
        if activeCardCount == 0 {
            return BoardEmptyState(
                title: "No cards yet",
                symbol: "text.badge.plus",
                description: "Start with a quick Brain Dump, or add one card manually.",
                actionTitle: "Brain Dump",
                actionSymbol: "text.badge.plus",
                action: .brainDump,
                secondaryActionTitle: "Add Card",
                secondaryActionSymbol: "plus",
                secondaryAction: .addCard
            )
        }

        if activeCardCount > 0, filter != .all {
            let noun = activeCardCount == 1 ? "card" : "cards"
            return BoardEmptyState(
                title: "No cards in this view",
                symbol: "tray",
                description: "You have \(activeCardCount) \(noun) in other views.",
                actionTitle: "Show All",
                actionSymbol: "rectangle.stack",
                action: .showAll,
                secondaryActionTitle: nil,
                secondaryActionSymbol: nil,
                secondaryAction: nil
            )
        }

        return BoardEmptyState(
            title: filter.defaultEmptyTitle,
            symbol: filter.defaultEmptySymbol,
            description: filter.defaultEmptyDescription,
            actionTitle: "Add Card",
            actionSymbol: "plus",
            action: .addCard,
            secondaryActionTitle: nil,
            secondaryActionSymbol: nil,
            secondaryAction: nil
        )
    }
}

struct HomeBoardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var cardStore: LocalCardStore
    @State private var filter: BoardFilter = .today
    @State private var editingCard: LoadCard?
    @State private var showingAdd = false
    @State private var recentlyDeleted: RecentlyDeletedCard?
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

                if filteredCards.isEmpty, !isCardStoreUnavailable {
                    Section {
                        BoardEmptyRow(
                            state: emptyState
                        ) {
                            handleEmptyAction(emptyState.action)
                        } secondaryAction: {
                            if let action = emptyState.secondaryAction {
                                handleEmptyAction(action)
                            }
                        }
                    }
                } else {
                    Section {
                        ForEach(filteredCards) { card in
                            HStack(spacing: 8) {
                                Button {
                                    editingCard = card
                                } label: {
                                    CardRow(
                                        card: card,
                                        showsDisclosureIndicator: !dynamicTypeSize.isAccessibilitySize
                                    )
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .accessibilityAction(named: "Mark Done") {
                                    markDone(card)
                                }
                                .accessibilityAction(named: "Snooze until Tomorrow") {
                                    snooze(card)
                                }
                                .accessibilityAction(named: "Remove") {
                                    remove(card)
                                }

                                if dynamicTypeSize.isAccessibilitySize {
                                    CardActionMenu(
                                        cardTitle: card.displayTitle,
                                        onDone: { markDone(card) },
                                        onSnooze: { snooze(card) },
                                        onRemove: { remove(card) }
                                    )
                                }
                            }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        remove(card)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }

                                    Button {
                                        markDone(card)
                                    } label: {
                                        Label("Done", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        snooze(card)
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
            .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .automatic)
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
                    .disabled(isCardStoreUnavailable)
                }
            }
            .sheet(item: $editingCard) { card in
                CardEditorView(card: card) { updated in
                    try cardStore.upsertThrowing(updated, expectedRevision: CardRevision(card: card))
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
                        Text("Removed \(recentlyDeleted.card.displayTitle)")
                            .lineLimit(2)
                        Spacer()
                        Button("Undo") {
                            restore(recentlyDeleted)
                        }
                        .accessibilityLabel("Undo remove \(recentlyDeleted.card.displayTitle)")
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
            return BoardStatus(
                title: "Local cards need attention",
                message: cardStore.isUnavailableDueToLoadFailure ? FairNestIssueCopy.localCardReadUnavailable : FairNestIssueCopy.localCardLoadFailure,
                symbol: "exclamationmark.triangle",
                tint: .red,
                actionTitle: nil,
                technicalDetails: message
            )
        }
        if let message = cardStore.lastPersistenceErrorMessage {
            return BoardStatus(
                title: "Changes are not saved yet",
                message: FairNestIssueCopy.localCardSaveFailure,
                symbol: "externaldrive.badge.exclamationmark",
                tint: .red,
                actionTitle: nil,
                technicalDetails: message
            )
        }
        if let message = services.lastSyncMessage {
            return BoardStatus(
                title: services.iCloudSyncEnabled ? "iCloud sync needs attention" : "iCloud sync was turned off",
                message: services.iCloudSyncEnabled ? FairNestIssueCopy.syncDelay : message,
                symbol: "icloud.slash",
                tint: .orange,
                actionTitle: services.iCloudSyncEnabled ? "Retry Sync" : nil,
                technicalDetails: services.iCloudSyncEnabled ? message : nil
            )
        }
        if services.iCloudSyncEnabled, services.syncInProgress {
            return BoardStatus(
                title: "Syncing",
                message: "FairNest is syncing household cards with iCloud.",
                symbol: "arrow.triangle.2.circlepath.icloud",
                tint: Color.secondary,
                actionTitle: nil,
                technicalDetails: nil
            )
        }
        return nil
    }

    private var isCardStoreUnavailable: Bool {
        cardStore.isUnavailableDueToLoadFailure
    }

    private func markDone(_ card: LoadCard) {
        performBoardOperation("mark this card done") {
            try cardStore.transition(id: card.id, to: .done)
        }
    }

    private func snooze(_ card: LoadCard) {
        performBoardOperation("snooze this card") {
            try cardStore.snoozeThrowing(id: card.id, days: 1)
        }
    }

    private func remove(_ card: LoadCard) {
        performBoardOperation("remove this card") {
            try cardStore.deleteThrowing(id: card.id)
            recentlyDeleted = RecentlyDeletedCard(
                card: card,
                deletedAt: cardStore.cards.first(where: { $0.id == card.id })?.deletedAt
            )
            announce("Removed \(card.displayTitle). Undo restores the most recent removed card.")
        }
    }

    private func restore(_ recentlyDeleted: RecentlyDeletedCard) {
        performBoardOperation("restore this card") {
            try cardStore.restoreThrowing(
                recentlyDeleted.card,
                matchingDeletedAt: recentlyDeleted.deletedAt
            )
            self.recentlyDeleted = nil
            announce("Restored \(recentlyDeleted.card.displayTitle).")
        }
    }

    private func performBoardOperation(_ actionDescription: String, _ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            boardError = BoardOperationError(message: FairNestIssueCopy.boardOperationFailure(actionDescription: actionDescription))
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
        return active
            .filter { filter.includes($0, now: now, calendar: calendar) }
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

    private var emptyState: BoardEmptyState {
        BoardEmptyState.make(filter: filter, activeCardCount: cardStore.activeCards.count)
    }

    private func handleEmptyAction(_ action: BoardEmptyAction) {
        guard !isCardStoreUnavailable else {
            boardError = BoardOperationError(message: FairNestIssueCopy.localCardReadUnavailable)
            return
        }
        switch action {
        case .addCard:
            showingAdd = true
        case .brainDump:
            NotificationCenter.default.post(name: .fairNestOpenBrainDump, object: nil)
        case .showAll:
            filter = .all
        }
    }
}

extension BoardFilter {
    func includes(_ card: LoadCard, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
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
            return card.status != .done && card.type == .decision
        case .appreciations:
            return card.type == .appreciation
        case .all:
            return true
        }
    }

    var defaultEmptyTitle: String {
        switch self {
        case .today: return "Nothing due now"
        case .week: return "This week is clear"
        case .recurring: return "No recurring responsibilities"
        case .decisions: return "No open decisions"
        case .appreciations: return "No appreciations saved"
        case .all: return "No cards yet"
        }
    }

    var defaultEmptySymbol: String {
        switch self {
        case .appreciations: return "heart"
        case .decisions: return "questionmark.diamond"
        case .recurring: return "arrow.trianglehead.2.clockwise"
        default: return "checkmark.circle"
        }
    }

    var defaultEmptyDescription: String {
        switch self {
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
    var showsDisclosureIndicator = true

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

            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
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
            card.displayTitle,
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

private struct CardActionMenu: View {
    var cardTitle: String
    var onDone: () -> Void
    var onSnooze: () -> Void
    var onRemove: () -> Void

    var body: some View {
        Menu {
            Button {
                onDone()
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            Button {
                onSnooze()
            } label: {
                Label("Tomorrow", systemImage: "moon")
            }
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
        .accessibilityLabel("Actions for \(cardTitle)")
    }
}

private extension LoadCard {
    var displayTitle: String {
        title.isEmpty ? "Untitled card" : title
    }
}

private struct BoardOperationError: Identifiable {
    let id = UUID()
    let message: String
}

private struct RecentlyDeletedCard {
    var card: LoadCard
    var deletedAt: Date?
}

private struct BoardStatus {
    var title: String
    var message: String
    var symbol: String
    var tint: Color
    var actionTitle: String?
    var technicalDetails: String?
}

private struct BoardStatusRow: View {
    var status: BoardStatus
    @EnvironmentObject private var services: AppServices

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(status.title, systemImage: status.symbol)
                    .font(.headline)
                    .foregroundStyle(status.tint)
                Text(status.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let technicalDetails = status.technicalDetails {
                    TechnicalDetailsDisclosure(details: technicalDetails)
                }
                if let actionTitle = status.actionTitle {
                    Button {
                        Task { await services.syncCardsIfAvailable() }
                    } label: {
                        Label(actionTitle, systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .accessibilityIdentifier("boardStatusMessage")
        }
    }
}

private struct BoardEmptyRow: View {
    var state: BoardEmptyState
    var onAction: () -> Void
    var secondaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(state.title)
                    .font(.headline)
            } icon: {
                Image(systemName: state.symbol)
                    .foregroundStyle(.tint)
            }

            Text(state.description)
                .font(.body)
                .foregroundStyle(.secondary)

            Button {
                onAction()
            } label: {
                Label(state.actionTitle, systemImage: state.actionSymbol)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(state.action.accessibilityIdentifier)

            if let title = state.secondaryActionTitle,
               let symbol = state.secondaryActionSymbol,
               let action = state.secondaryAction {
                Button {
                    secondaryAction()
                } label: {
                    Label(title, systemImage: symbol)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier(action.accessibilityIdentifier)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
