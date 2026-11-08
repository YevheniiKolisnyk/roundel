import Foundation
import RoundelCore

// A diagnostic, not part of the app: prints what an image file holds and what Roundel's Compress makes of it.
// It only reads the file. Usage: swift run image-inspect /path/to/photo.jpg
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 1, !arguments[0].hasPrefix("-") else {
    FileHandle.standardError.write(Data("Usage: swift run image-inspect /path/to/image\n".utf8))
    exit(2)
}
let path = (arguments[0] as NSString).expandingTildeInPath
print(ImageInspector.inspect(URL(fileURLWithPath: path)).text)
