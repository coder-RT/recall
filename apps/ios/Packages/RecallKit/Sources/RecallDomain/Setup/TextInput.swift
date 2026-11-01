import Foundation

/// What each text field accepts. The limits are the Mac's (resources/schemas; a test checks them against the
/// bundled openapi.json), so the phone never sends what the Mac would refuse. One-line fields drop line breaks;
/// no field keeps control characters (pasted text can carry them).
public enum TextInput {
    public static let question = 300  // AskRequest.question
    public static let roomName = 60  // ScanCreate.room
    public static let thingName = 40  // ObjectCorrection.name
    public static let note = 200  // ObjectCorrection.note
    public static let homeId = 64  // the home_id pattern
    public static let address = 300
    public static let deviceKey = 128
    public static let search = 60

    /// The text as the field keeps it: no control characters (line breaks only where `multiline`), at most `limit`.
    public static func clean(_ text: String, limit: Int, multiline: Bool = false) -> String {
        let kept = text.unicodeScalars.filter { s in
            (multiline && s == "\n") || !CharacterSet.controlCharacters.contains(s)
        }
        return String(String(String.UnicodeScalarView(kept)).prefix(limit))
    }

    /// A home name as the Mac accepts it: lowercase letters, digits and dashes ("My Flat" → "my-flat").
    public static func homeId(_ text: String) -> String {
        let words = text.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return String(words.joined(separator: "-").prefix(homeId))
    }
}
