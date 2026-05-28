import SwiftUI

enum FairNestStyle {
    static let cornerRadius: CGFloat = 8
    static let rowSpacing: CGFloat = 10
    static let horizontalInset: CGFloat = 16
}

struct OwnerBadge: View {
    var owner: CardOwner

    var body: some View {
        Label(owner.label, systemImage: owner.symbolName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Owner: \(owner.label)")
    }
}

struct StatusBadge: View {
    var status: CardStatus

    var body: some View {
        Text(status.label)
            .font(.caption)
            .foregroundStyle(status == .done ? .green : .secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Status: \(status.label)")
    }
}

struct EffortDots: View {
    @ScaledMetric(relativeTo: .caption) private var dotSize = 5
    var effort: Effort

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { value in
                    Circle()
                        .fill(value <= effort.rawValue ? Color.accentColor : Color.secondary.opacity(0.45))
                        .frame(width: dotSize, height: dotSize)
                }
            }
            Text(effort.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityLabel("Effort \(effort.label)")
    }
}

struct SectionFooterNote: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
