import RecallDesign
import RecallNetworking
import SwiftUI
import UIKit

/// After a scan: everything Recall found, the unsure ones first. Tapping one lets the user fix its name, colour,
/// height or note, confirm it, or remove it. The user's values win over what the models measured.
struct ReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var objects: [RememberedObject] = []
    @State private var loading = true
    @State private var error: String?
    @State private var editing: RememberedObject?

    private var unsure: [RememberedObject] { objects.filter(\.needsReview) }
    private var sure: [RememberedObject] { objects.filter { !$0.needsReview } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if loading {
                        ProgressView("Loading what Recall found…").frame(maxWidth: .infinity)
                    } else if let error {
                        ErrorBox(text: error)
                    } else if objects.isEmpty {
                        Text("Nothing remembered yet. Scan a room and upload it first.").foregroundStyle(Tokens.muted)
                    } else {
                        Text(summary).font(.body).foregroundStyle(Tokens.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !unsure.isEmpty {
                            Section("Please check", items: unsure)
                        }
                        if !sure.isEmpty {
                            Section(unsure.isEmpty ? "Found" : "Also found", items: sure)
                        }
                    }
                }
                .padding(20)
            }
            .background(Tokens.grey)
            .navigationTitle("What Recall found")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
            .refreshable { await load() }
            .sheet(item: $editing) { obj in
                EditObjectView(object: obj) { await load() }
            }
        }
    }

    private var summary: String {
        let n = objects.count
        let things = n == 1 ? "1 thing" : "\(n) things"
        return unsure.isEmpty
            ? "Recall remembers \(things). Tap one to rename it or add details."
            : "Recall remembers \(things). It's unsure about \(unsure.count); tap each to check it."
    }

    @ViewBuilder
    private func Section(_ title: String, items: [RememberedObject]) -> some View {
        Text(title).font(.title3.weight(.bold)).foregroundStyle(Tokens.ink).accessibilityAddTraits(.isHeader)
        ForEach(items) { obj in
            Button { editing = obj } label: { ObjectRow(object: obj) }
                .buttonStyle(.plain)
                .accessibilityHint("Opens it to correct or confirm.")
        }
    }

    private func load() async {
        guard let api = model.api else {
            error = model.setupProblem
            loading = false
            return
        }
        do {
            objects = try await api.objects(homeId: model.homeId)
                .sorted { ($0.needsReview ? 0 : 1, $0.title) < ($1.needsReview ? 0 : 1, $1.title) }
            error = nil
        } catch {
            self.error = APIError.explain(error)
        }
        loading = false
    }
}

