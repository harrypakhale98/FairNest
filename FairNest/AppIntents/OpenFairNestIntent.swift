import AppIntents

struct OpenFairNestIntent: AppIntent {
    static let title: LocalizedStringResource = "Open FairNest"
    static let description = IntentDescription("Open FairNest to the home board.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}
