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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Which room is this?").font(.title.weight(.bold)).foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    TextField("Room name", text: $name, prompt: Text("For example, Living room").foregroundStyle(Tokens.muted),
                              axis: .vertical)
                        .accessibilityLabel("Room name")
                        .accessibilityIdentifier("roomName")
                        .font(.title3).foregroundStyle(Tokens.ink)
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit { go() }
                        .frame(minHeight: Tokens.minTarget)
                        .glassCard(cornerRadius: 20, padding: 14)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Or pick one").font(.headline).foregroundStyle(Tokens.ink)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(common, id: \.self) { room in
                                Button(room) { name = room; go() }
                                    .buttonStyle(PillButtonStyle())
                            }
                        }
                    }
                    .glassCard()
                }
                .padding(20)
            }
            .recallScreen()
            .navigationTitle("Scan a room")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Text("Cancel").foregroundStyle(.white) }
                    .buttonStyle(.glassProminent).tint(Tokens.blueDeep) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { go() } label: { Text("Start").foregroundStyle(.white) }
                        .buttonStyle(.glassProminent).tint(Tokens.cta)
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
