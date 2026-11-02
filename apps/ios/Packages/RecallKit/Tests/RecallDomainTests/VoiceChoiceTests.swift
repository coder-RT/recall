import Foundation
import Testing
@testable import RecallDomain

@Suite("Choosing the voice")
struct VoiceChoiceTests {
    private let voices = [
        VoiceOption(id: "daniel", name: "Daniel", language: "en-GB", quality: 0, gender: .male),
        VoiceOption(id: "ava-p", name: "Ava", language: "en-US", quality: 2, gender: .female),
        VoiceOption(id: "serena-p", name: "Serena", language: "en-GB", quality: 2, gender: .female),
        VoiceOption(id: "jamie-e", name: "Jamie", language: "en-GB", quality: 1, gender: .male),
        VoiceOption(id: "bells", name: "Bells", language: "en-US", quality: 2, gender: .unspecified, special: true),
        VoiceOption(id: "anna", name: "Anna", language: "de-DE", quality: 2, gender: .female),
    ]

    @Test func automaticPicksTheBestQualityInTheOwnersRegion() {
        #expect(VoiceChoice.best(voices, preference: .automatic, language: "en-GB")?.id == "serena-p")
        #expect(VoiceChoice.best(voices, preference: .automatic, language: "en-US")?.id == "ava-p")
    }

    @Test func aGenderPreferenceIsHonouredAndFallsBackRatherThanGoingSilent() {
        #expect(VoiceChoice.best(voices, preference: .male, language: "en-GB")?.id == "jamie-e")  // enhanced beats default
        #expect(VoiceChoice.best(voices, preference: .female, language: "en-GB")?.id == "serena-p")
        let onlyFemale = voices.filter { $0.gender != .male }
        #expect(VoiceChoice.best(onlyFemale, preference: .male, language: "en-GB")?.id == "serena-p")
    }

    @Test func noveltyVoicesAndOtherLanguagesAreNeverChosen() {
        let funny = [VoiceOption(id: "bells", name: "Bells", language: "en-US", quality: 2, gender: .unspecified, special: true)]
        #expect(VoiceChoice.best(funny, preference: .automatic, language: "en-US") == nil)
        #expect(VoiceChoice.best(voices, preference: .automatic, language: "de-DE")?.id == "anna")
    }

    @Test func aVoiceSaysItsQuality() {
        #expect(voices[1].title == "Ava (Premium)")
        #expect(voices[0].title == "Daniel")
    }
}
