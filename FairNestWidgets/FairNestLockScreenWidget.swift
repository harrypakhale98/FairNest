import AppIntents
import SwiftUI
import WidgetKit

struct FairNestLockScreenWidget: Widget {
    let kind = FairNestShared.lockScreenWidgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: FairNestWidgetIntent.self, provider: FairNestTimelineProvider()) { entry in
            FairNestLockScreenWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
        }
        .configurationDisplayName("FairNest Check-In")
        .description("Shows the next responsibility or weekly check-in.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular])
    }
}

struct FairNestLockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: FairNestWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label(inlineText, systemImage: "house")
            default:
                VStack(alignment: .leading) {
                    Text("FairNest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(inlineText)
                        .font(.headline)
                        .lineLimit(2)
                }
                .widgetAccentable()
            }
        }
        .redacted(reason: entry.redacted ? .placeholder : [])
    }

    private var inlineText: String {
        if entry.snapshot.syncPending { return "Sync pending" }
        switch entry.configuration.focus {
        case .next:
            return entry.snapshot.nextResponsibility?.displayTitle ?? "Weekly check-in"
        case .today:
            let count = entry.snapshot.todayCards.count
            return count == 0 ? "Nothing due today" : "\(count) due today"
        case .week:
            let open = entry.snapshot.weeklyCards(now: entry.date).count
            return "\(open) open, effort \(entry.snapshot.weeklyEffortScore(now: entry.date))"
        }
    }
}
