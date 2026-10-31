import RecallDesign
import RecallDomain
import SwiftUI

/// "Why?": the sightings an answer rests on, each with the camera's view of it, when, how sure, and the models that
/// found and placed it. Read aloud as plain sentences; the picture is extra, never the only way to know.
struct EvidenceView: View {
    let answerId: String
    @Environment(\.container) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var evidence: Evidence?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let evidence {
                    Text(evidence.text).font(.title3.weight(.semibold)).foregroundStyle(Tokens.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(evidence.summary).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("evidence-summary")
                    ForEach(evidence.sightings) { SightingCard(sighting: $0) }
                    Text("Places come from the 3D scan, never from the language model; it only puts them into words.")
                        .font(.footnote).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
                } else if let error {
                    ErrorBox(text: error)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
                }
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.bottom, 24)
        }
        .recallScreen()
        .navigationTitle("Why Recall thinks so")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task {
            guard evidence == nil, let container else { return }
            do { evidence = try await container.evidenceSource().evidence(answer: answerId) } catch {
                self.error = UserMessage.explain(error)
            }
        }
    }
}

private struct SightingCard: View {
    let sighting: Sighting
    @Environment(\.container) private var container
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                    .clipShape(.rect(cornerRadius: 12))
                    .accessibilityLabel("The camera's view of the \(sighting.label)")
            }
            Text(sighting.spoken()).foregroundStyle(Tokens.ink).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sighting-\(sighting.observationId)")
        .task {
            guard image == nil, let path = sighting.cropPath, let container,
                  let data = try? await container.evidenceSource().crop(path: path) else { return }
            image = UIImage(data: data)
        }
    }
}
