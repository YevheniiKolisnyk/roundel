/// How the ring commits a selection.
public enum OpenMode: String, CaseIterable, Codable, Sendable {
    /// Ring opens on hotkey press; releasing the hotkey commits the highlighted section.
    case holdRelease
    /// Ring opens on hotkey press and stays open until a section is clicked.
    case clickRequired

    public var menuTitle: String {
        switch self {
        case .holdRelease: "Hover and release"
        case .clickRequired: "Hover and click"
        }
    }
}
