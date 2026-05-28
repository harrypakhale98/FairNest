import AppIntents
import SwiftUI
import WidgetKit

struct FairNestWidgetEntry: TimelineEntry {
    var date: Date
    var configuration: FairNestWidgetIntent
    var snapshot: WidgetHouseholdSnapshot
    var redacted: Bool = false
}

struct FairNestTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FairNestWidgetEntry {
        FairNestWidgetEntry(
            date: Date(),
            configuration: FairNestWidgetIntent(),
            snapshot: sampleSnapshot(),
            redacted: true
        )
    }

    func snapshot(for configuration: FairNestWidgetIntent, in context: Context) async -> FairNestWidgetEntry {
        FairNestWidgetEntry(date: Date(), configuration: configuration, snapshot: WidgetSnapshotStore.read())
    }

    func timeline(for configuration: FairNestWidgetIntent, in context: Context) async -> Timeline<FairNestWidgetEntry> {
        let now = Date()
        let snapshot = WidgetSnapshotStore.read()
        let entries = FairNestTimelineBuilder.entries(now: now, configuration: configuration, snapshot: snapshot)
        return Timeline(entries: entries, policy: .after(Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)))
    }

    private func sampleSnapshot() -> WidgetHouseholdSnapshot {
        WidgetHouseholdSnapshot(
            generatedAt: Date(),
            syncPending: false,
            cards: [
                WidgetCardSummary(id: UUID(), type: .recurringResponsibility, owner: .shared, effort: .light, dueDate: Date(), status: .planned),
                WidgetCardSummary(id: UUID(), type: .decision, owner: .me, effort: .medium, dueDate: Date(), status: .inbox)
            ]
        )
    }
}

enum FairNestTimelineBuilder {
    static func entries(now: Date, configuration: FairNestWidgetIntent, snapshot: WidgetHouseholdSnapshot) -> [FairNestWidgetEntry] {
        WidgetTimelineSchedule.reloadDates(now: now)
            .map { FairNestWidgetEntry(date: $0, configuration: configuration, snapshot: snapshot) }
    }
}

struct FairNestHomeWidget: Widget {
    let kind = FairNestShared.homeWidgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: FairNestWidgetIntent.self, provider: FairNestTimelineProvider()) { entry in
            FairNestWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
        }
        .configurationDisplayName("FairNest")
        .description("See the next shared responsibility, today’s load, or a weekly overview.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct FairNestWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    var entry: FairNestWidgetEntry

    var body: some View {
        Group {
            if entry.snapshot.syncPending {
                syncPendingView
            } else if entry.snapshot.cards.isEmpty {
                emptyView
            } else {
                switch entry.configuration.focus {
                case .next:
                    nextView
                case .today:
                    todayView
                case .week:
                    weeklyView
                }
            }
        }
        .redacted(reason: entry.redacted ? .placeholder : [])
        .widgetAccentable()
    }

    private var nextView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Next", systemImage: "house")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let card = entry.snapshot.nextResponsibility {
                Text(card.displayTitle)
                    .font(.headline)
                    .lineLimit(4)
                Spacer(minLength: 0)
                Text(card.owner.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var todayView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today’s home load")
                .font(.headline)
            ForEach(entry.snapshot.todayCards.prefix(3)) { card in
                HStack {
                    Image(systemName: card.type.symbolName)
                    Text(card.displayTitle)
                        .lineLimit(1)
                    Spacer()
                    Text(card.owner.label)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            if entry.snapshot.todayCards.isEmpty {
                Text("Nothing due today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var weeklyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weekly overview")
                .font(.headline)
            HStack {
                metric("Open", "\(entry.snapshot.cards.filter { $0.status != .done }.count)")
                metric("Today", "\(entry.snapshot.todayCards.count)")
                metric("Effort", "\(entry.snapshot.weeklyEffort)")
            }
            Divider()
            ForEach(entry.snapshot.cards.filter { $0.status != .done }.prefix(5)) { card in
                HStack {
                    Text(card.displayTitle)
                        .lineLimit(1)
                    Spacer()
                    Text(card.owner.label)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    private var syncPendingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sync pending", systemImage: "icloud.slash")
                .font(.headline)
            Text("Saved locally")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("FairNest", systemImage: "house")
                .font(.headline)
            Text("No cards yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
