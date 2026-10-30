import RecallDesign
import SwiftUI
import UIKit

/// Name the room before scanning; quick choices for the common ones.
struct RoomNameView: View {
    let start: (String) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private let common = ["Living room", "Kitchen", "Bedroom", "Hallway", "Bathroom", "Office"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Room name", text: $name, prompt: Text("For example, Living room").foregroundStyle(Tokens.muted),
                              axis: .vertical)
                        .accessibilityLabel("Room name")
                        .accessibilityIdentifier("roomName")
                        .font(.title3).foregroundStyle(Tokens.ink)
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit { go() }
                } header: {
                    SectionHeader("Which room is this?")
                }
                Section {
                    ForEach(common, id: \.self) { room in
                        Button(room) { name = room; go() }
                            .foregroundStyle(Tokens.blueDark)
                            .frame(minHeight: 44)
                    }
                } header: { SectionHeader("Or pick one") }
            }
            .navigationTitle("Scan a room")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { go() }
                }
            }
        }
    }

    private func go() {
        let room = name.trimmingCharacters(in: .whitespaces)
        guard !room.isEmpty else {
            // a greyed-out Start would fail contrast and say nothing; this says what is missing
            UIAccessibility.post(notification: .announcement, argument: "Type a room name or pick one first.")
            focused = true
            return
        }
        start(room)
    }
}
