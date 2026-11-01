import RecallDomain
import RecallDesign
import SwiftUI
import UIKit

/// Name the room before scanning; quick choices for the common ones.
struct RoomNameView: View {
    let start: (String) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private let common = ["Living room", "Kitchen", "Bedroom", "Hallway", "Bathroom", "Office"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Which room is this?").font(.title2.weight(.bold)).foregroundStyle(Tokens.ink)
                        .accessibilityAddTraits(.isHeader)
                    TextField("Room name", text: $name, prompt: Text("e.g. Living room").foregroundStyle(Tokens.muted),
                              axis: .vertical)
                        .accessibilityLabel("Room name")
                        .accessibilityIdentifier("roomName")
                        .limited($name, to: TextInput.roomName)
                        .font(.title3).foregroundStyle(Tokens.ink)
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit { go() }
                        .frame(minHeight: Tokens.minTarget - 16, alignment: .leading)
                        .card(padding: 16)
                    SectionTitle("Or pick one")
                        .padding(.top, 8)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 1 : 2),
                              spacing: 10) {
                        ForEach(common, id: \.self) { room in
                            Button { name = room; go() } label: {
                                HStack(spacing: 10) {
                                    IconTile(RoomIcon.for(room))
                                    Text(room).font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.ink)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .card(padding: 10)
                            }
                            .buttonStyle(.plainTap)
                        }
                    }
                }
                .padding(Tokens.gutter)
            }
            .recallScreen()
            .navigationTitle("New scan")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Tokens.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(role: .confirm) { go() } label: { Text("Start").foregroundStyle(Tokens.onGo) }
                    .buttonStyle(.glassProminent).tint(Tokens.go) }
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
