import AppIntents

enum FairNestWidgetFocus: String, AppEnum {
    case next
    case today
    case week

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Widget Focus")
    static let caseDisplayRepresentations: [FairNestWidgetFocus: DisplayRepresentation] = [
        .next: "Next Responsibility",
        .today: "Today",
        .week: "Weekly Overview"
    ]
}

struct FairNestWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "FairNest Widget"
    static let description = IntentDescription("Choose the FairNest household view to show.")

    @Parameter(title: "Focus", default: .next)
    var focus: FairNestWidgetFocus

    init() {
        focus = .next
    }
}
