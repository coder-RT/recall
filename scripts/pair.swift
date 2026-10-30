// Shows a pairing QR code: the iPhone's Camera app scans it and Recall fills in the Mac address, device key and home.
// The key is read from .env and goes only into the image, never to the terminal.
// Usage: swift scripts/pair.swift <mac-address> [home]
import AppKit
import CoreImage.CIFilterBuiltins
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/pair.swift <mac-address> [home]\n".utf8))
    exit(2)
}
let env = (try? String(contentsOfFile: ".env", encoding: .utf8)) ?? ""
let key = env.split(separator: "\n")
    .first { $0.hasPrefix("RECALL_DEVICE_KEY=") }
    .map { $0.dropFirst("RECALL_DEVICE_KEY=".count).trimmingCharacters(in: .whitespaces.union(["\"", "'"])) } ?? ""
guard !key.isEmpty else {
    FileHandle.standardError.write(Data("RECALL_DEVICE_KEY is missing from .env\n".utf8))
    exit(1)
}

var link = URLComponents()
link.scheme = "recall"
link.host = "pair"
link.queryItems = [URLQueryItem(name: "url", value: args[1]), URLQueryItem(name: "key", value: key),
                   URLQueryItem(name: "home", value: args.count > 2 ? args[2] : "flat")]

let filter = CIFilter.qrCodeGenerator()
filter.message = Data(link.url!.absoluteString.utf8)
filter.correctionLevel = "M"
let image = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
let rep = NSBitmapImageRep(ciImage: image)
let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("recall-pair.png")
try rep.representation(using: .png, properties: [:])!.write(to: out)
print("Scan the QR code with the iPhone's Camera app, then tap the Recall banner.")
print("Mac address in it: \(args[1])   (the key is in the image only; delete \(out.path) afterwards)")
NSWorkspace.shared.open(out)
