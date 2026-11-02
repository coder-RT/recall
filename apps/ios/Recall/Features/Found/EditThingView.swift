import RecallDesign
import RecallDomain
import SwiftUI

/// One thing: name, colour, height above the floor, a note; save (which also confirms it) or forget it.
struct EditThingView: View {
    @Environment(ThingsModel.self) private var things
    @Environment(\.dismiss) private var dismiss
    let thing: Thing

    @State private var name: String
    @State private var color: String  // "" = as measured
    @State private var heightCm: Int
    @State private var heightChanged: Bool
    @State private var note: String
    @State private var busy = false
    @State private var error: String?
    @State private var confirmRemove = false

    init(thing: Thing) {
        self.thing = thing
        _name = State(initialValue: thing.name ?? "")
        _color = State(initialValue: thing.measuredColor == nil ? (thing.color ?? "") : "")
        _heightCm = State(initialValue: Int(((thing.userHeightM ?? thing.heightM) * 100).rounded()))
        _heightChanged = State(initialValue: thing.userHeightM != nil)
        _note = State(initialValue: thing.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recall saw a \(thing.label), \(thing.place).").font(.body).foregroundStyle(Tokens.ink)
                            if let size = thing.sizeCm, size.count == 3 {
                                Text("About \(size[0]) by \(size[1]) by \(size[2]) centimetres.").font(.subheadline)
                                    .foregroundStyle(Tokens.muted)
                            }
                            Text("\(thing.evidence) (SAM 3.1).").font(.subheadline).foregroundStyle(Tokens.muted)
                            if !thing.trusted {
                                Text("Recall won't mention it yet. Save to confirm it's there, or tell it it's not.")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.danger)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Section {
                        TextField("Your name for it", text: $name, prompt: Text("e.g. work bag").foregroundStyle(Tokens.muted))
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("objectName")
                            .limited($name, to: TextInput.thingName)
                    } header: { FormHeader("Your name for it") } footer: {
                        FormNote("Optional. You can then ask for it by this name.")
                    }

                    Section {
                        Picker("Colour", selection: $color) {
                            Text(thing.measuredColor.map { "As seen: \($0)" } ?? "Not set").tag("")
                            ForEach(Correction.colors, id: \.self) { Text($0.capitalizedFirst).tag($0) }
                        }
                        .tint(Tokens.accent)
                    } footer: { FormNote("Helps tell two of the same thing apart.") }

                    Section {
                        // the visible words are the spoken label; the value is read in centimetres
                        Stepper(String(format: "%.2f m", Double(heightCm) / 100), value: $heightCm, in: 0...300, step: 5)
                            .font(.body.monospacedDigit()).foregroundStyle(Tokens.ink)
                            .onChange(of: heightCm) { heightChanged = true }
                            .accessibilityValue("\(heightCm) centimetres")
                        if heightChanged {
                            Button("Use the measured height (\(String(format: "%.2f m", thing.heightM)))") {
                                heightCm = Int((thing.heightM * 100).rounded())
                                DispatchQueue.main.async { heightChanged = false }
                            }
                            .foregroundStyle(Tokens.accent)
                        }
                    } header: { FormHeader("Height above the floor") } footer: { FormNote(heightNote) }

                    Section {
                        TextField("Note", text: $note, prompt: Text("e.g. in the blue pouch").foregroundStyle(Tokens.muted),
                                  axis: .vertical)
                            .limited($note, to: TextInput.note, multiline: true)
                    } header: { FormHeader("Note") } footer: { FormNote("\(note.count) of \(TextInput.note) characters.") }

                    if let error { Section { ErrorBox(text: error) } }

                    Section {
                        Button("Not there, forget it", systemImage: "trash", role: .destructive) { confirmRemove = true }
                            .foregroundStyle(Tokens.danger)
                            .accessibilityHint("Removes it, and later scans won't bring it back here.")
                            .disabled(busy)
                    }
                }
                .listRowBackground(Tokens.card)
            }
            .recallScreen()
            .navigationTitle(thing.title.capitalizedFirst)
            .navigationBarTitleDisplayMode(.inline)
            .tint(Tokens.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { Task { await save() } } label: {
                        Text(busy ? "Saving…" : "Save").foregroundStyle(Tokens.onGo)
                    }
                    .buttonStyle(.glassProminent).tint(Tokens.go)
                    .disabled(busy)
                    .accessibilityLabel("Save, it's right")
                    .accessibilityHint("Saves your changes and marks it as checked.")
                }
            }
            .confirmationDialog("Forget the \(thing.title)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Forget it", role: .destructive) { Task { await remove() } }
            }
            .keyboardDismissable()  // scroll or Done hides the keyboard; a tap outside does too (KeyboardDismissal)
        }
    }

    private var heightNote: String {
        thing.userHeightM == nil
            ? "Measured \(String(format: "%.2f", thing.heightM)) metres. Change it if that's wrong."
            : "You set this. The scan measured \(String(format: "%.2f", thing.heightM)) metres."
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            try await things.save(thing, .from(name: name, color: color, heightCm: heightChanged ? heightCm : nil, note: note))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove() async {
        busy = true
        defer { busy = false }
        do {
            try await things.remove(thing)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
