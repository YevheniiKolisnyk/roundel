import SwiftUI
import RoundelCore

/// What the stack shows right now. Updated by the presenter.
@MainActor
@Observable
final class ToastStackModel {
    var entries: [ToastQueue.Entry] = []
    var hiddenCount = 0
}

/// The toasts, newest on top, top-right aligned, with the margins ToastLayout gives the window. Toasts spring in from
/// above and fade out; with Reduce Motion they only fade.
struct ToastStackView: View {
    let model: ToastStackModel
    private let info = SurfaceInfo()
    private let metrics = DesignMetrics.standard

    var body: some View {
        let reduce = info.reduceMotion
        VStack(alignment: .trailing, spacing: metrics.toastSpacing) {
            ForEach(model.entries) { entry in
                ToastCard(message: entry.message)
                    .transition(reduce ? .opacity : .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                    ))
            }
            if model.hiddenCount > 0 {
                ToastMoreChip(count: model.hiddenCount).transition(.opacity)
            }
        }
        .padding(EdgeInsets(top: ToastLayout.insets.top, leading: ToastLayout.insets.left, bottom: ToastLayout.insets.bottom, trailing: ToastLayout.insets.right))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}
