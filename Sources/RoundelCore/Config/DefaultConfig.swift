import Foundation

/// The documented config written on first launch. JSON has no comments, so the docs live in `_comment` fields,
/// which the decoder ignores like any other unknown field.
public enum DefaultConfig {
    public static let json = #"""
    {
      "_comment": [
        "Roundel configuration. Edit and save: changes are picked up automatically.",
        "If the file has an error, Roundel keeps the last working config and shows the problem (menu bar + log).",
        "A fresh copy of every example lives in config.example.json next to this file (rewritten on each launch).",
        "",
        "version: always 1.",
        "settings.openMode: \"holdRelease\" (hold the hotkey, point, release) or \"clickRequired\" (tap the hotkey, then click).",
        "settings.expandDelayMs: how long to hover a group before its arc opens, 0-1000 ms (default 120).",
        "Groups open as an arc around the section you point at; keep moving outwards to open deeper groups.",
        "In hold mode, release on an action to run it; release on a group, in a gap or in the center to cancel.",
        "In click mode, hovering also opens arcs; click an action to run it, click a group to pin its arc, click the center or outside to close.",
        "",
        "ring: the sections, clockwise from the top. Every node has a unique \"id\", a \"title\", an optional \"icon\" and a \"type\":",
        "  \"action\": runs \"action\" with \"params\".",
        "  \"group\": opens a child ring made of \"children\". Groups can nest as deep as you like.",
        "",
        "icon: exactly one of",
        "  {\"symbol\": \"star.fill\"}          an SF Symbol name",
        "  {\"emoji\": \"🚀\"}                  one emoji",
        "  {\"image\": \"icons/my.png\"}        an image file, path relative to this folder",
        "Without an icon an action shows its own default icon.",
        "A green dot on a section means that toggle is currently on.",
        "An action id Roundel does not know is shown dimmed and logged; it never breaks the config.",
        "",
        "Actions and their \"params\":",
        "  app.open           name (\"Calculator\") or bundleId (\"com.apple.Safari\"). bundleId is the exact one.",
        "  url.open           url, with a scheme (https://, mailto:, ...).",
        "  path.open          path of a file or folder; ~ is allowed.",
        "  shell.run          script, args (list; available as $1 $2 ...), cwd, timeoutSec (1-600, default 30),",
        "                     login (true runs zsh -lc so your PATH and Homebrew are loaded; default false).",
        "                     A non-zero exit shows stderr in a toast. The script runs as you, with your permissions.",
        "  shortcut.run       name of a Shortcut from the Shortcuts app, timeoutSec (default 60).",
        "                     The example below expects a Shortcut called \"Roundel Example\": create one, or change the name.",
        "  caffeinate.toggle  mode (\"display\" keeps the screen on, \"system\" lets it sleep), minutes (auto-off).",
        "  screen.lock        locks the screen.",
        "  appearance.toggle  switches light and dark. The first use asks to let Roundel control System Events (Automation).",
        "  dnd.toggle         macOS has no API for Do Not Disturb, so this runs the Shortcut named in \"shortcut\"",
        "                     (default \"Toggle Do Not Disturb\"). Create it in Shortcuts with the \"Set Focus\" action.",
        "  media.playPause, media.next, media.previous   media keys. The first use asks for the Accessibility permission.",
        "  volume.muteToggle  mutes or unmutes the current output device.",
        "  log                writes params.message to the log."
      ],
      "version": 1,
      "settings": {
        "openMode": "holdRelease",
        "expandDelayMs": 120
      },
      "ring": [
        {
          "type": "group",
          "id": "launch",
          "title": "Launch",
          "icon": { "symbol": "paperplane.fill" },
          "_comment": "A group. Point at it and its children open as an arc around it.",
          "children": [
            { "type": "action", "id": "launch.safari", "title": "Safari", "icon": { "symbol": "safari" },
              "action": "app.open", "params": { "bundleId": "com.apple.Safari" } },
            { "type": "action", "id": "launch.calculator", "title": "Calculator",
              "action": "app.open", "params": { "name": "Calculator" } },
            { "type": "action", "id": "launch.downloads", "title": "Downloads", "icon": { "emoji": "📥" },
              "action": "path.open", "params": { "path": "~/Downloads" } },
            { "type": "action", "id": "launch.say", "title": "Say hello",
              "action": "shell.run", "params": { "script": "say \"$1\"", "args": ["Hello from Roundel"] } },
            { "type": "action", "id": "launch.shortcut", "title": "Shortcut",
              "action": "shortcut.run", "params": { "name": "Roundel Example" } },
            {
              "type": "group",
              "id": "launch.links",
              "title": "Links",
              "icon": { "symbol": "link" },
              "children": [
                { "type": "action", "id": "links.github", "title": "GitHub", "icon": { "emoji": "🐙" },
                  "action": "url.open", "params": { "url": "https://github.com" } },
                { "type": "action", "id": "links.apple", "title": "Apple", "icon": { "symbol": "globe" },
                  "action": "url.open", "params": { "url": "https://www.apple.com" } }
              ]
            }
          ]
        },
        {
          "type": "group",
          "id": "system",
          "title": "System",
          "icon": { "symbol": "gearshape.fill" },
          "children": [
            { "type": "action", "id": "system.caffeinate", "title": "Caffeinate",
              "action": "caffeinate.toggle", "params": { "mode": "display" } },
            { "type": "action", "id": "system.dark", "title": "Dark Mode", "action": "appearance.toggle" },
            { "type": "action", "id": "system.mute", "title": "Mute", "action": "volume.muteToggle" },
            { "type": "action", "id": "system.lock", "title": "Lock Screen", "action": "screen.lock" },
            { "type": "action", "id": "system.dnd", "title": "Do Not Disturb",
              "action": "dnd.toggle", "params": { "shortcut": "Toggle Do Not Disturb" } }
          ]
        },
        {
          "type": "group",
          "id": "media",
          "title": "Media",
          "icon": { "symbol": "music.note" },
          "children": [
            { "type": "action", "id": "media.playpause", "title": "Play / Pause", "action": "media.playPause" },
            { "type": "action", "id": "media.next", "title": "Next", "action": "media.next" },
            { "type": "action", "id": "media.previous", "title": "Previous", "action": "media.previous" }
          ]
        },
        {
          "type": "action",
          "id": "hello",
          "title": "Hello",
          "icon": { "emoji": "👋" },
          "action": "log",
          "params": { "message": "Hello from Roundel" }
        }
      ]
    }
    """#

    /// What `config.example.json` contains: the same examples, plus a note that the file is overwritten.
    public static let exampleJSON: String = json.replacingOccurrences(
        of: "{\n",
        with: "{\n  \"_generated\": \"config.example.json is regenerated on every launch. Copy what you need into config.json; edits here are lost.\",\n",
        options: .anchored
    )

    public static let exampleFileName = "config.example.json"

    /// The parsed default. Falls back to a one-node ring if the literal above is ever broken (a test guards that).
    public static let config: RoundelConfig = {
        if case .success(let config) = ConfigLoader.parse(Data(json.utf8)) { return config }
        return RoundelConfig(ring: [.action(ActionNode(id: "fallback", title: "Config error", action: "log"))])
    }()

    /// Writes (or refreshes) `config.example.json` in `directory`. Never touches `config.json`.
    @discardableResult
    public static func writeExample(in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(exampleFileName)
        let data = Data(exampleJSON.utf8)
        if (try? Data(contentsOf: url)) != data {
            try data.write(to: url, options: .atomic)
        }
        return url
    }

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
