import AppKit
import Vision

/// Renders each fixture string to an image and runs the app's OCR
/// (ScreenReader.recognize) over it (#213). Prints JSON lines:
/// {"id": ..., "expected": ..., "recognized": [...]}.
struct Fixture: Decodable {
    let id: String
    let text: String
}

struct FixturesFile: Decodable {
    let fixtures: [Fixture]
}

func render(_ text: String, width: CGFloat = 1400, height: CGFloat = 160) -> CGImage? {
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .natural
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 44),
        .foregroundColor: NSColor.black,
        .paragraphStyle: paragraph,
        // Render RTL strings in their natural direction.
        .writingDirection: [NSWritingDirection.natural.rawValue],
    ]
    let rect = NSRect(x: 20, y: 40, width: width - 40, height: height - 80)
    (text as NSString).draw(in: rect, withAttributes: attributes)
    image.unlockFocus()
    var rectOut = CGRect(origin: .zero, size: size)
    return image.cgImage(forProposedRect: &rectOut, context: nil, hints: nil)
}

let args = CommandLine.arguments
guard args.count > 1,
      let data = FileManager.default.contents(atPath: args[1]),
      let file = try? JSONDecoder().decode(FixturesFile.self, from: data) else {
    FileHandle.standardError.write("usage: ocr_bench fixtures.json\n".data(using: .utf8)!)
    exit(2)
}

for fixture in file.fixtures {
    guard let cg = render(fixture.text) else { continue }
    do {
        let lines = try ScreenReader.recognize(cg, in: CGSize(width: cg.width, height: cg.height))
        let recognized = lines.map { $0.line.text }
        let out: [String: Any] = [
            "id": fixture.id,
            "expected": fixture.text,
            "recognized": recognized,
        ]
        let json = try JSONSerialization.data(withJSONObject: out)
        FileHandle.standardOutput.write(json)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    } catch {
        FileHandle.standardError.write("\(fixture.id): \(error.localizedDescription)\n".data(using: .utf8)!)
    }
}
