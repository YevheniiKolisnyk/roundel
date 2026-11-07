import AppKit
import SwiftUI

/// What the ring does with a file drag that is over its panel.
@MainActor
protocol RingDropDelegate: AnyObject {
    /// `.copy` while the pointer is over a section that takes files, otherwise `[]` (the drag is refused and returns).
    func dragOperation() -> NSDragOperation
    /// The files were dropped. Returns whether they were accepted.
    func performDrop(_ urls: [URL]) -> Bool
    /// The drag session ended.
    func dragFinished()
}

/// The ring's view, registered as a destination for file drags. It covers the whole panel; the panel only receives a
/// drag where the footprint is painted (see `FootprintView`), so gaps and the empty space around arcs are not targets.
/// Which section is under the pointer is decided by the delegate from the ring layout, not by this view.
final class DropHostingView: NSHostingView<RingView> {
    weak var dropDelegate: RingDropDelegate?

    required init(rootView: RingView) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        MainActor.assumeIsolated { dropDelegate?.dragOperation() ?? [] }
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        MainActor.assumeIsolated { dropDelegate?.dragOperation() ?? [] }
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        MainActor.assumeIsolated { !(dropDelegate?.dragOperation() ?? []).isEmpty }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return MainActor.assumeIsolated { dropDelegate?.performDrop(urls) ?? false }
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        MainActor.assumeIsolated { dropDelegate?.dragFinished() }
    }
}