private struct ObjectRow: View {
    let object: RememberedObject

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: object.needsReview ? "questionmark.circle.fill" : object.confirmed ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(object.needsReview ? Tokens.danger : object.confirmed ? Tokens.cta : Tokens.muted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(object.title.capitalizedFirst).font(.headline).foregroundStyle(Tokens.ink)
                Text(object.place.capitalizedFirst).font(.subheadline).foregroundStyle(Tokens.ink)
                Text(detail).font(.footnote).foregroundStyle(Tokens.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(Tokens.muted).accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: Tokens.minTarget, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(object.needsReview ? Tokens.danger : Tokens.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if object.confirmed { return "Checked by you" + (object.note.map { ". \($0)" } ?? "") }
        let sure = "\(Int((object.confidence * 100).rounded())) percent sure"
        return object.needsReview ? "Unsure, \(sure). Please check." : sure.capitalizedFirst
    }
}

/// One object: name, colour, height above the floor, a note; save (which also confirms it) or remove.
struct EditObjectView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let object: RememberedObject
    let saved: () async -> Void

    @State private var name: String
    @State private var color: String  // "" = as measured
    @State private var heightCm: Int
    @State private var heightChanged: Bool
    @State private var note: String
    @State private var busy = false
    @State private var error: String?
    @State private var confirmRemove = false

    static let colors = ["black", "white", "grey", "red", "orange", "yellow", "green", "blue", "purple", "pink", "brown", "beige"]

    init(object: RememberedObject, saved: @escaping () async -> Void) {
        self.object = object
        self.saved = saved
        _name = State(initialValue: object.name ?? "")
        _color = State(initialValue: object.measuredColor == nil ? (object.color ?? "") : "")
        _heightCm = State(initialValue: Int(((object.userHeightM ?? object.heightM) * 100).rounded()))
        _heightChanged = State(initialValue: object.userHeightM != nil)
        _note = State(initialValue: object.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recall saw a \(object.label), \(object.place).").font(.body).foregroundStyle(Tokens.ink)
                        if let size = object.sizeCm {
                            Text("About \(size[0]) by \(size[1]) by \(size[2]) centimetres.").font(.subheadline).foregroundStyle(Tokens.muted)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    LabeledField("Your name for it", note: "Optional, for example \"work bag\". You can then ask for it by this name.") {
                        TextField("Your name for it", text: $name, prompt: Text("e.g. work bag").foregroundStyle(Tokens.muted))
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("objectName")
                    }

                    LabeledField("Colour", note: "Helps tell two of the same thing apart.") {
                        Picker("Colour", selection: $color) {
                            Text(object.measuredColor.map { "As seen: \($0)" } ?? "Not set").tag("")
                            ForEach(Self.colors, id: \.self) { Text($0.capitalizedFirst).tag($0) }
                        }
                        .pickerStyle(.menu).tint(Tokens.blueDark)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    LabeledField("Height above the floor", note: heightNote) {
                        Stepper(value: $heightCm, in: 0...300, step: 5) {
                            Text(String(format: "%.2f m", Double(heightCm) / 100)).font(.body.monospacedDigit())
                        }
                        .onChange(of: heightCm) { heightChanged = true }
                        .accessibilityValue("\(heightCm) centimetres")
                    }
                    if heightChanged {
                        Button("Use the measured height (\(String(format: "%.2f m", object.heightM)))") {
                            heightCm = Int((object.heightM * 100).rounded())
                            DispatchQueue.main.async { heightChanged = false }
                        }
                        .font(.body.weight(.semibold)).foregroundStyle(Tokens.blueDark).frame(minHeight: 44)
                    }

                    LabeledField("Note", note: "Anything that helps, for example \"in the blue pouch\".") {
                        TextField("Note", text: $note, prompt: Text("Optional").foregroundStyle(Tokens.muted), axis: .vertical)
                    }

                    if let error { ErrorBox(text: error) }

                    BigButton(busy ? "Saving…" : "Save, it's right", systemImage: "checkmark",
                              hint: "Saves your changes and marks it as checked.") { Task { await save() } }
                        .disabled(busy)
                    BigButton("Not there, forget it", systemImage: "trash",
                              hint: "Removes it from memory.", style: .stop) { confirmRemove = true }
                        .disabled(busy)
                }
                .padding(20)
            }
            .background(Tokens.grey)
            .navigationTitle(object.title.capitalizedFirst)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .confirmationDialog("Forget the \(object.title)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Forget it", role: .destructive) { Task { await remove() } }
            }
        }
    }

    private var heightNote: String {
        object.userHeightM == nil
            ? "Measured \(String(format: "%.2f", object.heightM)) metres. Change it if that's wrong."
            : "You set this. The scan measured \(String(format: "%.2f", object.heightM)) metres."
    }

    private func save() async {
        guard let api = model.api else { error = model.setupProblem; return }
        busy = true
        defer { busy = false }
        var fix = ObjectFix()
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        fix.name = n.isEmpty ? .clear : .set(n)
        fix.color = color.isEmpty ? .clear : .set(color)
        fix.heightM = heightChanged ? .set(Double(heightCm) / 100) : .clear
        let t = note.trimmingCharacters(in: .whitespacesAndNewlines)
        fix.note = t.isEmpty ? .clear : .set(t)
        fix.confirmed = true
        do {
            try await api.correct(homeId: model.homeId, objectId: object.id, fix)
            model.announcer.say("Saved.")
            await saved()
            dismiss()
        } catch {
            self.error = APIError.explain(error)
        }
    }

    private func remove() async {
        guard let api = model.api else { error = model.setupProblem; return }
        busy = true
        defer { busy = false }
        do {
            try await api.remove(homeId: model.homeId, objectId: object.id)
            model.announcer.say("Forgotten.")
            await saved()
            dismiss()
        } catch {
            self.error = APIError.explain(error)
        }
    }
}

/// A heading, the control in a white box, and a note under it; the heading is the control's label.
private struct LabeledField<Content: View>: View {
    let title: String
    let note: String
    @ViewBuilder let content: Content
    init(_ title: String, note: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(Tokens.ink).accessibilityHidden(true)
            content
                .font(.body).foregroundStyle(Tokens.ink)
                .padding(14)
                .frame(minHeight: Tokens.minTarget)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Tokens.line, lineWidth: 1))
                .accessibilityLabel(title)
                .accessibilityHint(note)
            Text(note).font(.footnote).foregroundStyle(Tokens.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
    }
}

/// An error shown on screen (not spoken) with a Copy button.
struct ErrorBox: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.body).foregroundStyle(Tokens.danger)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Button { UIPasteboard.general.string = text } label: {
                Label("Copy error", systemImage: "doc.on.doc").font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tokens.blueDark).frame(minHeight: 44)
            }
            .accessibilityLabel("Copy the error")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
