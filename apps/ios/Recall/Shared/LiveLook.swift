import ARKit
import RecallCapture
import RecallDesign
import SwiftUI

/// The chosen camera look over an ARKit camera view: nothing, the LiDAR's depth as heat, or edges like a scanner.
/// Redrawn ten times a second from the session's current frame; off with Reduce Motion for the edges (they flicker).
struct LiveLook: View {
    let session: ARSession
    let look: CameraLook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: CGImage?
    private static let filter = ScannerFilter()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            Group {
                if let image, look != .camera {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(look == .lidar ? 0.55 : 0.88)
                        .blendMode(look == .edges ? .screen : .normal)
                }
            }
            .onChange(of: context.date) { redraw() }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func redraw() {
        guard look != .camera, let frame = session.currentFrame else { image = nil; return }
        switch look {
        case .camera: image = nil
        case .lidar: image = frame.sceneDepth.flatMap { Self.filter.heat($0.depthMap) }
        case .edges: image = reduceMotion ? nil : Self.filter.edges(frame.capturedImage)
        }
    }
}

/// Camera · LiDAR · Edges.
struct LookChips: View {
    @Binding var look: CameraLook
    var choices: [CameraLook] = CameraLook.allCases

    var body: some View {
        HStack(spacing: 6) {
            ForEach(choices, id: \.self) { l in
                Button { look = l } label: {
                    Text(l.title).font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .foregroundStyle(look == l ? Color.black : Color.white)
                        .background(look == l ? Color.white : Color.black.opacity(0.55), in: Capsule())
                }
                .buttonStyle(.plainTap)
                .accessibilityLabel("\(l.title) view")
                .accessibilityHint(l.hint)
                .accessibilityAddTraits(look == l ? .isSelected : [])
                .accessibilityIdentifier("look-\(l.rawValue)")
            }
        }
    }
}
