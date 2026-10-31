import RecallDesign
import SwiftUI
import UIKit

/// An error shown on screen (not spoken) with a Copy button.
struct ErrorBox: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.body).foregroundStyle(Tokens.danger)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Button { UIPasteboard.general.string = text } label: {
                Label("Copy error", systemImage: "doc.on.doc").font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tokens.accent).frame(minHeight: 44)
            }
            .accessibilityLabel("Copy the error")
        }
        .card(padding: 14)
    }
}

/// Form section text in contrast-safe colours (the system's secondary grey is under 4.5:1 on the grouped background).
struct FormHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.muted).textCase(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct FormNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.footnote).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true) }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
