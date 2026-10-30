import RecallDesign
import RecallNetworking
import SwiftUI
import UIKit

/// After a scan: everything Recall found, the unsure ones first. Tapping one lets the user fix its name, colour,
/// height or note, confirm it, or remove it. The user's values win over what the models measured.
struct ReviewView: View {
    @Environment(AppModel.self) private var model
    @State private var objects: [RememberedObject] = []
    @State private var loading = true
    @State private var error: String?
    @State private var editing: RememberedObject?
    @State private var query = ""
    @State private var filter = Filter.all

    enum Filter { case all, unsure, checked }

    private var unsure: [RememberedObject] { objects.filter(\.needsReview) }
    private var shown: [RememberedObject] {
        objects.filter { o in
            (filter == .all || (filter == .unsure ? o.needsReview : o.confirmed))
                && (query.isEmpty || "\(o.title) \(o.label) \(o.place)".localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if loading {
                        ProgressView("Loading what Recall found…").frame(maxWidth: .infinity).padding(.vertical, 32)
                    } else if let error {
                        ErrorBox(text: error)
                        Button("Open Settings", systemImage: "gearshape") { model.tab = .settings }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.blueDark)
                            .buttonStyle(.glass).controlSize(.large)
                    } else if objects.isEmpty {
                        EmptyState("shippingbox", "Nothing remembered yet. Scan a room and upload it first.")
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                FilterChip("All", selected: filter == .all) { filter = .all }
                                FilterChip("To check (\(unsure.count))", selected: filter == .unsure) { filter = .unsure }
                                FilterChip("Checked", selected: filter == .checked) { filter = .checked }
                            }
                        }
                        SectionTitle(heading, count: shown.count == 1 ? "1 thing" : "\(shown.count) things")
                        if shown.isEmpty {
                            EmptyState("magnifyingglass", "Nothing matches.")
                        }
                        ForEach(shown) { obj in
                            Button { editing = obj } label: { ObjectRow(object: obj) }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens it to correct or confirm.")
                        }
                    }
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.bottom, 24)
            }
            .recallScreen()
            .navigationTitle("Found")
            .searchable(text: $query, prompt: "Search things or places")
            .task { await load() }
            .refreshable { await load() }
            .sheet(item: $editing) { obj in
                EditObjectView(object: obj) { await load() }
            }
        }
    }

    private var heading: String {
        switch filter {
        case .all: "Everything"
        case .unsure: "Please check"
        case .checked: "Checked by you"
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            Swatch(color: object.color)
            VStack(alignment: .leading, spacing: 3) {
                // the chip moves under the name when the text is large
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                layout {
                    Text(object.title.capitalizedFirst).font(.headline).foregroundStyle(Tokens.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    if object.needsReview {
                        Chip("Check", systemImage: "questionmark.circle.fill", color: Tokens.danger).fixedSize()
                    } else if object.confirmed {
                        Chip("Checked", systemImage: "checkmark.circle.fill", color: Tokens.cta).fixedSize()
                    }
                }
                Text(object.place.capitalizedFirst).font(.subheadline).foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.footnote).foregroundStyle(Tokens.muted)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Tokens.muted)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Tokens.minTarget)
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if object.confirmed { return "Checked by you" + (object.note.map { ". \($0)" } ?? "") }
        let sure = "\(Int((object.confidence * 100).rounded())) percent sure"
        return object.needsReview ? "Unsure, \(sure)" : sure.capitalizedFirst
    }
}

/// The object's colour as a round swatch (decoration: the colour is also in its name).
private struct Swatch: View {
    let color: String?
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Tokens.bluePale.opacity(0.7))
            if let c = color.flatMap(Self.colors.index(forKey:)).map({ Self.colors.values[$0] }) {
                Circle().fill(c).frame(width: 22, height: 22).overlay(Circle().stroke(Tokens.line, lineWidth: 1))
            } else {
                Image(systemName: "shippingbox").font(.title3.weight(.semibold)).foregroundStyle(Tokens.blueDark)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    static let colors: [String: Color] = [
        "black": .black, "white": .white, "grey": .gray, "gray": .gray, "red": .red, "orange": .orange,
        "yellow": .yellow, "green": .green, "blue": .blue, "purple": .purple, "pink": .pink, "brown": .brown,
        "beige": Color(red: 0.89, green: 0.82, blue: 0.69),
    ]
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
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recall saw a \(object.label), \(object.place).").font(.body).foregroundStyle(Tokens.ink)
                        if let size = object.sizeCm {
                            Text("About \(size[0]) by \(size[1]) by \(size[2]) centimetres.").font(.subheadline)
                                .foregroundStyle(Tokens.muted)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    TextField("Your name for it", text: $name, prompt: Text("e.g. work bag").foregroundStyle(Tokens.muted))
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("objectName")
                } header: { FormHeader("Your name for it") } footer: {
                    FormNote("Optional. You can then ask for it by this name.")
                }

                Section {
                    Picker("Colour", selection: $color) {
                        Text(object.measuredColor.map { "As seen: \($0)" } ?? "Not set").tag("")
                        ForEach(Self.colors, id: \.self) { Text($0.capitalizedFirst).tag($0) }
                    }
                    .tint(Tokens.blueDark)
                } footer: { FormNote("Helps tell two of the same thing apart.") }

                Section {
                    // the visible words are the spoken label; the value is read in centimetres
                    Stepper(String(format: "%.2f m", Double(heightCm) / 100), value: $heightCm, in: 0...300, step: 5)
                        .font(.body.monospacedDigit()).foregroundStyle(Tokens.ink)
                        .onChange(of: heightCm) { heightChanged = true }
                        .accessibilityValue("\(heightCm) centimetres")
                    if heightChanged {
                        Button("Use the measured height (\(String(format: "%.2f m", object.heightM)))") {
                            heightCm = Int((object.heightM * 100).rounded())
                            DispatchQueue.main.async { heightChanged = false }
                        }
                        .foregroundStyle(Tokens.blueDark)
                    }
                } header: { FormHeader("Height above the floor") } footer: { FormNote(heightNote) }

                Section {
                    TextField("Note", text: $note, prompt: Text("e.g. in the blue pouch").foregroundStyle(Tokens.muted),
                              axis: .vertical)
                } header: { FormHeader("Note") }

                if let error { Section { ErrorBox(text: error) } }

                Section {
                    Button("Not there, forget it", systemImage: "trash", role: .destructive) { confirmRemove = true }
                        .foregroundStyle(Tokens.danger)
                        .accessibilityHint("Removes it from memory.")
                        .disabled(busy)
                }
            }
            .navigationTitle(object.title.capitalizedFirst)
            .navigationBarTitleDisplayMode(.inline)
            .tint(Tokens.blueDark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Saving…" : "Save", role: .confirm) { Task { await save() } }
                        .buttonStyle(.glassProminent).tint(Tokens.cta)
                        .disabled(busy)
                        .accessibilityLabel("Save, it's right")
                        .accessibilityHint("Saves your changes and marks it as checked.")
                }
            }
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

/// Form section text in contrast-safe colours (the system's secondary grey is under 4.5:1 on the grouped background).
private struct FormHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.muted).textCase(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FormNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.footnote).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true) }
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
        .card(padding: 14)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
