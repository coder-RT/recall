import Foundation
import Testing
@testable import RecallDomain

@Suite("What text fields keep")
struct TextInputTests {
    @Test func aFieldStopsAtItsLimit() {
        #expect(TextInput.clean(String(repeating: "a", count: 500), limit: TextInput.question).count == 300)
        #expect(TextInput.clean("Living room", limit: TextInput.roomName) == "Living room")
    }

    @Test func pastedControlCharactersAndLineBreaksGo() {
        #expect(TextInput.clean("Living\u{0007} room\n", limit: 60) == "Living room")
        #expect(TextInput.clean("in the\nblue pouch\u{0000}", limit: 200, multiline: true) == "in the\nblue pouch")
    }

    @Test func bidiControlsArePastedAway() {
        // U+202E would show "txt.exe" as "exe.txt": a Cf format character, which controlCharacters includes
        #expect(TextInput.clean("key\u{202E}fdp.exe", limit: 60) == "keyfdp.exe")
        #expect(TextInput.clean("a\u{200F}b\u{2066}c", limit: 60) == "abc")
    }

    @Test func aKeyLongerThanTheFieldIsNoticed() {
        #expect(TextInput.keyTooLong(String(repeating: "k", count: 129)))
        #expect(!TextInput.keyTooLong(String(repeating: "k", count: 128) + "\n"))
    }

    @Test func emojiAndAccentsCountAsOneCharacterEach() {
        #expect(TextInput.clean("Café 🔑🔑", limit: 6) == "Café 🔑")
    }

    @Test func aHomeNameIsSentAsTheMacSpellsIt() {
        #expect(TextInput.homeId("My Flat") == "my-flat")
        #expect(TextInput.homeId("  Grandma's  house #2 ") == "grandma-s-house-2")
        #expect(TextInput.homeId("Łódź") == "lodz")  // spelt in the ASCII letters the Mac accepts, not dropped
        #expect(TextInput.homeId("Küche 2") == "kuche-2")
        #expect(TextInput.homeId("Квартира") == "kvartira")
        #expect(Connection(address: "", key: "", home: "  ").homeId == "flat")
        #expect(Connection(address: "", key: "", home: "Studio Flat").homeId == "studio-flat")
    }
}
