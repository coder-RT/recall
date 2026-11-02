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

    /// A line break typed into a one-line field: Return was pressed (fields that grow with large text type it).
    public static func pressedReturn(_ typed: String, multiline: Bool) -> Bool {
        !multiline && typed.contains(where: \.isNewline)
    }

    /// A pasted key longer than the field keeps: say so, rather than silently pairing with a cut key.
    public static func keyTooLong(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count > deviceKey
    }

    /// A home name as the Mac accepts it: lowercase letters, digits and dashes ("My Flat" → "my-flat").
    public static func homeId(_ text: String) -> String {
        // "Küche" becomes "kuche", "Łódź" "lodz" and "Квартира" "kvartira", rather than vanishing into the default
        // home (ICU's Any-Latin, then Latin-ASCII for letters like Ł that aren't a base letter plus an accent)
        let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
        let plain = latin.applyingTransform(StringTransform("Latin-ASCII"), reverse: false) ?? latin
        let words = plain.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return String(words.joined(separator: "-").prefix(homeId))
    }
}
