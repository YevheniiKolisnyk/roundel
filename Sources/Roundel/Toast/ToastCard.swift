import SwiftUI
import RoundelCore

/// One toast: a status icon, a title and, when there is more to say, a smaller secondary line, on a surface.
struct ToastCard: View {
    let message: ToastMessage
    private let info = SurfaceInfo()
    private let metrics = DesignMetrics.standard

    var body: some View {
        HStack(alignment: .top, spacing: metrics.space3) {
            icon
                .frame(width: metrics.toastIconSize, height: metrics.toastIconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.title)
                    .font(.system(size: metrics.titleSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = message.detail {
                    Text(detail)
                        .font(.system(size: metrics.bodySize))
                        .foregroundStyle(Color.primary.opacity(info.traits.secondaryTextOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(metrics.toastPadding)
        .frame(width: metrics.toastWidth, alignment: .leading)
        .roundelSurface(in: RoundedRectangle(cornerRadius: metrics.toastCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var icon: some View {
        switch message.kind {
        case .progress:
            ProgressView().controlSize(.small)
        case .success:
            symbol("checkmark.circle.fill", .green)
        case .warning:
            symbol("exclamationmark.triangle.fill", .orange)
        case .error:
            symbol("xmark.circle.fill", .red)
        }
    }

    private func symbol(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: metrics.toastIconSize, weight: .medium))
            .foregroundStyle(color)
    }

    private var accessibilityText: String {
        let kind: String
        switch message.kind {
        case .success: kind = "Done"
        case .warning: kind = "Warning"
        case .error: kind = "Error"
        case .progress: kind = "In progress"
        }
        return ([kind, message.title] + (message.detail.map { [$0.replacingOccurrences(of: "\n", with: ". ")] } ?? [])).joined(separator: ". ")
    }
}

/// "+2 more" under the stack, for toasts waiting out of view.
struct ToastMoreChip: View {
    let count: Int
    private let info = SurfaceInfo()
    private let metrics = DesignMetrics.standard

    var body: some View {
        Text("+\(count) more")
            .font(.system(size: metrics.captionSize, weight: .medium))
            .foregroundStyle(Color.primary.opacity(info.traits.secondaryTextOpacity))
            .padding(.horizontal, metrics.space3)
            .frame(height: metrics.toastMoreChipHeight)
            .roundelSurface(in: Capsule(style: .continuous))
            .accessibilityLabel("\(count) more notifications waiting")
    }
}
