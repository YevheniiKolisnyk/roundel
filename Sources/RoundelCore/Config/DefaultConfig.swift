import Foundation

/// The documented config written on first launch. JSON has no comments, so the docs live in `_comment` fields,
/// which the decoder ignores like any other unknown field.
public enum DefaultConfig {
    public static let json = #"""
    {
      "_comment": [
        "Roundel configuration. Edit and save: changes are picked up automatically.",
        "If the file has an error, Roundel keeps the last working config and shows the problem (menu bar + log).",
        "",
        "version: always 1.",
        "settings.openMode: \"holdRelease\" (hold the hotkey, point, release) or \"clickRequired\" (tap the hotkey, then click).",
        "settings.dwellMs: hover time on a group before it opens, 100-1000 ms. Hover mode only.",
        "settings.centerDwellMs: hover time in the center before going back one level, 100-1000 ms. Hover mode only.",
        "",
        "ring: the sections, clockwise from the top. Every node has a unique \"id\", a \"title\", an optional \"icon\" and a \"type\":",
        "  \"action\": runs \"action\" with \"params\". In this version every action only writes a line to the log.",
        "  \"group\": opens a child ring made of \"children\". Groups can nest as deep as you like.",
        "",
        "icon: exactly one of",
        "  {\"symbol\": \"star.fill\"}          an SF Symbol name",
        "  {\"emoji\": \"🚀\"}                  one emoji",
        "  {\"image\": \"icons/my.png\"}        an image file, path relative to this folder",
        "Without an icon the first letter of the title is shown.",
        "",
        "Any field starting with _ (like this one) is ignored. Unknown fields are ignored too."
      ],
      "version": 1,
      "settings": {
        "openMode": "holdRelease",
        "dwellMs": 250,
        "centerDwellMs": 250
      },
      "ring": [
        {
          "type": "action",
          "id": "hello",
          "title": "Hello",
          "icon": { "symbol": "hand.wave" },
          "action": "log",
          "params": { "message": "Hello from Roundel" }
        },
        {
          "type": "group",
          "id": "tools",
          "title": "Tools",
          "icon": { "symbol": "wrench.and.screwdriver" },
          "_comment": "A group. Hover it for a moment (or click it in click mode) to open its children.",
          "children": [
            { "type": "action", "id": "tools.terminal", "title": "Terminal", "icon": { "symbol": "terminal" }, "action": "log" },
            { "type": "action", "id": "tools.notes", "title": "Notes", "icon": { "emoji": "📝" }, "action": "log" },
            {
              "type": "group",
              "id": "tools.more",
              "title": "More",
              "icon": { "symbol": "ellipsis.circle" },
              "children": [
                { "type": "action", "id": "more.alpha", "title": "Alpha", "icon": { "symbol": "a.circle" }, "action": "log" },
                { "type": "action", "id": "more.beta", "title": "Beta", "icon": { "symbol": "b.circle" }, "action": "log" }
              ]
            },
            { "type": "action", "id": "tools.calc", "title": "Calculator", "icon": { "symbol": "plus.forwardslash.minus" }, "action": "log" }
          ]
        },
        {
          "type": "action",
          "id": "rocket",
          "title": "Rocket",
          "icon": { "emoji": "🚀" },
          "action": "log"
        },
        {
          "type": "action",
          "id": "moon",
          "title": "Moon",
          "icon": { "symbol": "moon.fill" },
          "action": "log"
        },
        {
          "type": "action",
          "id": "star",
          "title": "Star",
          "action": "log",
          "_comment": "No icon: the first letter of the title is shown."
        }
      ]
    }
    """#

    /// The parsed default. Falls back to a one-node ring if the literal above is ever broken (a test guards that).
    public static let config: RoundelConfig = {
        if case .success(let config) = ConfigLoader.parse(Data(json.utf8)) { return config }
        return RoundelConfig(ring: [.action(ActionNode(id: "fallback", title: "Config error", action: "log"))])
    }()

    /// Writes the default config if `url` does not exist. Never overwrites. Returns whether it wrote.
    @discardableResult
    public static func writeIfMissing(at url: URL) throws -> Bool {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: url.path) else { return false }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url, options: .atomic)
        return true
    }
}
